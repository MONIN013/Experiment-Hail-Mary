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
    end

    function write_mode_flags(control_transport, ctrl, value)
      t = twincat_ads.AdsTransport.net_types();
      mode_t = experiment.ModeManagerControl.modeflags_type(t);
      control_transport.write_scalar( ...
        ctrl.modeFlagsSymbol, experiment.ModeManagerControl.cast_modeflags_value(mode_t, value), mode_t);
    end

    function pulse_reset(control_transport, ctrl, pulse_seconds)
      experiment.ModeManagerControl.write_mode_flags(control_transport, ctrl, ctrl.MODEF_RESET_REQ);
      pause(pulse_seconds);
      experiment.ModeManagerControl.write_mode_flags(control_transport, ctrl, uint32(0));
    end

    function [ready, diag] = wait_for_reset_idle(plc_transport, control_transport, plc_symbols, ctrl, timeout_s)
      t = plc_symbols.types;
      t0 = tic;
      ready = false;
      diag = struct("wr_idx", NaN, "idx", NaN, "experiment_active", false);
      while toc(t0) < timeout_s
        try
          wr_idx = double(plc_transport.read_scalar(plc_symbols.log.wrIdx, t.u32));
          idx = double(plc_transport.read_scalar(plc_symbols.idx, t.u32));
          [ok_active, exp_active] = experiment.ModeManagerControl.try_read_experiment_active( ...
            control_transport, plc_transport, plc_symbols, ctrl, t);
          if ~ok_active
            ready = false;
          else
            diag.wr_idx = wr_idx;
            diag.idx = idx;
            diag.experiment_active = logical(exp_active);
            ready = (wr_idx == 0) && (idx == 0) && (~exp_active);
          end
        catch
          ready = false;
        end
        if ready
          return;
        end
        pause(0.01);
      end
    end

    function done = wait_until_done(control_transport, plc_transport, plc_symbols, ctrl, timeout_s)
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
        pause(0.01);
      end
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

      [ok_active, exp_active] = experiment.ModeManagerControl.try_read_experiment_active( ...
        control_transport, plc_transport, plc_symbols, ctrl, t);
      if ok_active
        seen_active = seen_active || logical(exp_active);
        done = seen_active && (~logical(exp_active));
      end
    end

    function net_type = modeflags_type(t)
      if isfield(t, "u16")
        net_type = t.u16;
      else
        net_type = t.u32;
      end
    end
  end

  methods (Static, Access = private)
    function v = cast_modeflags_value(net_type, value)
      net_type = string(net_type);
      if net_type == "System.UInt16"
        v = uint16(double(value));
      else
        v = uint32(double(value));
      end
    end

    function [ok_active, exp_active] = try_read_experiment_active(control_transport, plc_transport, plc_symbols, ctrl, t)
      ok_active = false;
      exp_active = false;
      try
        exp_active = logical(control_transport.read_scalar(ctrl.experimentActiveSymbol, t.bool));
        ok_active = true;
        return;
      catch
      end
      try
        exp_active = logical(plc_transport.read_scalar(plc_symbols.experimentActive, t.bool));
        ok_active = true;
      catch
        ok_active = false;
        exp_active = false;
      end
    end
  end
end
