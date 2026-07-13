function out = restart_runtime(env, varargin)
% restart_runtime  Restart an idle VM-only TwinCAT runtime to zero hidden state.
%
% This is intentionally opt-in. A TwinCAT System Service reset is the only
% deployed lifecycle transition that invokes VirtualMotorCore::ResetRuntimeState.

arguments
  env config.EnvironmentConfig
end
arguments (Repeating)
  varargin
end

p = inputParser;
p.addParameter("ads_assembly", "", @(x) ischar(x) || isstring(x));
p.addParameter("timeout_s", 30.0, @is_positive_scalar);
p.addParameter("poll_period_s", 0.25, @is_positive_scalar);
p.parse(varargin{:});
opts = p.Results;

symbols = experiment.RuntimeSymbols.from_defaults();
t = twincat_ads.AdsTransport.net_types();
idle_map = struct( ...
  "experiment_active", {{symbols.experimentActive, t.bool}}, ...
  "logger_file_released", {{symbols.loggerFileReleased, t.bool}}, ...
  "mode_state", {{symbols.modeState, t.i16}});

control = make_transport();
control_cleanup = onCleanup(@() control.disconnect());
control.connect(env.ams_net_id, env.control_port);
before = control.read_struct(idle_map);
if logical(before.experiment_active) || int16(before.mode_state) ~= int16(0)
  error("virtualMotor:restart:notIdle", ...
    "Refusing TwinCAT restart while experimentActive=%d or modeState=%d (loggerFileReleased=%d).", ...
    logical(before.experiment_active), int16(before.mode_state), ...
    logical(before.logger_file_released));
end
control.disconnect();
clear control_cleanup

service = make_transport();
service_cleanup = onCleanup(@() service.disconnect());
service.connect(env.ams_net_id, 10000);
client = service.read_client();
state_before = client.ReadState();
if state_before.AdsState ~= TwinCAT.Ads.AdsState.Run
  error("virtualMotor:restart:notRunning", ...
    "TwinCAT System Service must be in Run before reset; got %s.", ...
    string(state_before.AdsState));
end
client.WriteControl(TwinCAT.Ads.StateInfo( ...
  TwinCAT.Ads.AdsState.Reset, int16(state_before.DeviceState)));
service.disconnect();
clear service_cleanup

t0 = tic;
state_after = [];
last_error = "";
while toc(t0) < double(opts.timeout_s)
  probe = make_transport();
  try
    probe.connect(env.ams_net_id, 10000);
    state_after = probe.read_client().ReadState();
    probe.disconnect();
    if state_after.AdsState == TwinCAT.Ads.AdsState.Run
      break;
    end
  catch e
    last_error = string(e.message);
    probe.disconnect();
  end
  pause(min(double(opts.poll_period_s), max(double(opts.timeout_s) - toc(t0), 0)));
end
if isempty(state_after) || state_after.AdsState ~= TwinCAT.Ads.AdsState.Run
  error("virtualMotor:restart:timeout", ...
    "TwinCAT System Service did not return to Run within %.3f s. Last error: %s", ...
    double(opts.timeout_s), last_error);
end

plc_ready = false;
plc_state = struct();
while toc(t0) < double(opts.timeout_s)
  seq = make_transport();
  control_probe = make_transport();
  try
    seq.connect(env.ams_net_id, env.seq_port);
    control_probe.connect(env.ams_net_id, env.control_port);
    twincat_ads.SymbolBrowser.validate_symbols(seq, symbols.plcRequiredProbes);
    twincat_ads.SymbolBrowser.validate_symbols(control_probe, symbols.modeRequiredProbes);
    plc_state = control_probe.read_struct(idle_map);
    seq.disconnect();
    control_probe.disconnect();
    plc_ready = true;
    break;
  catch e
    last_error = string(e.message);
    seq.disconnect();
    control_probe.disconnect();
  end
  pause(min(double(opts.poll_period_s), max(double(opts.timeout_s) - toc(t0), 0)));
end
if ~plc_ready
  error("virtualMotor:restart:plcTimeout", ...
    "PLC runtime symbols did not become readable within %.3f s. Last error: %s", ...
    double(opts.timeout_s), last_error);
end
if logical(plc_state.experiment_active) || int16(plc_state.mode_state) ~= int16(0)
  error("virtualMotor:restart:notIdleAfterRestart", ...
    "PLC runtime returned non-IDLE after lifecycle reset.");
end

settled = [];
while toc(t0) < double(opts.timeout_s)
  module = make_transport();
  try
    module.connect(env.ams_net_id, env.module_port);
    remaining_s = max(double(opts.timeout_s) - toc(t0), 0.1);
    settled = virtualMotor.wait_for_settle(module, min(1.0, remaining_s));
    module.disconnect();
    break;
  catch e
    last_error = string(e.message);
    module.disconnect();
  end
  pause(min(double(opts.poll_period_s), max(double(opts.timeout_s) - toc(t0), 0)));
end
if isempty(settled)
  error("virtualMotor:restart:moduleTimeout", ...
    "VirtualMotor module port did not become readable within %.3f s. Last error: %s", ...
    double(opts.timeout_s), last_error);
end
if any([settled.motor_position_count, settled.load_position_count, ...
    settled.motor_velocity_count, settled.load_velocity_count] ~= 0)
  error("virtualMotor:restart:notZero", ...
    "VirtualMotor lifecycle restart returned nonzero observable state.");
end

out = struct( ...
  "restarted", true, ...
  "elapsed_s", toc(t0), ...
  "state_before", string(state_before.AdsState), ...
  "state_after", string(state_after.AdsState), ...
  "plc_ready", plc_ready, ...
  "observable_state", settled);

  function transport = make_transport()
    transport = twincat_ads.AdsTransport("ads_assembly", opts.ads_assembly);
  end
end

function tf = is_positive_scalar(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && double(value) > 0;
end
