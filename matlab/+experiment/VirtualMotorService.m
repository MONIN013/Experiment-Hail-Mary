classdef VirtualMotorService < handle
  properties (Access = private)
    plc_transport
    vm_transport
  end

  methods
    function obj = VirtualMotorService(plc_transport, vm_transport)
      if ~isa(plc_transport, "twincat_ads.IAdsTransport")
        error("experiment:service:invalidDependency", ...
          "plc_transport must implement twincat_ads.IAdsTransport.");
      end
      if ~isa(vm_transport, "twincat_ads.IAdsTransport")
        error("experiment:service:invalidDependency", ...
          "vm_transport must implement twincat_ads.IAdsTransport.");
      end
      obj.plc_transport = plc_transport;
      obj.vm_transport = vm_transport;
    end

    function out = run(obj, cfg)
      if ~isa(cfg, "experiment.RunConfig")
        cfg = experiment.RunConfig.fromStruct(cfg);
      end
      obj.ensure_folder(fileparts(cfg.save_path));

      plc_symbols = experiment.VirtualMotorSymbols.fromDefaults();
      vm_symbols = experiment.VirtualMotorSymbols.fromPrefix(cfg.vm_param_symbol_prefix);
      twincat_ads.SymbolBrowser.validateSymbols(obj.plc_transport, plc_symbols.required_probes);
      twincat_ads.SymbolBrowser.validateSymbols(obj.vm_transport, vm_symbols.required_probes);
      t = plc_symbols.types;

      vm_params = struct();
      vm_params.m = cfg.m;
      vm_params.d = cfg.d;
      vm_params.kt = cfg.kt;
      vm_params.tau_limit = cfg.tau_limit;
      vm_params.vel_limit = cfg.vel_limit;
      vm_params.task_dt_ns = cfg.task_dt_ns;
      obj.write_vm_params(vm_symbols, vm_params);

      profile = cfg.current_profile(:);
      use_profile = ~isempty(profile);
      t_run = tic;
      if use_profile
        profile_n = numel(profile);
        if profile_n > double(cfg.cmd_max_n)
          error("experiment:service:invalidProfile", ...
            "current_profile length (%d) exceeds cmd_max_n (%d).", profile_n, cfg.cmd_max_n);
        end

        obj.plc_transport.writeScalar(plc_symbols.start, false, t.bool);
        obj.plc_transport.writeScalar(plc_symbols.cmd_idx, uint32(0), t.u32);
        obj.plc_transport.writeScalar(plc_symbols.cmd_len, uint32(0), t.u32);
        obj.pulse_reset(plc_symbols, 0.02);

        idle_ready = obj.wait_for_reset_idle(plc_symbols, cfg.reset_timeout_s);
        if ~idle_ready
          warning("experiment:service:resetSyncTimeout", ...
            "Timed out waiting reset idle state (wr_idx==0, cmd_idx==0, start flag == FALSE).");
        end

        obj.plc_transport.writeArray(plc_symbols.cmd_profile, profile, t.double);
        obj.plc_transport.writeScalar(plc_symbols.cmd_len, uint32(profile_n), t.u32);
        obj.plc_transport.writeScalar(plc_symbols.start, true, t.bool);

        if cfg.wait_for_done
          done = obj.wait_until_done(plc_symbols, cfg.done_timeout_s);
          if ~done
            warning("experiment:service:timeout", "Timed out waiting for experiment completion.");
          end
        else
          while toc(t_run) < cfg.hold_seconds
            pause(min(0.05, cfg.hold_seconds / 10 + eps));
          end
        end
      else
        obj.plc_transport.writeScalar(plc_symbols.current_in, cfg.current_in, t.double);
        while toc(t_run) < cfg.hold_seconds
          pause(min(0.05, cfg.hold_seconds / 10 + eps));
        end
        if cfg.release_to_zero
          obj.plc_transport.writeScalar(plc_symbols.current_in, 0.0, t.double);
        end
      end
      elapsed_s = toc(t_run);

      position_last = obj.plc_transport.readScalar(plc_symbols.position_out, t.double);
      current_last = obj.plc_transport.readScalar(plc_symbols.current_in, t.double);
      velocity_last = obj.plc_transport.readScalar(plc_symbols.velocity_out, t.double);

      raw = struct();
      raw.position_last = double(position_last);
      raw.current_last = double(current_last);
      raw.velocity_last = double(velocity_last);

      [log_data, log_read_time] = obj.read_upper_logs(plc_symbols, cfg.log_n);
      raw.log_seq = log_data.log_seq;
      raw.log_i = log_data.log_i;
      raw.log_x = log_data.log_x;
      raw.log_t = log_data.log_t;
      raw.log_wr_idx = log_data.wr_idx;
      raw.log_overflow = log_data.overflow;

      cmd = struct();
      cmd.current_in = cfg.current_in;
      cmd.current_profile = profile;
      cmd.use_profile = use_profile;
      cmd.hold_seconds = cfg.hold_seconds;
      cmd.release_to_zero = cfg.release_to_zero;

      host = struct();
      host.elapsed_s = elapsed_s;
      host.log_read_time_s = log_read_time;

      cfg_struct = cfg.toStruct();
      metrics = experiment.preload_eval(raw, cmd, cfg_struct);
      config = cfg_struct;
      save(cfg.save_path, "raw", "cmd", "host", "metrics", "config");

      out = struct();
      out.raw = raw;
      out.cmd = cmd;
      out.host = host;
      out.metrics = metrics;
      out.config = config;
      out.save_path = cfg.save_path;
    end
  end

  methods (Access = private)
    function write_vm_params(obj, symbols, params)
      t = symbols.types;
      obj.vm_transport.writeScalar(symbols.vm_params.m, params.m, t.double);
      obj.vm_transport.writeScalar(symbols.vm_params.d, params.d, t.double);
      obj.vm_transport.writeScalar(symbols.vm_params.kt, params.kt, t.double);
      obj.vm_transport.writeScalar(symbols.vm_params.tau_limit, params.tau_limit, t.double);
      obj.vm_transport.writeScalar(symbols.vm_params.vel_limit, params.vel_limit, t.double);
      obj.vm_transport.writeScalar(symbols.vm_params.task_dt_ns, uint64(params.task_dt_ns), t.u64);
    end

    function pulse_reset(obj, symbols, pulse_seconds)
      t = symbols.types;
      obj.plc_transport.writeScalar(symbols.reset, true, t.bool);
      pause(pulse_seconds);
      obj.plc_transport.writeScalar(symbols.reset, false, t.bool);
    end

    function done = wait_until_done(obj, symbols, timeout_s)
      t = symbols.types;
      t0 = tic;
      done = false;
      while toc(t0) < timeout_s
        try
          exp_start = logical(obj.plc_transport.readScalar(symbols.start, t.bool));
          done = ~exp_start;
        catch
          done = false;
        end
        if done
          return;
        end
        pause(0.01);
      end
    end

    function ready = wait_for_reset_idle(obj, symbols, timeout_s)
      t = symbols.types;
      t0 = tic;
      ready = false;
      while toc(t0) < timeout_s
        try
          wr_idx = double(obj.plc_transport.readScalar(symbols.log.wr_idx, t.u32));
          cmd_idx = double(obj.plc_transport.readScalar(symbols.cmd_idx, t.u32));
          exp_start = logical(obj.plc_transport.readScalar(symbols.start, t.bool));
          ready = (wr_idx == 0) && (cmd_idx == 0) && (~exp_start);
        catch
          ready = false;
        end
        if ready
          return;
        end
        pause(0.01);
      end
    end

    function [log_data, read_time] = read_upper_logs(obj, symbols, log_n)
      t = symbols.types;
      t_read = tic;
      log_data = struct( ...
        "log_seq", zeros(0, 1), ...
        "log_i", zeros(0, 1), ...
        "log_x", zeros(0, 1), ...
        "log_t", zeros(0, 1), ...
        "wr_idx", 0, ...
        "overflow", false);

      try
        wr_idx = obj.plc_transport.readScalar(symbols.log.wr_idx, t.u32);
        overflow = obj.plc_transport.readScalar(symbols.log.overflow, t.bool);
        valid_n = uint32(min(double(wr_idx), log_n));
        if valid_n > 0
          log_data.log_seq = double(obj.plc_transport.readArray(symbols.log.log_seq, t.u32, valid_n));
          log_data.log_i = double(obj.plc_transport.readArray(symbols.log.log_i, t.double, valid_n));
          log_data.log_x = double(obj.plc_transport.readArray(symbols.log.log_x, t.double, valid_n));
          log_data.log_t = double(obj.plc_transport.readArray(symbols.log.log_t, t.u64, valid_n));
        end
        log_data.wr_idx = double(wr_idx);
        log_data.overflow = logical(overflow);
      catch
        warning("experiment:service:logUnavailable", ...
          "Logging symbols may be absent; keeping empty logs.");
      end
      read_time = toc(t_read);
    end

    function ensure_folder(~, path_value)
      if strlength(string(path_value)) == 0
        return;
      end
      if ~exist(path_value, "dir")
        mkdir(path_value);
      end
    end
  end
end
