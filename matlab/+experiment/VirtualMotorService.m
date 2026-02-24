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
        cfg = experiment.RunConfig.from_struct(cfg);
      end
      obj.ensure_folder(fileparts(cfg.save_path));

      plc_symbols = experiment.VirtualMotorSymbols.from_defaults();
      vm_symbols = experiment.VirtualMotorSymbols.from_prefix(cfg.vm_param_symbol_prefix);
      twincat_ads.SymbolBrowser.validate_symbols(obj.plc_transport, plc_symbols.required_probes);
      twincat_ads.SymbolBrowser.validate_symbols(obj.vm_transport, vm_symbols.required_probes);
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
      log_data = struct( ...
        "log_seq", zeros(0, 1), ...
        "log_i", zeros(0, 1), ...
        "log_x", zeros(0, 1), ...
        "log_t", zeros(0, 1), ...
        "log_cmd_idx", zeros(0, 1), ...
        "log_cmd_value", zeros(0, 1), ...
        "wr_idx", 0, ...
        "overflow", false);
      log_read_time = 0;
      host_log_stats = struct( ...
        "log_read_time_s_total", 0, ...
        "log_stream_cycles", 0, ...
        "log_stream_enabled", false, ...
        "log_samples_captured", 0, ...
        "log_stream_fallback_used", false, ...
        "log_stream_error_identifier", "", ...
        "log_stream_error_message", "");
      t_run = tic;
      if use_profile
        profile_n = numel(profile);
        if profile_n > double(cfg.cmd_max_n)
          error("experiment:service:invalidProfile", ...
            "current_profile length (%d) exceeds cmd_max_n (%d).", profile_n, cfg.cmd_max_n);
        end

        obj.plc_transport.write_scalar(plc_symbols.start, false, t.bool);
        obj.plc_transport.write_scalar(plc_symbols.cmd_idx, uint32(0), t.u32);
        obj.plc_transport.write_scalar(plc_symbols.cmd_len, uint32(0), t.u32);
        obj.pulse_reset(plc_symbols, 0.02);

        idle_ready = obj.wait_for_reset_idle(plc_symbols, cfg.reset_timeout_s);
        if ~idle_ready
          warning("experiment:service:resetSyncTimeout", ...
            "Timed out waiting reset idle state (wr_idx==0, cmd_idx==0, start flag == FALSE).");
        end

        obj.plc_transport.write_array(plc_symbols.cmd_profile, profile, t.double);
        obj.plc_transport.write_scalar(plc_symbols.cmd_len, uint32(profile_n), t.u32);
        obj.plc_transport.write_scalar(plc_symbols.start, true, t.bool);

        if cfg.wait_for_done && cfg.log_stream_enable
          [done, log_data, host_log_stats] = obj.wait_until_done_streaming(plc_symbols, cfg);
          log_read_time = host_log_stats.log_read_time_s_total;
          if ~done
            warning("experiment:service:timeout", "Timed out waiting for experiment completion.");
          end
        elseif cfg.wait_for_done
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
        obj.plc_transport.write_scalar(plc_symbols.current_in, cfg.current_in, t.double);
        while toc(t_run) < cfg.hold_seconds
          pause(min(0.05, cfg.hold_seconds / 10 + eps));
        end
        if cfg.release_to_zero
          obj.plc_transport.write_scalar(plc_symbols.current_in, 0.0, t.double);
        end
      end
      elapsed_s = toc(t_run);

      position_last = obj.plc_transport.read_scalar(plc_symbols.position_out, t.double);
      current_last = obj.plc_transport.read_scalar(plc_symbols.current_in, t.double);
      velocity_last = obj.plc_transport.read_scalar(plc_symbols.velocity_out, t.double);

      raw = struct();
      raw.position_last = double(position_last);
      raw.current_last = double(current_last);
      raw.velocity_last = double(velocity_last);

      if ~(use_profile && cfg.wait_for_done && cfg.log_stream_enable && host_log_stats.log_stream_enabled)
        [log_data, log_read_time] = obj.read_upper_logs(plc_symbols, cfg.log_n);
      end
      raw.log_seq = log_data.log_seq;
      raw.log_i = log_data.log_i;
      raw.log_x = log_data.log_x;
      raw.log_t = log_data.log_t;
      raw.log_cmd_idx = log_data.log_cmd_idx;
      raw.log_cmd_value = log_data.log_cmd_value;
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
      host.log_read_time_s_total = host_log_stats.log_read_time_s_total;
      host.log_stream_cycles = host_log_stats.log_stream_cycles;
      host.log_stream_enabled = host_log_stats.log_stream_enabled;
      host.log_samples_captured = host_log_stats.log_samples_captured;
      host.log_stream_fallback_used = logical(host_log_stats.log_stream_fallback_used);
      host.log_stream_error_identifier = char(string(host_log_stats.log_stream_error_identifier));
      host.log_stream_error_message = char(string(host_log_stats.log_stream_error_message));

      cfg_struct = cfg.to_struct();
      metrics = experiment.preload_eval(raw, cmd, cfg_struct);
      if use_profile && cfg.wait_for_done && ~logical(cfg.log_require_waveform_exact) && ...
          isfield(metrics, "acceptance") && isfield(metrics.acceptance, "input_waveform_exact_match") && ...
          ~logical(metrics.acceptance.input_waveform_exact_match)
        metrics.notes{end + 1, 1} = ...
          "Waveform exact-match enforcement disabled by config (log_require_waveform_exact=false); diagnostics retained.";
      end
      obj.enforce_log_requirements(metrics, raw, cmd, cfg, host);
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
      obj.vm_transport.write_scalar(symbols.vm_params.m, params.m, t.double);
      obj.vm_transport.write_scalar(symbols.vm_params.d, params.d, t.double);
      obj.vm_transport.write_scalar(symbols.vm_params.kt, params.kt, t.double);
      obj.vm_transport.write_scalar(symbols.vm_params.tau_limit, params.tau_limit, t.double);
      obj.vm_transport.write_scalar(symbols.vm_params.vel_limit, params.vel_limit, t.double);
      obj.vm_transport.write_scalar(symbols.vm_params.task_dt_ns, uint64(params.task_dt_ns), t.u64);
    end

    function pulse_reset(obj, symbols, pulse_seconds)
      t = symbols.types;
      obj.plc_transport.write_scalar(symbols.reset, true, t.bool);
      pause(pulse_seconds);
      obj.plc_transport.write_scalar(symbols.reset, false, t.bool);
    end

    function done = wait_until_done(obj, symbols, timeout_s)
      t = symbols.types;
      t0 = tic;
      done = false;
      while toc(t0) < timeout_s
        try
          exp_start = logical(obj.plc_transport.read_scalar(symbols.start, t.bool));
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

    function [done, log_data, host_stats] = wait_until_done_streaming(obj, symbols, cfg)
      t = symbols.types;
      t0 = tic;
      done = false;
      ring_n = obj.read_log_ring_capacity(symbols, cfg);
      state = obj.init_log_stream_state();
      host_stats = struct( ...
        "log_read_time_s_total", 0, ...
        "log_stream_cycles", 0, ...
        "log_stream_enabled", true, ...
        "log_samples_captured", 0, ...
        "log_stream_fallback_used", false, ...
        "log_stream_error_identifier", "", ...
        "log_stream_error_message", "");

      while toc(t0) < cfg.done_timeout_s
        try
          wr_idx = double(obj.plc_transport.read_scalar(symbols.log.wr_idx, t.u32));
          plc_overflow = logical(obj.plc_transport.read_scalar(symbols.log.overflow, t.bool));
          exp_start = logical(obj.plc_transport.read_scalar(symbols.start, t.bool));
          [state, local_overflow] = obj.drain_log_ring_to_host(symbols, cfg, ring_n, state, wr_idx);
          if local_overflow && cfg.log_warn_on_overflow && ~state.overflow_warned
            warning("experiment:service:logOverflow", ...
              "Host log consumer fell behind PLC ring buffer capacity; some samples were overwritten.");
            state.overflow_warned = true;
          end
          state.overflow = state.overflow || plc_overflow || local_overflow;
          host_stats.log_stream_cycles = host_stats.log_stream_cycles + 1;
          done = ~exp_start;
          if done
            try
              wr_idx_final = double(obj.plc_transport.read_scalar(symbols.log.wr_idx, t.u32));
              plc_overflow_final = logical(obj.plc_transport.read_scalar(symbols.log.overflow, t.bool));
              [state, local_overflow_final] = obj.drain_log_ring_to_host(symbols, cfg, ring_n, state, wr_idx_final);
              if local_overflow_final && cfg.log_warn_on_overflow && ~state.overflow_warned
                warning("experiment:service:logOverflow", ...
                  "Host log consumer fell behind PLC ring buffer capacity; some samples were overwritten.");
                state.overflow_warned = true;
              end
              state.overflow = state.overflow || plc_overflow_final || local_overflow_final;
              wr_idx = wr_idx_final;
            catch e_final
              if strcmp(string(e_final.identifier), "experiment:service:hostLogLimit")
                rethrow(e_final);
              end
              if cfg.log_stream_require_success
                obj.raise_streaming_failure(e_final, host_stats);
              end
              host_stats.log_stream_enabled = false;
              host_stats.log_stream_fallback_used = true;
              host_stats.log_stream_error_identifier = char(string(e_final.identifier));
              host_stats.log_stream_error_message = char(string(e_final.message));
            end
            break;
          end
        catch e
          if strcmp(string(e.identifier), "experiment:service:hostLogLimit")
            rethrow(e);
          end
          host_stats.log_stream_error_identifier = char(string(e.identifier));
          host_stats.log_stream_error_message = char(string(e.message));
          if cfg.log_stream_require_success
            obj.raise_streaming_failure(e, host_stats);
          end
          warning("experiment:service:logUnavailable", ...
            "Streaming log read failed; falling back to non-streaming read (%s: %s).", ...
            string(e.identifier), string(e.message));
          done = obj.wait_until_done(symbols, max(0, cfg.done_timeout_s - toc(t0)));
          host_stats.log_stream_enabled = false;
          host_stats.log_stream_fallback_used = true;
          log_data = struct( ...
            "log_seq", zeros(0, 1), ...
            "log_i", zeros(0, 1), ...
            "log_x", zeros(0, 1), ...
            "log_t", zeros(0, 1), ...
            "log_cmd_idx", zeros(0, 1), ...
            "log_cmd_value", zeros(0, 1), ...
            "wr_idx", 0, ...
            "overflow", false);
          return;
        end
        pause(cfg.log_poll_period_s);
      end

      if ~done
        try
          wr_idx = double(obj.plc_transport.read_scalar(symbols.log.wr_idx, t.u32));
          plc_overflow = logical(obj.plc_transport.read_scalar(symbols.log.overflow, t.bool));
          [state, local_overflow] = obj.drain_log_ring_to_host(symbols, cfg, ring_n, state, wr_idx);
          state.overflow = state.overflow || plc_overflow || local_overflow;
        catch e_final_pending
          if strcmp(string(e_final_pending.identifier), "experiment:service:hostLogLimit")
            rethrow(e_final_pending);
          end
          if cfg.log_stream_require_success
            obj.raise_streaming_failure(e_final_pending, host_stats);
          end
          host_stats.log_stream_enabled = false;
          host_stats.log_stream_fallback_used = true;
          host_stats.log_stream_error_identifier = char(string(e_final_pending.identifier));
          host_stats.log_stream_error_message = char(string(e_final_pending.message));
          wr_idx = state.next_read_idx;
        end
      end

      host_stats.log_samples_captured = state.sample_count;
      host_stats.log_read_time_s_total = state.read_time_s;
      log_data = obj.finalize_log_stream_state(state);
      log_data.wr_idx = wr_idx;
      log_data.overflow = logical(state.overflow);
    end

    function ready = wait_for_reset_idle(obj, symbols, timeout_s)
      t = symbols.types;
      t0 = tic;
      ready = false;
      while toc(t0) < timeout_s
        try
          wr_idx = double(obj.plc_transport.read_scalar(symbols.log.wr_idx, t.u32));
          cmd_idx = double(obj.plc_transport.read_scalar(symbols.cmd_idx, t.u32));
          exp_start = logical(obj.plc_transport.read_scalar(symbols.start, t.bool));
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

    function ring_n = read_log_ring_capacity(obj, symbols, cfg)
      t = symbols.types;
      try
        ring_n = double(obj.plc_transport.read_scalar("GVL_VM_LOG.LOG_N", t.u32));
      catch
        ring_n = double(cfg.log_n);
      end
      if ~(isfinite(ring_n) && ring_n > 0)
        ring_n = double(cfg.log_n);
      end
    end

    function state = init_log_stream_state(~)
      state = struct( ...
        "next_read_idx", 0, ...
        "sample_count", 0, ...
        "chunks_seq", {cell(0, 1)}, ...
        "chunks_i", {cell(0, 1)}, ...
        "chunks_x", {cell(0, 1)}, ...
        "chunks_t", {cell(0, 1)}, ...
        "chunks_cmd_idx", {cell(0, 1)}, ...
        "chunks_cmd_value", {cell(0, 1)}, ...
        "overflow", false, ...
        "overflow_warned", false, ...
        "rd_idx_supported", true, ...
        "rd_idx_warned", false, ...
        "read_time_s", 0);
    end

    function [state, local_overflow] = drain_log_ring_to_host(obj, symbols, cfg, ring_n, state, wr_idx)
      t = symbols.types;
      local_overflow = false;
      pending = double(wr_idx) - double(state.next_read_idx);
      if pending <= 0
        return;
      end

      if pending > ring_n
        local_overflow = true;
        state.overflow = true;
        state.next_read_idx = double(wr_idx) - ring_n;
        pending = ring_n;
      end

      while pending > 0
        take_n = min(pending, floor(double(cfg.log_chunk_n)));
        [chunk, read_elapsed] = obj.read_ring_chunk(symbols, t, state.next_read_idx, take_n, ring_n);
        state.read_time_s = state.read_time_s + read_elapsed;
        state = obj.append_log_chunk(state, chunk, cfg);
        state.next_read_idx = state.next_read_idx + take_n;
        pending = double(wr_idx) - double(state.next_read_idx);
      end

      if state.rd_idx_supported
        try
          obj.plc_transport.write_scalar(symbols.log.rd_idx, uint32(state.next_read_idx), t.u32);
        catch e
          state.rd_idx_supported = false;
          if ~state.rd_idx_warned
            warning("experiment:service:rdIdxUnavailable", ...
              "GVL_VM_LOG.rd_idx write unavailable; continuing without PLC-side consumer index sync (%s: %s).", ...
              string(e.identifier), string(e.message));
            state.rd_idx_warned = true;
          end
        end
      end
    end

    function [chunk, read_elapsed] = read_ring_chunk(obj, symbols, t, abs_start_idx, take_n, ring_n)
      t_chunk = tic;
      start_ring = mod(double(abs_start_idx), double(ring_n));
      n1 = min(double(take_n), double(ring_n) - start_ring);
      n2 = double(take_n) - n1;

      chunk = struct();
      % PLC logger writes absolute sequence numbers (GVL_VM_LOG.seq) in lockstep with wr_idx.
      % Reconstructing from abs_start_idx avoids TwinCAT/MATLAB UDINT[] slice marshaling issues.
      chunk.log_seq = obj.make_expected_seq_chunk(abs_start_idx, take_n);
      chunk.log_i = obj.read_log_component_slice(symbols.log.log_i, t.double, start_ring, n1, n2);
      chunk.log_x = obj.read_log_component_slice(symbols.log.log_x, t.double, start_ring, n1, n2);
      try
        chunk.log_t = obj.read_log_component_slice(symbols.log.log_t, t.u64, start_ring, n1, n2);
      catch
        % log_t is optional for current validation/plot flow; keep capture alive if MATLAB cannot marshal UInt64[].
        chunk.log_t = zeros(double(take_n), 1);
      end
      try
        chunk.log_cmd_idx = obj.read_log_component_slice(symbols.log.log_cmd_idx, t.u32, start_ring, n1, n2);
      catch
        chunk.log_cmd_idx = zeros(0, 1);
      end
      try
        chunk.log_cmd_value = obj.read_log_component_slice(symbols.log.log_cmd_value, t.double, start_ring, n1, n2);
      catch
        chunk.log_cmd_value = zeros(0, 1);
      end
      read_elapsed = toc(t_chunk);
    end

    function values = read_log_component_slice(obj, symbol, net_type, start_ring, n1, n2)
      v1 = obj.plc_transport.read_array_slice(symbol, net_type, uint32(start_ring), uint32(n1));
      if n2 <= 0
        values = double(v1(:));
        return;
      end
      v2 = obj.plc_transport.read_array_slice(symbol, net_type, uint32(0), uint32(n2));
      values = [double(v1(:)); double(v2(:))];
    end

    function seq = make_expected_seq_chunk(~, abs_start_idx, take_n)
      % PLC stores seq := seq + 1 each sample and increments wr_idx once per sample.
      % Therefore the absolute write index k maps to sequence k+1 after reset.
      seq = double(abs_start_idx) + (1:double(take_n))';
      max_udint = 2^32;
      seq = mod(seq, max_udint);
    end

    function state = append_log_chunk(~, state, chunk, cfg)
      n_chunk = numel(chunk.log_seq);
      if ~isinf(cfg.log_host_max_n) && (double(state.sample_count) + double(n_chunk) > double(cfg.log_host_max_n))
        error("experiment:service:hostLogLimit", ...
          "Host log buffer exceeded log_host_max_n (%g samples).", double(cfg.log_host_max_n));
      end
      if n_chunk == 0
        return;
      end
      state.chunks_seq{end + 1, 1} = double(chunk.log_seq(:));
      state.chunks_i{end + 1, 1} = double(chunk.log_i(:));
      state.chunks_x{end + 1, 1} = double(chunk.log_x(:));
      state.chunks_t{end + 1, 1} = double(chunk.log_t(:));
      if isfield(chunk, "log_cmd_idx") && ~isempty(chunk.log_cmd_idx)
        state.chunks_cmd_idx{end + 1, 1} = double(chunk.log_cmd_idx(:));
      end
      if isfield(chunk, "log_cmd_value") && ~isempty(chunk.log_cmd_value)
        state.chunks_cmd_value{end + 1, 1} = double(chunk.log_cmd_value(:));
      end
      state.sample_count = state.sample_count + n_chunk;
    end

    function log_data = finalize_log_stream_state(~, state)
      log_data = struct( ...
        "log_seq", zeros(0, 1), ...
        "log_i", zeros(0, 1), ...
        "log_x", zeros(0, 1), ...
        "log_t", zeros(0, 1), ...
        "log_cmd_idx", zeros(0, 1), ...
        "log_cmd_value", zeros(0, 1), ...
        "wr_idx", 0, ...
        "overflow", false);
      if ~isempty(state.chunks_seq)
        log_data.log_seq = vertcat(state.chunks_seq{:});
        log_data.log_i = vertcat(state.chunks_i{:});
        log_data.log_x = vertcat(state.chunks_x{:});
        log_data.log_t = vertcat(state.chunks_t{:});
        if ~isempty(state.chunks_cmd_idx)
          log_data.log_cmd_idx = vertcat(state.chunks_cmd_idx{:});
        end
        if ~isempty(state.chunks_cmd_value)
          log_data.log_cmd_value = vertcat(state.chunks_cmd_value{:});
        end
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
        "log_cmd_idx", zeros(0, 1), ...
        "log_cmd_value", zeros(0, 1), ...
        "wr_idx", 0, ...
        "overflow", false);

      try
        wr_idx = obj.plc_transport.read_scalar(symbols.log.wr_idx, t.u32);
        overflow = obj.plc_transport.read_scalar(symbols.log.overflow, t.bool);
        valid_n = uint32(min(double(wr_idx), log_n));
        if valid_n > 0
          log_data.log_seq = double(obj.plc_transport.read_array(symbols.log.log_seq, t.u32, valid_n));
          log_data.log_i = double(obj.plc_transport.read_array(symbols.log.log_i, t.double, valid_n));
          log_data.log_x = double(obj.plc_transport.read_array(symbols.log.log_x, t.double, valid_n));
          try
            log_data.log_t = double(obj.plc_transport.read_array(symbols.log.log_t, t.u64, valid_n));
          catch
            % log_t is optional; keep logs if TwinCAT UInt64[] cannot be marshaled in MATLAB/.NET interop.
            log_data.log_t = zeros(double(valid_n), 1);
          end
          try
            log_data.log_cmd_idx = double(obj.plc_transport.read_array(symbols.log.log_cmd_idx, t.u32, valid_n));
          catch
            log_data.log_cmd_idx = zeros(0, 1);
          end
          try
            log_data.log_cmd_value = double(obj.plc_transport.read_array(symbols.log.log_cmd_value, t.double, valid_n));
          catch
            log_data.log_cmd_value = zeros(0, 1);
          end
        end
        log_data.wr_idx = double(wr_idx);
        log_data.overflow = logical(overflow);
      catch e
        warning("experiment:service:logUnavailable", ...
          "Logging symbols may be absent; keeping empty logs (%s: %s).", ...
          string(e.identifier), string(e.message));
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

    function enforce_log_requirements(~, metrics, raw, cmd, cfg, host)
      if ~cfg.log_require_complete
        return;
      end

      if cfg.log_stream_enable && cfg.wait_for_done && cfg.log_stream_require_success && ...
          logical(host.log_stream_fallback_used)
        error("experiment:service:incompleteLog", ...
          "Streaming log capture fell back to non-streaming path (id=%s).", ...
          char(string(host.log_stream_error_identifier)));
      end

      n_seq = numel(raw.log_seq);
      n_i = numel(raw.log_i);
      n_x = numel(raw.log_x);
      if n_seq == 0
        error("experiment:service:incompleteLog", ...
          "No log samples captured (log_seq/log_i/log_x are empty).");
      end
      if raw.log_overflow
        error("experiment:service:incompleteLog", ...
          "PLC/host log overflow detected (raw.log_overflow=true).");
      end
      if ~(n_seq == n_i && n_i == n_x)
        error("experiment:service:incompleteLog", ...
          "Log component sample counts mismatch (seq=%d, logI=%d, logX=%d).", n_seq, n_i, n_x);
      end
      if n_seq > 1 && ~all(udint_seq_step_is_one(raw.log_seq(:)))
        missing_n = sum(~udint_seq_step_is_one(raw.log_seq(:)));
        error("experiment:service:incompleteLog", ...
          "Sequence gap detected in log_seq (%d discontinuities).", missing_n);
      end
      if cmd.use_profile && cfg.wait_for_done && (n_i ~= numel(cmd.current_profile))
        error("experiment:service:incompleteLog", ...
          "Profile/log sample count mismatch (cmd=%d, logI=%d, logX=%d).", ...
          numel(cmd.current_profile), n_i, n_x);
      end

      if isfield(metrics, "sampling") && isfield(metrics.sampling, "all_sample_counts_match") && ...
          ~logical(metrics.sampling.all_sample_counts_match)
        error("experiment:service:incompleteLog", ...
          "Sampling count check failed (cmd=%d, logI=%d, logX=%d).", ...
          numel(cmd.current_profile), n_i, n_x);
      end
      if isfield(metrics, "acceptance") && isfield(metrics.acceptance, "seq_no_gap") && ...
          ~logical(metrics.acceptance.seq_no_gap)
        error("experiment:service:incompleteLog", ...
          "Sampling sequence check failed (metrics.acceptance.seq_no_gap=false).");
      end
      if cmd.use_profile && cfg.wait_for_done && ...
          isprop(cfg, "log_require_waveform_exact") && ~logical(cfg.log_require_waveform_exact)
        return;
      end

      if cmd.use_profile && cfg.wait_for_done && ...
          isfield(metrics, "acceptance") && isfield(metrics.acceptance, "input_waveform_exact_match") && ...
          ~logical(metrics.acceptance.input_waveform_exact_match)
        mismatch_class = "";
        best_shift = NaN;
        zero_shift_max_abs_err = NaN;
        best_shift_max_abs_err = NaN;
        if isfield(metrics, "input_waveform")
          iw = metrics.input_waveform;
          if isfield(iw, "mismatch_class")
            mismatch_class = string(iw.mismatch_class);
          end
          if isfield(iw, "best_shift_samples")
            best_shift = double(iw.best_shift_samples);
          end
          if isfield(iw, "zero_shift_max_abs_err")
            zero_shift_max_abs_err = double(iw.zero_shift_max_abs_err);
          end
          if isfield(iw, "best_shift_max_abs_err")
            best_shift_max_abs_err = double(iw.best_shift_max_abs_err);
          end
        end
        error("experiment:service:incompleteLog", ...
          "Input waveform exact match failed (class=%s, best_shift=%g, zero_shift_max_abs_err=%.6g, best_shift_max_abs_err=%.6g).", ...
          char(mismatch_class), best_shift, zero_shift_max_abs_err, best_shift_max_abs_err);
      end
    end

    function raise_streaming_failure(~, e, host_stats)
      error("experiment:service:logStreamFailed", ...
        "Streaming log read failed (%s: %s). fallback=%d, cycles=%d, captured=%d", ...
        char(string(e.identifier)), char(string(e.message)), ...
        logical(host_stats.log_stream_fallback_used), ...
        double(host_stats.log_stream_cycles), ...
        double(host_stats.log_samples_captured));
    end
  end
end

function tf = udint_seq_step_is_one(seq)
seq = double(seq(:));
if numel(seq) <= 1
  tf = true(0, 1);
  return;
end
max_udint = 2^32;
step = mod(seq(2:end) - seq(1:end-1), max_udint);
tf = (step == 1);
end
