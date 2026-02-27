classdef VirtualMotorService < handle
  properties (Access = private)
    plc_transport
    vm_transport
    control_transport
  end

  methods
    function obj = VirtualMotorService(plc_transport, vm_transport, control_transport)
      if ~isa(plc_transport, "twincat_ads.IAdsTransport")
        error("experiment:service:invalidDependency", ...
          "plc_transport must implement twincat_ads.IAdsTransport.");
      end
      if ~isa(vm_transport, "twincat_ads.IAdsTransport")
        error("experiment:service:invalidDependency", ...
          "vm_transport must implement twincat_ads.IAdsTransport.");
      end
      if nargin < 3 || isempty(control_transport)
        control_transport = plc_transport;
      end
      if ~isa(control_transport, "twincat_ads.IAdsTransport")
        error("experiment:service:invalidDependency", ...
          "control_transport must implement twincat_ads.IAdsTransport.");
      end
      obj.plc_transport = plc_transport;
      obj.vm_transport = vm_transport;
      obj.control_transport = control_transport;
    end

    function out = run(obj, cfg)
      if ~isa(cfg, "experiment.RunConfig")
        cfg = experiment.RunConfig.from_struct(cfg);
      end
      obj.ensure_folder(fileparts(cfg.save_path));

      plc_symbols = experiment.VirtualMotorSymbols.from_defaults();
      vm_symbols = experiment.VirtualMotorSymbols.from_vm_prefix(cfg.vm_param_symbol_prefix);
      controller_symbols = experiment.VirtualMotorSymbols.from_controller_prefix(cfg.controller_param_symbol_prefix);
      twincat_ads.SymbolBrowser.validate_symbols(obj.plc_transport, plc_symbols.plcRequiredProbes);
      twincat_ads.SymbolBrowser.validate_symbols(obj.vm_transport, vm_symbols.vmRequiredProbes);
      twincat_ads.SymbolBrowser.validate_symbols(obj.vm_transport, controller_symbols.controllerRequiredProbes);
      t = plc_symbols.types;
      ctrl = obj.resolve_control_symbols(plc_symbols);
      heartbeat_state = experiment.ModeManagerControl.init_heartbeat( ...
        obj.control_transport, ctrl, cfg.host_heartbeat_enable, cfg.host_heartbeat_period_s);

      vmParams = struct();
      vmParams.m = cfg.m;
      vmParams.d = cfg.d;
      vmParams.kt = cfg.kt;
      vmParams.tauLimit = cfg.tau_limit;
      vmParams.velLimit = cfg.vel_limit;
      vmParams.taskDtNs = cfg.task_dt_ns;
      obj.write_vmParams(vm_symbols, vmParams);
      obj.write_controllerParams(controller_symbols, cfg);

      ref_profile = cfg.ref_profile(:);
      ff_profile = cfg.ff_profile(:);
      dist_profile = cfg.dist_profile(:);
      log_data = struct( ...
        "logSeq", zeros(0, 1), ...
        "logRefValue", zeros(0, 1), ...
        "logFfValue", zeros(0, 1), ...
        "logDistValue", zeros(0, 1), ...
        "logControlInput", zeros(0, 1), ...
        "logTargetCurrent", zeros(0, 1), ...
        "logPositionAct", zeros(0, 1), ...
        "logT", zeros(0, 1), ...
        "logIdx", zeros(0, 1), ...
        "wrIdx", 0, ...
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
      table_n = numel(ref_profile);
      if table_n > double(cfg.table_max_n)
        error("experiment:service:invalidProfile", ...
          "ref_profile length (%d) exceeds table_max_n (%d).", table_n, cfg.table_max_n);
      end

      obj.write_mode_flags(ctrl, uint32(0));
      obj.plc_transport.write_scalar(plc_symbols.tableLen, uint32(0), t.u32);
      [reset_acked, reset_diag, heartbeat_state] = obj.request_reset_and_wait_ack( ...
        ctrl, cfg.reset_timeout_s, heartbeat_state);
      if ~reset_acked
        error("experiment:service:resetAckTimeout", ...
          "Timed out waiting reset acknowledgement (resetAckCounter before=%g after=%g).", ...
          reset_diag.counter_before, reset_diag.counter_after);
      end

      [idle_ready, heartbeat_state] = obj.wait_for_reset_idle( ...
        plc_symbols, ctrl, cfg.reset_timeout_s, heartbeat_state);
      if ~idle_ready
        error("experiment:service:resetSyncTimeout", ...
          "Timed out waiting reset idle state (wrIdx==0, idx==0, experimentActive==FALSE).");
      end

      obj.plc_transport.write_array(plc_symbols.refTable, ref_profile, t.double);
      obj.plc_transport.write_array(plc_symbols.ffTable, ff_profile, t.double);
      obj.plc_transport.write_array(plc_symbols.distTable, dist_profile, t.double);
      obj.plc_transport.write_scalar(plc_symbols.tableLen, uint32(table_n), t.u32);
      obj.write_mode_flags(ctrl, uint32(ctrl.MODEF_SERVO_ENABLE));
      obj.write_mode_flags(ctrl, uint32(bitor(ctrl.MODEF_SERVO_ENABLE, ctrl.MODEF_EXPERIMENT_START_REQ)));

      if cfg.wait_for_done && cfg.log_stream_enable
        [done, log_data, host_log_stats, heartbeat_state] = obj.wait_until_done_streaming( ...
          plc_symbols, ctrl, cfg, heartbeat_state);
        log_read_time = host_log_stats.log_read_time_s_total;
        if ~done
          warning("experiment:service:timeout", "Timed out waiting for experiment completion.");
        end
      elseif cfg.wait_for_done
        [done, heartbeat_state] = obj.wait_until_done( ...
          plc_symbols, ctrl, cfg.done_timeout_s, heartbeat_state);
        if ~done
          warning("experiment:service:timeout", "Timed out waiting for experiment completion.");
        end
      else
        while toc(t_run) < cfg.hold_seconds
          heartbeat_state = experiment.ModeManagerControl.tick_heartbeat( ...
            obj.control_transport, ctrl, heartbeat_state, false);
          pause(min(0.05, cfg.hold_seconds / 10 + eps));
        end
      end
      obj.write_mode_flags(ctrl, uint32(0));
      elapsed_s = toc(t_run);

      position_last = obj.plc_transport.read_scalar(plc_symbols.positionActLog, t.double);
      controlInput_last = obj.plc_transport.read_scalar(plc_symbols.controlInput, t.double);

      raw = struct();
      raw.position_last = double(position_last);
      raw.controlInput_last = double(controlInput_last);

      if ~(cfg.wait_for_done && cfg.log_stream_enable && host_log_stats.log_stream_enabled)
        [log_data, log_read_time] = obj.read_upper_logs(plc_symbols, cfg.log_n);
      end
      raw.logSeq = log_data.logSeq;
      raw.logRefValue = log_data.logRefValue;
      raw.logFfValue = log_data.logFfValue;
      raw.logDistValue = log_data.logDistValue;
      raw.logControlInput = log_data.logControlInput;
      raw.logTargetCurrent = log_data.logTargetCurrent;
      raw.logPositionAct = log_data.logPositionAct;
      raw.logT = log_data.logT;
      raw.logIdx = log_data.logIdx;
      raw.log_wrIdx = log_data.wrIdx;
      raw.log_overflow = log_data.overflow;
      if isempty(raw.logTargetCurrent)
        raw.target_current_last = NaN;
      else
        raw.target_current_last = raw.logTargetCurrent(end);
      end

      cmd = struct();
      cmd.ref_profile = ref_profile;
      cmd.ff_profile = ff_profile;
      cmd.dist_profile = dist_profile;
      cmd.tableLen = table_n;
      cmd.use_profile = true;
      cmd.hold_seconds = cfg.hold_seconds;

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
      host.host_heartbeat_enable = logical(cfg.host_heartbeat_enable);
      host.host_heartbeat_period_s = double(cfg.host_heartbeat_period_s);
      host.control_mode_flags_symbol = char(string(ctrl.modeFlagsSymbol));
      host.control_experiment_state_symbol = char(string(ctrl.experimentStateSymbol));

      cfg_struct = cfg.to_struct();
      metrics = experiment.preload_eval(raw, cmd, cfg_struct);
      if cfg.wait_for_done && ~logical(cfg.log_require_waveform_exact) && ...
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
    function write_vmParams(obj, symbols, params)
      t = symbols.types;
      obj.vm_transport.write_scalar(symbols.vmParams.m, params.m, t.double);
      obj.vm_transport.write_scalar(symbols.vmParams.d, params.d, t.double);
      obj.vm_transport.write_scalar(symbols.vmParams.kt, params.kt, t.double);
      obj.vm_transport.write_scalar(symbols.vmParams.tauLimit, params.tauLimit, t.double);
      obj.vm_transport.write_scalar(symbols.vmParams.velLimit, params.velLimit, t.double);
      obj.vm_transport.write_scalar(symbols.vmParams.taskDtNs, uint64(params.taskDtNs), t.u64);
    end

    function write_controllerParams(obj, symbols, cfg)
      t = symbols.types;
      p = symbols.controllerParams;
      obj.vm_transport.write_scalar(p.pidB0, cfg.pid_b0, t.double);
      obj.vm_transport.write_scalar(p.pidB1, cfg.pid_b1, t.double);
      obj.vm_transport.write_scalar(p.pidB2, cfg.pid_b2, t.double);
      obj.vm_transport.write_scalar(p.pidA1, cfg.pid_a1, t.double);
      obj.vm_transport.write_scalar(p.pidA2, cfg.pid_a2, t.double);

      obj.vm_transport.write_scalar(p.leadB0, cfg.lead_b0, t.double);
      obj.vm_transport.write_scalar(p.leadB1, cfg.lead_b1, t.double);
      obj.vm_transport.write_scalar(p.leadB2, cfg.lead_b2, t.double);
      obj.vm_transport.write_scalar(p.leadA1, cfg.lead_a1, t.double);
      obj.vm_transport.write_scalar(p.leadA2, cfg.lead_a2, t.double);

      obj.vm_transport.write_scalar(p.notchB0, cfg.notch_b0, t.double);
      obj.vm_transport.write_scalar(p.notchB1, cfg.notch_b1, t.double);
      obj.vm_transport.write_scalar(p.notchB2, cfg.notch_b2, t.double);
      obj.vm_transport.write_scalar(p.notchA1, cfg.notch_a1, t.double);
      obj.vm_transport.write_scalar(p.notchA2, cfg.notch_a2, t.double);
      obj.vm_transport.write_scalar(p.resoB0, cfg.reso_b0, t.double);
      obj.vm_transport.write_scalar(p.resoB1, cfg.reso_b1, t.double);
      obj.vm_transport.write_scalar(p.resoB2, cfg.reso_b2, t.double);
      obj.vm_transport.write_scalar(p.resoA1, cfg.reso_a1, t.double);
      obj.vm_transport.write_scalar(p.resoA2, cfg.reso_a2, t.double);

      obj.vm_transport.write_scalar(p.enablePid, cfg.enable_pid, t.bool);
      obj.vm_transport.write_scalar(p.enableLead, cfg.enable_lead, t.bool);
      obj.vm_transport.write_scalar(p.enableNotch, cfg.enable_notch, t.bool);
      obj.vm_transport.write_scalar(p.enableReso, cfg.enable_reso, t.bool);
    end

    function ctrl = resolve_control_symbols(obj, symbols)
      ctrl = experiment.ModeManagerControl.resolve_symbols( ...
        obj.control_transport, symbols, "experiment:service:invalidConfig");
    end

    function write_mode_flags(obj, ctrl, value)
      experiment.ModeManagerControl.write_mode_flags(obj.control_transport, ctrl, value);
    end

    function [acked, diag, heartbeat_state] = request_reset_and_wait_ack( ...
        obj, ctrl, timeout_s, heartbeat_state)
      [acked, diag, heartbeat_state] = experiment.ModeManagerControl.request_reset_and_wait_ack( ...
        obj.control_transport, ctrl, timeout_s, heartbeat_state);
    end

    function [done, heartbeat_state] = wait_until_done(obj, symbols, ctrl, timeout_s, heartbeat_state)
      [done, heartbeat_state] = experiment.ModeManagerControl.wait_until_done( ...
        obj.control_transport, obj.plc_transport, symbols, ctrl, timeout_s, heartbeat_state);
    end

    function [done, log_data, host_stats, heartbeat_state] = wait_until_done_streaming( ...
        obj, symbols, ctrl, cfg, heartbeat_state)
      t = symbols.types;
      t0 = tic;
      done = false;
      ring_n = obj.read_log_ring_capacity(symbols, cfg);
      state = obj.init_log_stream_state();
      state_supported = strlength(string(ctrl.experimentStateSymbol)) > 0;
      seen_active = false;
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
          wrIdx = double(obj.plc_transport.read_scalar(symbols.log.wrIdx, t.u32));
          plc_overflow = logical(obj.plc_transport.read_scalar(symbols.log.overflow, t.bool));
          [state, local_overflow] = obj.drain_log_ring_to_host(symbols, cfg, ring_n, state, wrIdx);
          if local_overflow && cfg.log_warn_on_overflow && ~state.overflow_warned
            warning("experiment:service:logOverflow", ...
              "Host log consumer fell behind PLC ring buffer capacity; some samples were overwritten.");
            state.overflow_warned = true;
          end
          state.overflow = state.overflow || plc_overflow || local_overflow;
          host_stats.log_stream_cycles = host_stats.log_stream_cycles + 1;
          [done, state_supported, seen_active] = experiment.ModeManagerControl.poll_done( ...
            obj.control_transport, obj.plc_transport, symbols, ctrl, t, state_supported, seen_active);
          if done
            try
              wrIdx_final = double(obj.plc_transport.read_scalar(symbols.log.wrIdx, t.u32));
              plc_overflow_final = logical(obj.plc_transport.read_scalar(symbols.log.overflow, t.bool));
              [state, local_overflow_final] = obj.drain_log_ring_to_host(symbols, cfg, ring_n, state, wrIdx_final);
              if local_overflow_final && cfg.log_warn_on_overflow && ~state.overflow_warned
                warning("experiment:service:logOverflow", ...
                  "Host log consumer fell behind PLC ring buffer capacity; some samples were overwritten.");
                state.overflow_warned = true;
              end
              state.overflow = state.overflow || plc_overflow_final || local_overflow_final;
              wrIdx = wrIdx_final;
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
          [done, heartbeat_state] = obj.wait_until_done( ...
            symbols, ctrl, max(0, cfg.done_timeout_s - toc(t0)), heartbeat_state);
          host_stats.log_stream_enabled = false;
          host_stats.log_stream_fallback_used = true;
          log_data = struct( ...
            "logSeq", zeros(0, 1), ...
            "logRefValue", zeros(0, 1), ...
            "logFfValue", zeros(0, 1), ...
            "logDistValue", zeros(0, 1), ...
            "logControlInput", zeros(0, 1), ...
            "logTargetCurrent", zeros(0, 1), ...
            "logPositionAct", zeros(0, 1), ...
            "logT", zeros(0, 1), ...
            "logIdx", zeros(0, 1), ...
            "wrIdx", 0, ...
            "overflow", false);
          return;
        end
        heartbeat_state = experiment.ModeManagerControl.tick_heartbeat( ...
          obj.control_transport, ctrl, heartbeat_state, false);
        pause(cfg.log_poll_period_s);
      end

      if ~done
        try
          wrIdx = double(obj.plc_transport.read_scalar(symbols.log.wrIdx, t.u32));
          plc_overflow = logical(obj.plc_transport.read_scalar(symbols.log.overflow, t.bool));
          [state, local_overflow] = obj.drain_log_ring_to_host(symbols, cfg, ring_n, state, wrIdx);
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
          wrIdx = state.next_read_idx;
        end
      end

      host_stats.log_samples_captured = state.sample_count;
      host_stats.log_read_time_s_total = state.read_time_s;
      log_data = obj.finalize_log_stream_state(state);
      log_data.wrIdx = wrIdx;
      log_data.overflow = logical(state.overflow);
    end

    function [ready, heartbeat_state] = wait_for_reset_idle( ...
        obj, symbols, ctrl, timeout_s, heartbeat_state)
      [ready, ~, heartbeat_state] = experiment.ModeManagerControl.wait_for_reset_idle( ...
        obj.plc_transport, obj.control_transport, symbols, ctrl, timeout_s, heartbeat_state);
    end

    function ring_n = read_log_ring_capacity(obj, symbols, cfg)
      t = symbols.types;
      try
        ring_n = double(obj.plc_transport.read_scalar(symbols.log.logN, t.u32));
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
        "chunks_refValue", {cell(0, 1)}, ...
        "chunks_ffValue", {cell(0, 1)}, ...
        "chunks_distValue", {cell(0, 1)}, ...
        "chunks_controlInput", {cell(0, 1)}, ...
        "chunks_target_current", {cell(0, 1)}, ...
        "chunks_position_act", {cell(0, 1)}, ...
        "chunks_t", {cell(0, 1)}, ...
        "chunks_idx", {cell(0, 1)}, ...
        "overflow", false, ...
        "overflow_warned", false, ...
        "rdIdx_supported", true, ...
        "rdIdx_warned", false, ...
        "read_time_s", 0);
    end

    function [state, local_overflow] = drain_log_ring_to_host(obj, symbols, cfg, ring_n, state, wrIdx)
      t = symbols.types;
      local_overflow = false;
      pending = double(wrIdx) - double(state.next_read_idx);
      if pending <= 0
        return;
      end

      if pending > ring_n
        local_overflow = true;
        state.overflow = true;
        state.next_read_idx = double(wrIdx) - ring_n;
        pending = ring_n;
      end

      while pending > 0
        take_n = min(pending, floor(double(cfg.log_chunk_n)));
        [chunk, read_elapsed] = obj.read_ring_chunk(symbols, t, state.next_read_idx, take_n, ring_n);
        state.read_time_s = state.read_time_s + read_elapsed;
        state = obj.append_log_chunk(state, chunk, cfg);
        state.next_read_idx = state.next_read_idx + take_n;
        pending = double(wrIdx) - double(state.next_read_idx);
      end

      if state.rdIdx_supported
        try
          obj.plc_transport.write_scalar(symbols.log.rdIdx, uint32(state.next_read_idx), t.u32);
        catch e
          state.rdIdx_supported = false;
          if ~state.rdIdx_warned
            warning("experiment:service:rdIdxUnavailable", ...
              "GVL_SEQ_LOG.rdIdx write unavailable; continuing without PLC-side consumer index sync (%s: %s).", ...
              string(e.identifier), string(e.message));
            state.rdIdx_warned = true;
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
      % PLC logger writes absolute sequence numbers (GVL_SEQ_LOG.seq) in lockstep with wrIdx.
      % Reconstructing from abs_start_idx avoids TwinCAT/MATLAB UDINT[] slice marshaling issues.
      chunk.logSeq = obj.make_expected_seq_chunk(abs_start_idx, take_n);
      chunk.logRefValue = obj.read_log_component_slice(symbols.log.logRefValue, t.double, start_ring, n1, n2);
      chunk.logFfValue = obj.read_log_component_slice(symbols.log.logFfValue, t.double, start_ring, n1, n2);
      chunk.logDistValue = obj.read_log_component_slice(symbols.log.logDistValue, t.double, start_ring, n1, n2);
      chunk.logControlInput = obj.read_log_component_slice(symbols.log.logControlInput, t.double, start_ring, n1, n2);
      chunk.logTargetCurrent = obj.read_log_component_slice(symbols.log.logTargetCurrent, t.double, start_ring, n1, n2);
      chunk.logPositionAct = obj.read_log_component_slice(symbols.log.logPositionAct, t.double, start_ring, n1, n2);
      try
        chunk.logT = obj.read_log_component_slice(symbols.log.logT, t.u64, start_ring, n1, n2);
      catch
        % logT is optional for current validation/plot flow; keep capture alive if MATLAB cannot marshal UInt64[].
        chunk.logT = zeros(double(take_n), 1);
      end
      try
        chunk.logIdx = obj.read_log_component_slice(symbols.log.logIdx, t.u32, start_ring, n1, n2);
      catch
        chunk.logIdx = zeros(0, 1);
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
      % PLC stores seq := seq + 1 each sample and increments wrIdx once per sample.
      % Therefore the absolute write index k maps to sequence k+1 after reset.
      seq = double(abs_start_idx) + (1:double(take_n))';
      max_udint = 2^32;
      seq = mod(seq, max_udint);
    end

    function state = append_log_chunk(~, state, chunk, cfg)
      n_chunk = numel(chunk.logSeq);
      if ~isinf(cfg.log_host_max_n) && (double(state.sample_count) + double(n_chunk) > double(cfg.log_host_max_n))
        error("experiment:service:hostLogLimit", ...
          "Host log buffer exceeded log_host_max_n (%g samples).", double(cfg.log_host_max_n));
      end
      if n_chunk == 0
        return;
      end
      state.chunks_seq{end + 1, 1} = double(chunk.logSeq(:));
      state.chunks_refValue{end + 1, 1} = double(chunk.logRefValue(:));
      state.chunks_ffValue{end + 1, 1} = double(chunk.logFfValue(:));
      state.chunks_distValue{end + 1, 1} = double(chunk.logDistValue(:));
      state.chunks_controlInput{end + 1, 1} = double(chunk.logControlInput(:));
      state.chunks_target_current{end + 1, 1} = double(chunk.logTargetCurrent(:));
      state.chunks_position_act{end + 1, 1} = double(chunk.logPositionAct(:));
      state.chunks_t{end + 1, 1} = double(chunk.logT(:));
      if isfield(chunk, "logIdx") && ~isempty(chunk.logIdx)
        state.chunks_idx{end + 1, 1} = double(chunk.logIdx(:));
      end
      state.sample_count = state.sample_count + n_chunk;
    end

    function log_data = finalize_log_stream_state(~, state)
      log_data = struct( ...
        "logSeq", zeros(0, 1), ...
        "logRefValue", zeros(0, 1), ...
        "logFfValue", zeros(0, 1), ...
        "logDistValue", zeros(0, 1), ...
        "logControlInput", zeros(0, 1), ...
        "logTargetCurrent", zeros(0, 1), ...
        "logPositionAct", zeros(0, 1), ...
        "logT", zeros(0, 1), ...
        "logIdx", zeros(0, 1), ...
        "wrIdx", 0, ...
        "overflow", false);
      if ~isempty(state.chunks_seq)
        log_data.logSeq = vertcat(state.chunks_seq{:});
        log_data.logRefValue = vertcat(state.chunks_refValue{:});
        log_data.logFfValue = vertcat(state.chunks_ffValue{:});
        log_data.logDistValue = vertcat(state.chunks_distValue{:});
        log_data.logControlInput = vertcat(state.chunks_controlInput{:});
        log_data.logTargetCurrent = vertcat(state.chunks_target_current{:});
        log_data.logPositionAct = vertcat(state.chunks_position_act{:});
        log_data.logT = vertcat(state.chunks_t{:});
        if ~isempty(state.chunks_idx)
          log_data.logIdx = vertcat(state.chunks_idx{:});
        end
      end
    end

    function [log_data, read_time] = read_upper_logs(obj, symbols, logN)
      t = symbols.types;
      t_read = tic;
      log_data = struct( ...
        "logSeq", zeros(0, 1), ...
        "logRefValue", zeros(0, 1), ...
        "logFfValue", zeros(0, 1), ...
        "logDistValue", zeros(0, 1), ...
        "logControlInput", zeros(0, 1), ...
        "logTargetCurrent", zeros(0, 1), ...
        "logPositionAct", zeros(0, 1), ...
        "logT", zeros(0, 1), ...
        "logIdx", zeros(0, 1), ...
        "wrIdx", 0, ...
        "overflow", false);

      try
        wrIdx = obj.plc_transport.read_scalar(symbols.log.wrIdx, t.u32);
        overflow = obj.plc_transport.read_scalar(symbols.log.overflow, t.bool);
        valid_n = uint32(min(double(wrIdx), logN));
        if valid_n > 0
          log_data.logSeq = double(obj.plc_transport.read_array(symbols.log.logSeq, t.u32, valid_n));
          log_data.logRefValue = double(obj.plc_transport.read_array(symbols.log.logRefValue, t.double, valid_n));
          log_data.logFfValue = double(obj.plc_transport.read_array(symbols.log.logFfValue, t.double, valid_n));
          log_data.logDistValue = double(obj.plc_transport.read_array(symbols.log.logDistValue, t.double, valid_n));
          log_data.logControlInput = double(obj.plc_transport.read_array(symbols.log.logControlInput, t.double, valid_n));
          log_data.logTargetCurrent = double(obj.plc_transport.read_array(symbols.log.logTargetCurrent, t.double, valid_n));
          log_data.logPositionAct = double(obj.plc_transport.read_array(symbols.log.logPositionAct, t.double, valid_n));
          try
            log_data.logT = double(obj.plc_transport.read_array(symbols.log.logT, t.u64, valid_n));
          catch
            % logT is optional; keep logs if TwinCAT UInt64[] cannot be marshaled in MATLAB/.NET interop.
            log_data.logT = zeros(double(valid_n), 1);
          end
          try
            log_data.logIdx = double(obj.plc_transport.read_array(symbols.log.logIdx, t.u32, valid_n));
          catch
            log_data.logIdx = zeros(0, 1);
          end
        end
        log_data.wrIdx = double(wrIdx);
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

      n_seq = numel(raw.logSeq);
      n_ref = numel(raw.logRefValue);
      n_pos = numel(raw.logPositionAct);
      n_ff = numel(raw.logFfValue);
      n_dist = numel(raw.logDistValue);
      n_u = numel(raw.logControlInput);
      n_tau = numel(raw.logTargetCurrent);
      if n_seq == 0
        error("experiment:service:incompleteLog", ...
          "No log samples captured (logSeq/logRefValue/logPositionAct are empty).");
      end
      if raw.log_overflow
        error("experiment:service:incompleteLog", ...
          "PLC/host log overflow detected (raw.log_overflow=true).");
      end
      if ~(n_seq == n_ref && n_ref == n_pos && n_ref == n_ff && n_ref == n_dist && n_ref == n_u && n_ref == n_tau)
        error("experiment:service:incompleteLog", ...
          "Log component sample counts mismatch (seq=%d, ref=%d, ff=%d, dist=%d, u=%d, tau=%d, pos=%d).", ...
          n_seq, n_ref, n_ff, n_dist, n_u, n_tau, n_pos);
      end
      if n_seq > 1 && ~all(udint_seq_step_is_one(raw.logSeq(:)))
        missing_n = sum(~udint_seq_step_is_one(raw.logSeq(:)));
        error("experiment:service:incompleteLog", ...
          "Sequence gap detected in logSeq (%d discontinuities).", missing_n);
      end
      if cmd.use_profile && cfg.wait_for_done && (n_ref ~= numel(cmd.ref_profile))
        error("experiment:service:incompleteLog", ...
          "Profile/log sample count mismatch (table=%d, refLog=%d, posLog=%d).", ...
          numel(cmd.ref_profile), n_ref, n_pos);
      end

      if isfield(metrics, "sampling") && isfield(metrics.sampling, "all_sample_counts_match") && ...
          ~logical(metrics.sampling.all_sample_counts_match)
        error("experiment:service:incompleteLog", ...
          "Sampling count check failed (table=%d, refLog=%d, posLog=%d).", ...
          numel(cmd.ref_profile), n_ref, n_pos);
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


