classdef VirtualMotorService < ehm.interfaces.IVirtualMotorGateway
  properties (Access = private)
    plcTransport
    vmTransport
    symbolCatalog
  end

  methods
    function obj = VirtualMotorService(plcTransport, vmTransport, symbolCatalog)
      if ~isa(plcTransport, "ehm.interfaces.IAdsTransport")
        error("ehm:service:invalidDependency", "plcTransport must implement IAdsTransport.");
      end
      if ~isa(vmTransport, "ehm.interfaces.IAdsTransport")
        error("ehm:service:invalidDependency", "vmTransport must implement IAdsTransport.");
      end
      if ~isa(symbolCatalog, "ehm.interfaces.ISymbolCatalog")
        error("ehm:service:invalidDependency", "symbolCatalog must implement ISymbolCatalog.");
      end
      obj.plcTransport = plcTransport;
      obj.vmTransport = vmTransport;
      obj.symbolCatalog = symbolCatalog;
    end

    function out = run(obj, cfg)
      if ~isa(cfg, "ehm.config.RunConfig")
        cfg = ehm.config.RunConfig.fromStruct(cfg);
      end
      obj.ensureFolder(fileparts(cfg.save_path));

      plcSymbols = obj.symbolCatalog.resolveVirtualMotorSymbols("");
      vmSymbols = obj.symbolCatalog.resolveVirtualMotorSymbols(cfg.vm_param_symbol_prefix);
      obj.symbolCatalog.validateRequiredSymbols(obj.plcTransport, plcSymbols);
      obj.symbolCatalog.validateRequiredSymbols(obj.vmTransport, vmSymbols);
      t = plcSymbols.types;

      vmParams = struct();
      vmParams.M = cfg.M;
      vmParams.D = cfg.D;
      vmParams.Kt = cfg.Kt;
      vmParams.tau_limit = cfg.tau_limit;
      vmParams.vel_limit = cfg.vel_limit;
      vmParams.task_dt_ns = cfg.task_dt_ns;
      obj.writeVmParams(vmSymbols, vmParams);

      profile = cfg.current_profile(:);
      useProfile = ~isempty(profile);
      tRun = tic;
      if useProfile
        profileN = numel(profile);
        if profileN > double(cfg.cmd_max_n)
          error("ehm:service:invalidProfile", ...
            "current_profile length (%d) exceeds cmd_max_n (%d).", profileN, cfg.cmd_max_n);
        end

        obj.plcTransport.writeScalar(plcSymbols.start, false, t.bool);
        obj.plcTransport.writeScalar(plcSymbols.cmdIdx, uint32(0), t.u32);
        obj.plcTransport.writeScalar(plcSymbols.cmdLen, uint32(0), t.u32);
        obj.pulseReset(plcSymbols, 0.02);

        idleReady = obj.waitForResetIdle(plcSymbols, cfg.reset_timeout_s);
        if ~idleReady
          warning("ehm:service:resetSyncTimeout", ...
            "Timed out waiting reset idle state (wr_idx==0, cmd_idx==0, start flag == FALSE).");
        end

        obj.plcTransport.writeArray(plcSymbols.cmdProfile, profile, t.double);
        obj.plcTransport.writeScalar(plcSymbols.cmdLen, uint32(profileN), t.u32);
        obj.plcTransport.writeScalar(plcSymbols.start, true, t.bool);

        if cfg.wait_for_done
          done = obj.waitUntilDone(plcSymbols, cfg.done_timeout_s);
          if ~done
            warning("ehm:service:timeout", "Timed out waiting for experiment completion.");
          end
        else
          while toc(tRun) < cfg.hold_seconds
            pause(min(0.05, cfg.hold_seconds / 10 + eps));
          end
        end
      else
        obj.plcTransport.writeScalar(plcSymbols.currentIn, cfg.current_in, t.double);
        while toc(tRun) < cfg.hold_seconds
          pause(min(0.05, cfg.hold_seconds / 10 + eps));
        end
        if cfg.release_to_zero
          obj.plcTransport.writeScalar(plcSymbols.currentIn, 0.0, t.double);
        end
      end
      elapsedS = toc(tRun);

      positionLast = obj.plcTransport.readScalar(plcSymbols.positionOut, t.double);
      currentLast = obj.plcTransport.readScalar(plcSymbols.currentIn, t.double);
      velocityLast = obj.plcTransport.readScalar(plcSymbols.velocityOut, t.double);

      raw = struct();
      raw.position_last = double(positionLast);
      raw.current_last = double(currentLast);
      raw.velocity_last = double(velocityLast);

      [logData, logReadTime] = obj.readUpperLogs(plcSymbols, cfg.log_n);
      raw.log_seq = logData.log_seq;
      raw.log_i = logData.log_i;
      raw.log_x = logData.log_x;
      raw.log_t = logData.log_t;
      raw.log_wr_idx = logData.wr_idx;
      raw.log_overflow = logData.overflow;

      cmd = struct();
      cmd.current_in = cfg.current_in;
      cmd.current_profile = profile;
      cmd.use_profile = useProfile;
      cmd.hold_seconds = cfg.hold_seconds;
      cmd.release_to_zero = cfg.release_to_zero;

      host = struct();
      host.elapsed_s = elapsedS;
      host.log_read_time_s = logReadTime;

      cfgStruct = cfg.toStruct();
      metrics = preload_eval(raw, cmd, cfgStruct);
      config = cfgStruct;
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
    function writeVmParams(obj, symbols, params)
      t = symbols.types;
      obj.vmTransport.writeScalar(symbols.vmParams.M, params.M, t.double);
      obj.vmTransport.writeScalar(symbols.vmParams.D, params.D, t.double);
      obj.vmTransport.writeScalar(symbols.vmParams.Kt, params.Kt, t.double);
      obj.vmTransport.writeScalar(symbols.vmParams.tau_limit, params.tau_limit, t.double);
      obj.vmTransport.writeScalar(symbols.vmParams.vel_limit, params.vel_limit, t.double);
      obj.vmTransport.writeScalar(symbols.vmParams.task_dt_ns, uint64(params.task_dt_ns), t.u64);
    end

    function pulseReset(obj, symbols, pulseSeconds)
      t = symbols.types;
      obj.plcTransport.writeScalar(symbols.reset, true, t.bool);
      pause(pulseSeconds);
      obj.plcTransport.writeScalar(symbols.reset, false, t.bool);
    end

    function done = waitUntilDone(obj, symbols, timeoutS)
      t = symbols.types;
      t0 = tic;
      done = false;
      while toc(t0) < timeoutS
        try
          expStart = logical(obj.plcTransport.readScalar(symbols.start, t.bool));
          done = ~expStart;
        catch
          done = false;
        end
        if done
          return;
        end
        pause(0.01);
      end
    end

    function ready = waitForResetIdle(obj, symbols, timeoutS)
      t = symbols.types;
      t0 = tic;
      ready = false;
      while toc(t0) < timeoutS
        try
          wrIdx = double(obj.plcTransport.readScalar(symbols.log.wrIdx, t.u32));
          cmdIdx = double(obj.plcTransport.readScalar(symbols.cmdIdx, t.u32));
          expStart = logical(obj.plcTransport.readScalar(symbols.start, t.bool));
          ready = (wrIdx == 0) && (cmdIdx == 0) && (~expStart);
        catch
          ready = false;
        end
        if ready
          return;
        end
        pause(0.01);
      end
    end

    function [logData, readTime] = readUpperLogs(obj, symbols, logN)
      t = symbols.types;
      tRead = tic;
      logData = struct("log_seq", zeros(0, 1), "log_i", zeros(0, 1), ...
        "log_x", zeros(0, 1), "log_t", zeros(0, 1), "wr_idx", 0, "overflow", false);

      try
        wrIdx = obj.plcTransport.readScalar(symbols.log.wrIdx, t.u32);
        overflow = obj.plcTransport.readScalar(symbols.log.overflow, t.bool);
        validN = uint32(min(double(wrIdx), logN));
        if validN > 0
          logData.log_seq = double(obj.plcTransport.readArray(symbols.log.logSeq, t.u32, validN));
          logData.log_i = double(obj.plcTransport.readArray(symbols.log.logI, t.double, validN));
          logData.log_x = double(obj.plcTransport.readArray(symbols.log.logX, t.double, validN));
          logData.log_t = double(obj.plcTransport.readArray(symbols.log.logT, t.u64, validN));
        end
        logData.wr_idx = double(wrIdx);
        logData.overflow = logical(overflow);
      catch
        warning("ehm:service:logUnavailable", ...
          "Logging symbols may be absent; keeping empty logs.");
      end
      readTime = toc(tRead);
    end

    function ensureFolder(~, pathValue)
      if strlength(string(pathValue)) == 0
        return;
      end
      if ~exist(pathValue, "dir")
        mkdir(pathValue);
      end
    end
  end
end
