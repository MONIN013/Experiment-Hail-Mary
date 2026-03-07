classdef ModeManagerControl
  methods (Static)
    function ctrl = resolve_symbols(control_transport, plc_symbols, error_id)
      if nargin < 3 || strlength(string(error_id)) == 0
        error_id = "experiment:modecontrol:invalidConfig";
      end
      t = plc_symbols.types;
      ctrl = struct( ...
        "modeFlagsSymbol", "", ...
        "experimentStateSymbol", "", ...
        "experimentActiveSymbol", "GVL_MODE.experimentActive", ...
        "loggerFileReleasedSymbol", "GVL_MODE.loggerFileReleased", ...
        "loggerErrorCodeSymbol", "GVL_MODE.loggerErrorCode", ...
        "hostHeartbeatCounterSymbol", string(plc_symbols.hostHeartbeatCounter), ...
        "resetReqSymbol", string(plc_symbols.modeResetReq), ...
        "resetAckCounterSymbol", string(plc_symbols.modeResetAckCounter), ...
        "MODEF_SERVO_ENABLE", uint32(hex2dec("0001")), ...
        "MODEF_EXPERIMENT_START_REQ", uint32(hex2dec("0002")), ...
        "MODEF_RESET_REQ", uint32(hex2dec("0004")), ...
        "STATE_READY", uint32(1), ...
        "STATE_DONE", uint32(3));

      mode_candidates = string(plc_symbols.modeFlags);
      if isprop(plc_symbols, "modeFlagsCandidates") && ~isempty(plc_symbols.modeFlagsCandidates)
        mode_candidates = string(plc_symbols.modeFlagsCandidates(:));
      end
      mode_candidates = unique(mode_candidates(strlength(mode_candidates) > 0), "stable");
      for k = 1:numel(mode_candidates)
        sym = char(mode_candidates(k));
        try
          mode_t = experiment.ModeManagerControl.modeflags_type(t);
          current_value = control_transport.read_scalar(sym, mode_t);
          control_transport.write_scalar(sym, ...
            experiment.ModeManagerControl.cast_modeflags_value(mode_t, current_value), mode_t);
          ctrl.modeFlagsSymbol = sym;
          break;
        catch
        end
      end
      if strlength(string(ctrl.modeFlagsSymbol)) == 0
        error(error_id, "No writable modeFlags ADS symbol found. Tried: %s", strjoin(mode_candidates, ", "));
      end
      try
        control_transport.read_scalar(ctrl.resetAckCounterSymbol, t.u32);
        reset_req_current = logical(control_transport.read_scalar(ctrl.resetReqSymbol, t.bool));
        control_transport.write_scalar(ctrl.resetReqSymbol, reset_req_current, t.bool);
      catch
        error(error_id, "No reset handshake ADS symbols found. Required: %s, %s", ...
          char(string(ctrl.resetReqSymbol)), char(string(ctrl.resetAckCounterSymbol)));
      end
      try
        hb_current = uint32(control_transport.read_scalar(ctrl.hostHeartbeatCounterSymbol, t.u32));
        control_transport.write_scalar(ctrl.hostHeartbeatCounterSymbol, hb_current, t.u32);
      catch
        error(error_id, "No host heartbeat ADS symbol found. Required: %s", ...
          char(string(ctrl.hostHeartbeatCounterSymbol)));
      end

      state_candidates = strings(0, 1);
      if isprop(plc_symbols, "experimentStateCandidates") && ~isempty(plc_symbols.experimentStateCandidates)
        state_candidates = string(plc_symbols.experimentStateCandidates(:));
      elseif isprop(plc_symbols, "experimentState")
        state_candidates = string(plc_symbols.experimentState);
      end
      state_candidates = unique(state_candidates(strlength(state_candidates) > 0), "stable");
      for k = 1:numel(state_candidates)
        sym = char(state_candidates(k));
        try
          control_transport.read_scalar(sym, t.u32);
          ctrl.experimentStateSymbol = sym;
          break;
        catch
        end
      end
      try
        control_transport.read_scalar(char(string(plc_symbols.loggerFileReleased)), t.bool);
        ctrl.loggerFileReleasedSymbol = char(string(plc_symbols.loggerFileReleased));
      catch
        error(error_id, "No logger release ADS symbol found. Required: %s", ...
          char(string(plc_symbols.loggerFileReleased)));
      end
      try
        control_transport.read_scalar(char(string(plc_symbols.loggerErrorCode)), t.u32);
        ctrl.loggerErrorCodeSymbol = char(string(plc_symbols.loggerErrorCode));
      catch
        error(error_id, "No logger error ADS symbol found. Required: %s", ...
          char(string(plc_symbols.loggerErrorCode)));
      end
    end

    function write_mode_flags(control_transport, ctrl, value)
      t = twincat_ads.AdsTransport.net_types();
      mode_t = experiment.ModeManagerControl.modeflags_type(t);
      if bitand(uint32(value), uint32(ctrl.MODEF_RESET_REQ)) ~= 0
        error("experiment:modecontrol:invalidConfig", ...
          "MODEF_RESET_REQ in modeFlags is no longer supported. Use resetReq/resetAckCounter handshake.");
      end
      control_transport.write_scalar( ...
        ctrl.modeFlagsSymbol, experiment.ModeManagerControl.cast_modeflags_value(mode_t, value), mode_t);
    end

    function [acked, diag, heartbeat_state] = request_reset_and_wait_ack(control_transport, ctrl, timeout_s, heartbeat_state)
      if nargin < 4 || isempty(heartbeat_state)
        heartbeat_state = experiment.ModeManagerControl.heartbeat_disabled();
      end
      t = twincat_ads.AdsTransport.net_types();
      t0 = tic;
      acked = false;
      diag = struct("counter_before", NaN, "counter_after", NaN);
      counter_before = uint32(control_transport.read_scalar(ctrl.resetAckCounterSymbol, t.u32));
      control_transport.write_scalar(ctrl.resetReqSymbol, true, t.bool);
      diag.counter_before = double(counter_before);
      while toc(t0) < timeout_s
        counter_after = uint32(control_transport.read_scalar(ctrl.resetAckCounterSymbol, t.u32));
        diag.counter_after = double(counter_after);
        if counter_after ~= counter_before
          acked = true;
          return;
        end
        heartbeat_state = experiment.ModeManagerControl.tick_heartbeat(control_transport, ctrl, heartbeat_state, false);
        pause(0.01);
      end
    end

    function [ready, diag, heartbeat_state] = wait_for_reset_idle( ...
        plc_transport, control_transport, plc_symbols, ctrl, timeout_s, heartbeat_state)
      if nargin < 6 || isempty(heartbeat_state)
        heartbeat_state = experiment.ModeManagerControl.heartbeat_disabled();
      end
      t = plc_symbols.types;
      t0 = tic;
      ready = false;
      diag = struct("idx", NaN, "experiment_active", false);
      while toc(t0) < timeout_s
        idx = double(plc_transport.read_scalar(plc_symbols.idx, t.u32));
        exp_active = experiment.ModeManagerControl.try_read_experiment_active( ...
          control_transport, ctrl, t);
        diag.idx = idx;
        diag.experiment_active = logical(exp_active);
        ready = (idx == 0) && (~exp_active);
        if ready
          return;
        end
        heartbeat_state = experiment.ModeManagerControl.tick_heartbeat(control_transport, ctrl, heartbeat_state, false);
        pause(0.01);
      end
    end

    function [done, heartbeat_state] = wait_until_done( ...
        control_transport, plc_transport, plc_symbols, ctrl, timeout_s, heartbeat_state)
      if nargin < 6 || isempty(heartbeat_state)
        heartbeat_state = experiment.ModeManagerControl.heartbeat_disabled();
      end
      t = plc_symbols.types;
      t0 = tic;
      done = false;
      state_supported = strlength(string(ctrl.experimentStateSymbol)) > 0;
      seen_active = false;
      while toc(t0) < timeout_s
        [done, state_supported, seen_active] = experiment.ModeManagerControl.poll_done( ...
          control_transport, plc_transport, plc_symbols, ctrl, t, state_supported, seen_active);
        if done
          return;
        end
        heartbeat_state = experiment.ModeManagerControl.tick_heartbeat(control_transport, ctrl, heartbeat_state, false);
        pause(0.01);
      end
    end

    function [released, diag, heartbeat_state] = wait_for_logger_release( ...
        control_transport, ctrl, timeout_s, heartbeat_state)
      if nargin < 4 || isempty(heartbeat_state)
        heartbeat_state = experiment.ModeManagerControl.heartbeat_disabled();
      end
      t = twincat_ads.AdsTransport.net_types();
      t0 = tic;
      released = false;
      diag = struct( ...
        "file_released", false, ...
        "error_code", uint32(0), ...
        "detail", "");
      while toc(t0) < timeout_s
        diag.file_released = logical(control_transport.read_scalar(ctrl.loggerFileReleasedSymbol, t.bool));
        diag.error_code = uint32(control_transport.read_scalar(ctrl.loggerErrorCodeSymbol, t.u32));
        if diag.error_code ~= 0
          diag.detail = sprintf("logger error 0x%08X", diag.error_code);
          return;
        end
        if diag.file_released
          released = true;
          diag.detail = "logger file released";
          return;
        end
        heartbeat_state = experiment.ModeManagerControl.tick_heartbeat(control_transport, ctrl, heartbeat_state, false);
        pause(0.01);
      end
      diag.detail = sprintf("timed out waiting %.3f s for logger file release", timeout_s);
    end

    function logger = read_logger_status(control_transport, ctrl)
      t = twincat_ads.AdsTransport.net_types();
      logger = struct( ...
        "file_released", logical(control_transport.read_scalar(ctrl.loggerFileReleasedSymbol, t.bool)), ...
        "error_code", uint32(control_transport.read_scalar(ctrl.loggerErrorCodeSymbol, t.u32)));
    end

    function state = init_heartbeat(control_transport, ctrl, enabled, period_s)
      if nargin < 3 || isempty(enabled)
        enabled = true;
      end
      if nargin < 4 || isempty(period_s)
        period_s = 0.1;
      end
      state = struct( ...
        "enabled", logical(enabled), ...
        "period_s", double(period_s), ...
        "next_tick_s", 0.0, ...
        "counter", uint32(0), ...
        "started_at", tic);
      if ~state.enabled
        return;
      end
      t = twincat_ads.AdsTransport.net_types();
      state.counter = uint32(control_transport.read_scalar(ctrl.hostHeartbeatCounterSymbol, t.u32));
      state = experiment.ModeManagerControl.tick_heartbeat(control_transport, ctrl, state, true);
    end

    function state = heartbeat_disabled()
      state = struct( ...
        "enabled", false, ...
        "period_s", 0.1, ...
        "next_tick_s", inf, ...
        "counter", uint32(0), ...
        "started_at", tic);
    end

    function state = tick_heartbeat(control_transport, ctrl, state, force)
      if nargin < 4
        force = false;
      end
      if ~isstruct(state) || ~isfield(state, "enabled") || ~logical(state.enabled)
        return;
      end
      elapsed_s = toc(state.started_at);
      if ~force && elapsed_s < state.next_tick_s
        return;
      end
      t = twincat_ads.AdsTransport.net_types();
      state.counter = uint32(mod(double(state.counter) + 1, 2^32));
      control_transport.write_scalar(ctrl.hostHeartbeatCounterSymbol, state.counter, t.u32);
      state.next_tick_s = elapsed_s + state.period_s;
    end

    function [done, state_supported, seen_active] = poll_done( ...
        control_transport, plc_transport, plc_symbols, ctrl, t, state_supported, seen_active)
      done = false;
      if state_supported
        try
          state = uint32(control_transport.read_scalar(ctrl.experimentStateSymbol, t.u32));
          done = (state == ctrl.STATE_DONE);
          if done
            return;
          end
        catch
          state_supported = false;
        end
      end

      exp_active = experiment.ModeManagerControl.try_read_experiment_active( ...
        control_transport, ctrl, t);
      seen_active = seen_active || logical(exp_active);
      done = seen_active && (~logical(exp_active));
    end

    function net_type = modeflags_type(t)
      if ~isfield(t, "u16")
        error("experiment:modecontrol:invalidConfig", ...
          "ADS net type mapping must include u16 for GVL_MODE.modeFlags.");
      end
      net_type = t.u16;
    end
  end

  methods (Static, Access = private)
    function v = cast_modeflags_value(~, value)
      v = uint16(double(value));
    end

    function exp_active = try_read_experiment_active(control_transport, ctrl, t)
      try
        exp_active = logical(control_transport.read_scalar(ctrl.experimentActiveSymbol, t.bool));
      catch e
        error("experiment:modecontrol:readExperimentActiveFailed", ...
          "Failed to read '%s' via control transport (%s: %s).", ...
          char(string(ctrl.experimentActiveSymbol)), string(e.identifier), string(e.message));
      end
    end
  end
end
