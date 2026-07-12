classdef ExperimentRunner
  methods (Static)
    function out = run(conn, cfg, varargin)
      startup_total_t0 = tic;
      cfg = experiment.ExperimentConfig.from_varargin(cfg);
      experiment.ExperimentRunner.validate_connection(conn);
      experiment.ExperimentRunner.validate_connection_snapshot(conn, cfg.env);
      opts = experiment.ExperimentRunner.parse_run_options(varargin{:});
      if ~isempty(opts.abort_condition)
        opts.cfg_snapshot = cfg.to_struct();
      end

      if cfg.host_heartbeat_enable && cfg.external_host_heartbeat_enable
        error("experiment:runner:invalidConfig", ...
          "Internal and external host heartbeat writers cannot be enabled together.");
      end

      seq_transport = conn.seq;
      ctrl_transport = conn.ctrl;
      module_transport = [];
      if isfield(conn, "module")
        module_transport = conn.module;
      end

      plc_symbols = experiment.RuntimeSymbols.from_defaults();
      env = cfg.env;
      controller_symbols = experiment.RuntimeSymbols.from_controller_prefix(env.controller_prefix);
      startup_timing = struct( ...
        "contract_s", 0.0, ...
        "reset_idle_s", 0.0, ...
        "parameter_write_s", 0.0, ...
        "table_write_s", 0.0, ...
        "heartbeat_start_s", 0.0, ...
        "servo_ready_s", 0.0, ...
        "total_s", 0.0);

      if (cfg.write_controller_params || cfg.write_virtual_motor_params) && isempty(module_transport)
        error("experiment:runner:invalidConfig", ...
          "module transport is required when controller or virtual-motor parameter writes are enabled.");
      end

      phase_t0 = tic;
      if cfg.validate_symbols
        experiment.ExperimentRunner.validate_runtime_symbols(seq_transport, ctrl_transport, plc_symbols);
        if cfg.write_controller_params
          twincat_ads.SymbolBrowser.validate_symbols(module_transport, controller_symbols.controllerRequiredProbes);
        end
      end

      ctrl = experiment.ModeManagerControl.resolve_symbols( ...
        ctrl_transport, plc_symbols, "experiment:runner:invalidConfig");
      startup_timing.contract_s = toc(phase_t0);
      clear_mode_guard = onCleanup( ...
        @() experiment.ExperimentRunner.safe_clear_mode_flags(ctrl_transport, ctrl));
      heartbeat_state = experiment.ModeManagerControl.heartbeat_disabled();
      external_heartbeat_cleanup = [];

      table_n = numel(cfg.ref_profile);
      logger_path = string(env.logger_host_file_path);
      t_run = tic;
      phase_t0 = tic;
      experiment.ModeManagerControl.write_mode_flags(ctrl_transport, ctrl, uint32(0));
      seq_transport.write_scalar(plc_symbols.tableLen, uint32(0), plc_symbols.types.u32);

      [reset_acked, reset_diag, ~] = experiment.ModeManagerControl.request_reset_and_wait_ack( ...
        ctrl_transport, ctrl, cfg.reset_timeout_s, heartbeat_state);
      if ~reset_acked
        error("experiment:runner:resetAckTimeout", ...
          "Timed out waiting reset acknowledgement (resetAckCounter before=%g after=%g).", ...
          reset_diag.counter_before, reset_diag.counter_after);
      end

      [idle_ready, idle_diag, ~] = experiment.ModeManagerControl.wait_for_reset_idle( ...
        seq_transport, ctrl_transport, plc_symbols, ctrl, cfg.reset_timeout_s, heartbeat_state);
      if ~idle_ready
        error("experiment:runner:resetSyncTimeout", ...
          "Timed out waiting reset idle state (idx==0, experimentActive==FALSE). Observed idx=%g experimentActive=%d.", ...
          idle_diag.idx, logical(idle_diag.experiment_active));
      end
      startup_timing.reset_idle_s = toc(phase_t0);
      logger_before = experiment.ModeManagerControl.read_logger_status(ctrl_transport, ctrl);
      logger_module_before = experiment.ExperimentRunner.read_logger_module_status(module_transport);

      phase_t0 = tic;
      if cfg.write_controller_params
        experiment.write_controller_params( ...
          module_transport, env.controller_prefix, ...
          cfg.controller.to_flat_struct());
      end

      if cfg.write_virtual_motor_params
        virtualMotor.writeParams(conn, cfg.virtual_motor_plant, ...
          "taskDtNs", env.task_dt_ns(), ...
          "validateSymbols", cfg.validate_symbols);
      end
      startup_timing.parameter_write_s = toc(phase_t0);

      phase_t0 = tic;
      experiment.write_ref_table(seq_transport, cfg.ref_profile(:), double(env.table_max_n));
      experiment.write_ff_table(seq_transport, cfg.ff_profile(:), table_n);
      experiment.write_dist_table(seq_transport, cfg.dist_profile(:), table_n);
      seq_transport.write_scalar(plc_symbols.repeatCount, uint32(cfg.repeat_count), plc_symbols.types.u32);
      seq_transport.write_scalar(plc_symbols.tableLen, uint32(table_n), plc_symbols.types.u32);
      startup_timing.table_write_s = toc(phase_t0);

      phase_t0 = tic;
      if cfg.external_host_heartbeat_enable
        [external_heartbeat_cleanup, heartbeat_monitor] = experiment.start_external_heartbeat( ...
          env, cfg.external_host_heartbeat_period_s, cfg.ads_assembly);
        heartbeat_state = experiment.ModeManagerControl.monitor_external_heartbeat(heartbeat_monitor);
      else
        heartbeat_state = experiment.ModeManagerControl.init_heartbeat( ...
          ctrl_transport, ctrl, cfg.host_heartbeat_enable, cfg.host_heartbeat_period_s);
      end
      startup_timing.heartbeat_start_s = toc(phase_t0);

      phase_t0 = tic;
      experiment.ModeManagerControl.write_mode_flags(ctrl_transport, ctrl, uint32(ctrl.MODEF_SERVO_ENABLE));
      heartbeat_state = experiment.ExperimentRunner.wait_for_ready_state( ...
        ctrl_transport, ctrl, cfg.reset_timeout_s, heartbeat_state);
      startup_timing.servo_ready_s = toc(phase_t0);
      experiment.ModeManagerControl.write_mode_flags(ctrl_transport, ctrl, ...
        uint32(bitor(ctrl.MODEF_SERVO_ENABLE, ctrl.MODEF_EXPERIMENT_START_REQ)));
      startup_timing.total_s = toc(startup_total_t0);

      if cfg.wait_for_done
        [done, timed_out, stop_reason, abort_requested, abort_diag, heartbeat_state] = ...
          experiment.ExperimentRunner.wait_for_terminal_state( ...
            ctrl_transport, seq_transport, plc_symbols, ctrl, cfg, heartbeat_state, opts);
      else
        done = false;
        timed_out = false;
        stop_reason = "hold_complete";
        abort_requested = false;
        abort_diag = experiment.ExperimentRunner.empty_abort_diag();
        while toc(t_run) < cfg.hold_seconds
          if ~isempty(opts.abort_condition)
            [abort_requested, abort_diag] = experiment.ExperimentRunner.check_abort_condition( ...
              opts.abort_condition, struct( ...
                "elapsed_s", toc(t_run), ...
                "cfg", opts.cfg_snapshot, ...
                "heartbeat_state", heartbeat_state));
          end
          if abort_requested
            [aborted, abort_diag, heartbeat_state] = experiment.ModeManagerControl.abort_experiment( ...
              ctrl_transport, ctrl, heartbeat_state, struct( ...
                "timeout_s", cfg.logger_release_timeout_s, ...
                "poll_period_s", cfg.abort_check_period_s, ...
                "tick_heartbeat", true));
            if ~aborted
              error("experiment:runner:abortTimeout", ...
                "Timed out waiting abort completion (%s).", string(abort_diag.detail));
            end
            stop_reason = "abort";
            break;
          end
          heartbeat_state = experiment.ModeManagerControl.tick_heartbeat( ...
            ctrl_transport, ctrl, heartbeat_state, false);
          pause(min(cfg.abort_check_period_s, cfg.hold_seconds / 10 + eps));
        end
      end

      experiment.ModeManagerControl.write_mode_flags(ctrl_transport, ctrl, uint32(0));
      [file_released, logger_diag, ~] = experiment.ModeManagerControl.wait_for_logger_release( ...
        ctrl_transport, ctrl, cfg.logger_release_timeout_s, heartbeat_state);
      elapsed_s = toc(t_run);
      logger_after = experiment.ModeManagerControl.read_logger_status(ctrl_transport, ctrl);

      if logger_diag.error_code ~= 0
        error("experiment:runner:loggerError", ...
          "Logger reported error after experiment stop (0x%08X).", uint32(logger_diag.error_code));
      end
      if ~file_released
        error("experiment:runner:loggerReleaseTimeout", ...
          "Logger file was not released after experiment stop (%s).", string(logger_diag.detail));
      end
      logger_module_after = experiment.ExperimentRunner.read_logger_module_status(module_transport);

      [raw, logger_bin] = experiment.ExperimentRunner.read_log_payload(cfg.read_logs, logger_path);
      cmd = struct( ...
        "ref_profile", cfg.ref_profile(:), ...
        "ff_profile", cfg.ff_profile(:), ...
        "dist_profile", cfg.dist_profile(:), ...
        "table_len", table_n, ...
        "repeat_count", double(cfg.repeat_count), ...
        "task_rate_hz", env.task_rate_hz);
      host = struct( ...
        "elapsed_s", elapsed_s, ...
        "wait_for_done", logical(cfg.wait_for_done), ...
        "done", logical(done), ...
        "timed_out", logical(timed_out), ...
        "abort_requested", logical(abort_requested), ...
        "stop_reason", char(string(stop_reason)), ...
        "abort_diag", abort_diag, ...
        "startup_timing", startup_timing, ...
        "control_ams_port", double(env.control_port), ...
        "host_heartbeat_enable", logical(cfg.host_heartbeat_enable), ...
        "host_heartbeat_period_s", double(cfg.host_heartbeat_period_s), ...
        "external_host_heartbeat_enable", logical(cfg.external_host_heartbeat_enable), ...
        "external_host_heartbeat_period_s", double(cfg.external_host_heartbeat_period_s), ...
        "abort_check_period_s", double(cfg.abort_check_period_s), ...
        "logger_release_timeout_s", double(cfg.logger_release_timeout_s), ...
        "control_mode_flags_symbol", char(string(ctrl.modeFlagsSymbol)), ...
        "control_mode_state_symbol", char(string(ctrl.modeStateSymbol)));
      logger_status_available = logical(logger_module_before.status_available && logger_module_after.status_available);
      logger = struct( ...
        "status_available", logger_status_available, ...
        "ready_before", logical(logger_module_before.ready), ...
        "ready_after", logical(logger_module_after.ready), ...
        "error_before", uint32(logger_before.error_code), ...
        "error_after", uint32(logger_after.error_code), ...
        "records_before", uint32(logger_module_before.records), ...
        "records_after", uint32(logger_module_after.records), ...
        "file_released", logical(logger_after.file_released), ...
        "file_probe_detail", string(logger_diag.detail), ...
        "file_path", char(logger_path));

      metrics = experiment.preload_eval(raw, cmd, cfg);
      config_out = cfg.to_struct();

      if strlength(string(cfg.save_path)) > 0
        experiment.ExperimentRunner.ensure_folder(fileparts(cfg.save_path));
        save_payload = struct( ...
          "raw", raw, ...
          "cmd", cmd, ...
          "host", host, ...
          "metrics", metrics, ...
          "config", config_out);
        save(cfg.save_path, "-struct", "save_payload");
      end

      out = struct( ...
        "raw", raw, ...
        "logger_bin", logger_bin, ...
        "cmd", cmd, ...
        "host", host, ...
        "metrics", metrics, ...
        "config", config_out, ...
        "logger", logger, ...
        "save_path", char(string(cfg.save_path)));

      if ~isempty(external_heartbeat_cleanup)
        clear external_heartbeat_cleanup
      end
    end
  end

  methods (Static, Access = private)
    function opts = parse_run_options(varargin)
      p = inputParser;
      p.addParameter("abort_condition", [], @(x) isempty(x) || isa(x, "function_handle"));
      p.parse(varargin{:});
      opts = p.Results;
      opts.cfg_snapshot = [];
    end

    function validate_connection(conn)
      required = {"seq", "ctrl"};
      for k = 1:numel(required)
        key = required{k};
        if ~isfield(conn, key) || ~isa(conn.(key), "twincat_ads.IAdsTransport")
          error("experiment:runner:invalidConfig", "Connection is missing '%s' transport.", key);
        end
      end
      if isfield(conn, "module") && ~isempty(conn.module) && ~isa(conn.module, "twincat_ads.IAdsTransport")
        error("experiment:runner:invalidConfig", "Connection 'module' must implement twincat_ads.IAdsTransport.");
      end
    end

    function validate_runtime_symbols(seq_transport, ctrl_transport, plc_symbols)
      twincat_ads.SymbolBrowser.validate_symbols(seq_transport, plc_symbols.plcRequiredProbes);
      twincat_ads.SymbolBrowser.validate_symbols(ctrl_transport, plc_symbols.modeRequiredProbes);
    end

    function safe_clear_mode_flags(control_transport, ctrl)
      try
        experiment.ModeManagerControl.write_mode_flags(control_transport, ctrl, uint32(0));
      catch
      end
    end

    function validate_connection_snapshot(conn, expected_env)
      if ~isfield(conn, "env") || isempty(conn.env)
        return;
      end

      actual = config.EnvironmentConfig.from_struct(conn.env);
      expected = config.EnvironmentConfig.from_struct(expected_env);
      fields = [ ...
        "ams_net_id"
        "seq_port"
        "control_port"
        "module_port"
        "controller_prefix"
        "logger_target_file_path"
        "logger_host_file_path"
      ];
      mismatches = strings(0, 1);
      for k = 1:numel(fields)
        name = char(fields(k));
        if ~isequal(string(actual.(name)), string(expected.(name)))
          mismatches(end + 1, 1) = fields(k); %#ok<AGROW>
        end
      end
      if ~isempty(mismatches)
        error("experiment:runner:connectionConfigMismatch", ...
          "Connection environment differs from cfg.env: %s.", strjoin(mismatches, ", "));
      end
    end

    function status = read_logger_module_status(module_transport)
      status = struct("status_available", false, "ready", false, "records", uint32(0));
      if isempty(module_transport) || ~isa(module_transport, "twincat_ads.IAdsTransport")
        return;
      end

      t = twincat_ads.AdsTransport.net_types();
      try
        status.ready = logical(module_transport.read_scalar( ...
          "ExperimentLogger_Obj1 (Module1).Outputs.status.loggerReady", t.bool));
        status.records = uint32(module_transport.read_scalar( ...
          "ExperimentLogger_Obj1 (Module1).Outputs.status.recordsWritten", t.u32));
        status.status_available = true;
      catch
        status = struct("status_available", false, "ready", false, "records", uint32(0));
      end
    end

    function [raw, logger_bin] = read_log_payload(read_logs, logger_path)
      raw = struct( ...
        "seq", zeros(0, 1), ...
        "ref_value", zeros(0, 1), ...
        "ff_value", zeros(0, 1), ...
        "dist_value", zeros(0, 1), ...
        "control_input", zeros(0, 1), ...
        "target_current", zeros(0, 1), ...
        "position_act", zeros(0, 1));
      logger_bin = [];
      if ~logical(read_logs)
        return;
      end
      if ~isfile(logger_path)
        error("experiment:runner:loggerFileMissing", ...
          "Logger file was released but not found at %s.", string(logger_path));
      end
      logger_bin = experiment.read_logger_bin(logger_path);
      raw.seq = double(logger_bin.raw.seq(:));
      raw.ref_value = double(logger_bin.raw.ref_value(:));
      raw.ff_value = double(logger_bin.raw.ff_value(:));
      raw.dist_value = double(logger_bin.raw.dist_value(:));
      raw.control_input = double(logger_bin.raw.control_input(:));
      raw.target_current = double(logger_bin.raw.current_cmd(:));
      raw.position_act = double(logger_bin.raw.load_position(:));
    end

    function ensure_folder(path_value)
      if strlength(string(path_value)) == 0
        return;
      end
      if ~exist(path_value, "dir")
        mkdir(path_value);
      end
    end

    function heartbeat_state = wait_for_ready_state(ctrl_transport, ctrl, timeout_s, heartbeat_state)
      if nargin < 4 || isempty(heartbeat_state)
        heartbeat_state = experiment.ModeManagerControl.heartbeat_disabled();
      end
      t = twincat_ads.AdsTransport.net_types();
      t0 = tic;
      while toc(t0) < timeout_s
        heartbeat_state = experiment.ModeManagerControl.tick_heartbeat( ...
          ctrl_transport, ctrl, heartbeat_state, false);
        state = int16(ctrl_transport.read_scalar(ctrl.modeStateSymbol, t.i16));
        if state == ctrl.MODESTATE_SERVO_READY
          return;
        end
        pause(0.01);
      end

      diag = experiment.ExperimentRunner.try_read_symbol( ...
        @() int16(ctrl_transport.read_scalar(ctrl.modeStateSymbol, t.i16)), int16(-1));
      experiment.ExperimentRunner.safe_clear_mode_flags(ctrl_transport, ctrl);
      error("experiment:runner:readyTimeout", ...
        "Timed out waiting %.3f s for SERVO_READY after servo enable. modeState=%d", ...
        timeout_s, int16(diag));
    end

    function [done, timed_out, stop_reason, abort_requested, abort_diag, heartbeat_state] = wait_for_terminal_state( ...
        ctrl_transport, seq_transport, plc_symbols, ctrl, cfg, heartbeat_state, opts)
      t0 = tic;
      done = false;
      timed_out = false;
      abort_requested = false;
      abort_diag = experiment.ExperimentRunner.empty_abort_diag();
      observer_state = struct( ...
        "seen_active", false);
      while toc(t0) < cfg.done_timeout_s
        remaining_s = max(cfg.done_timeout_s - toc(t0), eps);
        [status, heartbeat_state, observer_state] = experiment.ModeManagerControl.wait_until_inactive( ...
          ctrl_transport, ctrl, min(cfg.abort_check_period_s, remaining_s), ...
          heartbeat_state, observer_state);
        if status.completed
          done = strcmp(status.stop_reason, "done");
          stop_reason = char(string(status.stop_reason));
          return;
        end

        if ~isempty(opts.abort_condition)
          [abort_requested, abort_diag] = experiment.ExperimentRunner.check_abort_condition( ...
            opts.abort_condition, struct( ...
              "elapsed_s", toc(t0), ...
              "status", status, ...
              "cfg", opts.cfg_snapshot, ...
              "heartbeat_state", heartbeat_state));
        end
        if abort_requested
          [aborted, abort_diag, heartbeat_state] = experiment.ModeManagerControl.abort_experiment( ...
            ctrl_transport, ctrl, heartbeat_state, struct( ...
              "timeout_s", cfg.logger_release_timeout_s, ...
              "poll_period_s", cfg.abort_check_period_s, ...
              "tick_heartbeat", true));
          if ~aborted
            error("experiment:runner:abortTimeout", ...
              "Timed out waiting abort completion (%s).", string(abort_diag.detail));
          end
          stop_reason = "abort";
          return;
        end
      end

      experiment.ExperimentRunner.safe_clear_mode_flags(ctrl_transport, ctrl);
      diag = experiment.ExperimentRunner.read_timeout_diag( ...
        ctrl_transport, seq_transport, plc_symbols, ctrl);
      error("experiment:runner:doneTimeout", [ ...
        'Timed out waiting %.3f s for experiment completion or abort. ' ...
        'modeState=%s experimentActive=%s idx=%s trialIndex=%s playbackDone=%s ' ...
        'loggerFileReleased=%s loggerError=0x%08X watchdogTripCounter=%s'], ...
        cfg.done_timeout_s, ...
        experiment.ExperimentRunner.diag_value_to_char(diag.mode_state), ...
        experiment.ExperimentRunner.diag_value_to_char(diag.experiment_active), ...
        experiment.ExperimentRunner.diag_value_to_char(diag.idx), ...
        experiment.ExperimentRunner.diag_value_to_char(diag.trial_index), ...
        experiment.ExperimentRunner.diag_value_to_char(diag.playback_done), ...
        experiment.ExperimentRunner.diag_value_to_char(diag.logger_file_released), ...
        uint32(diag.logger_error_code), ...
        experiment.ExperimentRunner.diag_value_to_char(diag.watchdog_trip_counter));
    end

    function [abort_requested, abort_diag] = check_abort_condition(abort_condition, context)
      abort_requested = false;
      abort_diag = experiment.ExperimentRunner.empty_abort_diag();
      if isempty(abort_condition)
        return;
      end
      abort_requested = logical(abort_condition(context));
      abort_diag.requested_by_callback = logical(abort_requested);
      abort_diag.callback_elapsed_s = double(context.elapsed_s);
    end

    function diag = empty_abort_diag()
      diag = struct( ...
        "requested_by_callback", false, ...
        "callback_elapsed_s", NaN, ...
        "requested_at_s", NaN, ...
        "modeflags_written", false, ...
        "stop_confirmed", false, ...
        "file_released", false, ...
        "error_code", uint32(0), ...
        "detail", "");
    end

    function diag = read_timeout_diag(ctrl_transport, seq_transport, plc_symbols, ctrl)
      t = plc_symbols.types;
      diag = struct( ...
        "mode_state", missing, ...
        "experiment_active", missing, ...
        "idx", missing, ...
        "trial_index", missing, ...
        "playback_done", missing, ...
        "logger_file_released", missing, ...
        "logger_error_code", uint32(0), ...
        "watchdog_trip_counter", missing);

      diag.mode_state = experiment.ExperimentRunner.try_read_symbol( ...
        @() double(ctrl_transport.read_scalar(ctrl.modeStateSymbol, t.i16)));
      diag.experiment_active = experiment.ExperimentRunner.try_read_symbol( ...
        @() logical(ctrl_transport.read_scalar(ctrl.experimentActiveSymbol, t.bool)));
      diag.logger_file_released = experiment.ExperimentRunner.try_read_symbol( ...
        @() logical(ctrl_transport.read_scalar(ctrl.loggerFileReleasedSymbol, t.bool)));
      diag.logger_error_code = experiment.ExperimentRunner.try_read_symbol( ...
        @() uint32(ctrl_transport.read_scalar(ctrl.loggerErrorCodeSymbol, t.u32)), uint32(0));
      diag.idx = experiment.ExperimentRunner.try_read_symbol( ...
        @() double(seq_transport.read_scalar(plc_symbols.idx, t.u32)));
      diag.trial_index = experiment.ExperimentRunner.try_read_symbol( ...
        @() double(seq_transport.read_scalar(plc_symbols.trialIndex, t.u32)));
      diag.playback_done = experiment.ExperimentRunner.try_read_symbol( ...
        @() logical(seq_transport.read_scalar("GVL_SEQ.playbackDone", t.bool)));
      diag.watchdog_trip_counter = experiment.ExperimentRunner.try_read_symbol( ...
        @() double(ctrl_transport.read_scalar("GVL_MODE.watchdogTripCounter", t.u32)));
    end

    function value = try_read_symbol(reader, default_value)
      if nargin < 2
        default_value = missing;
      end
      try
        value = reader();
      catch
        value = default_value;
      end
    end

    function out = diag_value_to_char(value)
      if ismissing(value)
        out = "<missing>";
        return;
      end
      out = char(string(value));
    end
  end
end
