function applied_revision = write_controller_params(transport, controller_param_symbol_prefix, controller)
% write_controller_params  Commit a fixed ten-section SOS bank to ControllerCore.
%
% Writes are ordered as coefficients -> sectionCount -> applyRevision.
% ControllerCore keeps the old active bank until applyRevision is accepted.

  arguments
    transport twincat_ads.IAdsTransport
    controller_param_symbol_prefix {mustBeTextScalar}
    controller
  end

  cfg = experiment.ControllerConfig.from_struct(controller);
  payload = cfg.to_ads_payload();
  symbols = experiment.RuntimeSymbols.from_controller_prefix( ...
    char(string(controller_param_symbol_prefix)));
  t = symbols.types;
  p = symbols.controllerParams;

  current_revision = uint32(transport.read_scalar(p.applyRevision, t.u32));
  requested_revision = next_revision(current_revision);

  transport.write_array(p.coefficients, payload.coefficients, t.double);
  transport.write_scalar(p.sectionCount, payload.section_count, t.u32);
  transport.write_scalar(p.applyRevision, requested_revision, t.u32);

  applied_revision = wait_for_apply_ack(transport, p, t, requested_revision);
end

function revision = next_revision(current)
revision = uint32(mod(double(uint32(current)) + 1, 2^32));
end

function applied = wait_for_apply_ack(transport, symbols, types, requested)
timeout_s = 0.5;
poll_period_s = 0.005;
timer = tic;
% Allow at least one 8 kHz ControllerCore cycle to process the new revision.
% This also prevents a previous rejected revision's error code from being
% mistaken for the result of the payload that was just committed.
pause(poll_period_s);
while true
  processed = uint32(transport.read_scalar(symbols.processedRevision, types.u32));
  if processed == requested
    applied = uint32(transport.read_scalar(symbols.appliedRevision, types.u32));
    error_code = uint32(transport.read_scalar(symbols.parameterErrorCode, types.u32));
    if applied == requested && error_code == 0
      return;
    end
    if error_code ~= 0
      error("experiment:controller:parameterRejected", ...
        "ControllerCore rejected SOS revision %u (parameterErrorCode=0x%08X).", ...
        requested, error_code);
    end
    error("experiment:controller:invalidApplyStatus", ...
      "ControllerCore processed SOS revision %u without applying or rejecting it.", requested);
  end
  if toc(timer) >= timeout_s
    applied = uint32(transport.read_scalar(symbols.appliedRevision, types.u32));
    error("experiment:controller:applyTimeout", ...
      "Timed out waiting for ControllerCore SOS revision %u (processed=%u, applied=%u).", ...
      requested, processed, applied);
  end
  pause(poll_period_s);
end
end
