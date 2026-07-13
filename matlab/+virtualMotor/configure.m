function out = configure(conn, plant_cfg, varargin)
% configure  Safely configure VirtualMotor while the common runtime is idle.

if ~isstruct(conn) || ~all(isfield(conn, ["seq", "ctrl", "module"])) || ...
    ~isa(conn.seq, "twincat_ads.IAdsTransport") || ...
    ~isa(conn.ctrl, "twincat_ads.IAdsTransport") || ...
    ~isa(conn.module, "twincat_ads.IAdsTransport")
  error("virtualMotor:configure:invalidConnection", ...
    "Connection must contain seq, ctrl, and module transports.");
end

env = resolve_environment(conn);
p = inputParser;
p.addParameter("taskDtNs", env.task_dt_ns(), @is_positive_integer);
p.addParameter("timeout_s", 5.0, @is_positive_scalar);
p.addParameter("validateSymbols", true, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});
opts = p.Results;

plant_cfg = virtualMotor.PlantConfig.from_struct(plant_cfg);
requested = struct( ...
  "plant", plant_cfg.to_struct(), ...
  "taskDtNs", uint64(opts.taskDtNs));
plc = experiment.RuntimeSymbols.from_defaults();
t = plc.types;

if logical(opts.validateSymbols)
  twincat_ads.SymbolBrowser.validate_symbols(conn.seq, {
    plc.tableLen, t.u32
  });
  twincat_ads.SymbolBrowser.validate_symbols(conn.ctrl, {
    plc.modeFlags, t.u16;
    plc.modeState, t.i16;
    plc.experimentActive, t.bool
  });
  vm_symbols = virtualMotor.Symbols.from_defaults();
  twincat_ads.SymbolBrowser.validate_symbols(conn.module, vm_symbols.requiredProbes);
end

assert_runtime_idle(conn, plc, t);
settle = virtualMotor.wait_for_settle(conn.module, double(opts.timeout_s));
assert_runtime_idle(conn, plc, t);
virtualMotor.writeParams(conn, plant_cfg, ...
  "taskDtNs", uint64(opts.taskDtNs), ...
  "validateSymbols", logical(opts.validateSymbols));
readback = virtualMotor.readParams(conn);

if ~plant_matches(requested.plant, readback.plant) || ...
    requested.taskDtNs ~= readback.taskDtNs
  error("virtualMotor:configure:readbackMismatch", ...
    "VirtualMotor parameter readback does not match the requested configuration.");
end

out = struct( ...
  "requested", requested, ...
  "readback", readback, ...
  "settle", settle, ...
  "verified", true);
end

function assert_runtime_idle(conn, plc, t)
mode_flags = uint16(conn.ctrl.read_scalar(plc.modeFlags, t.u16));
mode_state = int16(conn.ctrl.read_scalar(plc.modeState, t.i16));
experiment_active = logical(conn.ctrl.read_scalar(plc.experimentActive, t.bool));
table_len = uint32(conn.seq.read_scalar(plc.tableLen, t.u32));
if mode_flags ~= 0 || mode_state ~= 0 || experiment_active || table_len ~= 0
  error("virtualMotor:configure:runtimeNotIdle", ...
    "VirtualMotor configuration requires modeFlags=0, modeState=IDLE, " + ...
    "experimentActive=false, and tableLen=0; observed %u/%d/%d/%u.", ...
    mode_flags, mode_state, experiment_active, table_len);
end
end

function env = resolve_environment(conn)
if isfield(conn, "env") && ~isempty(conn.env)
  env = config.EnvironmentConfig.from_struct(conn.env);
else
  env = config.EnvironmentConfig.current();
end
end

function tf = plant_matches(expected, actual)
tf = isequaln(expected.motor.encoderResolution, actual.motor.encoderResolution) && ...
  isequaln(expected.load.encoderResolution, actual.load.encoderResolution);
numeric_paths = {
  "motor", "inertia"; "motor", "damping"; "motor", "ratedTorque";
  "motor", "tauLimit"; "motor", "velLimit"; "motor", "maxPermille";
  "load", "inertia"; "load", "damping"; "load", "ratedTorque";
  "load", "tauLimit"; "load", "velLimit";
  "coupling", "stiffness"; "coupling", "damping"
};
for k = 1:size(numeric_paths, 1)
  group = numeric_paths{k, 1};
  field = numeric_paths{k, 2};
  a = double(expected.(group).(field));
  b = double(actual.(group).(field));
  tolerance = 16 * eps(max([1, abs(a), abs(b)]));
  tf = tf && abs(a - b) <= tolerance;
end
end

function tf = is_positive_scalar(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && double(value) > 0;
end

function tf = is_positive_integer(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && ...
  double(value) > 0 && fix(double(value)) == double(value) && ...
  double(value) <= double(intmax("uint64"));
end
