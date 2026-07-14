function result = run_exp01(scenario, varargin)
% run_exp01  Execute and analyze the system-identification scenario.

p = inputParser;
p.addParameter("collector", @experiment.exp0n.run_and_collect, ...
  @(x) isa(x, "function_handle"));
p.parse(varargin{:});
validate_scenario(scenario, "exp01");

ensure_result_directory(scenario);
collected = p.Results.collector(scenario.cfg);
experiment.exp0n.assert_run_contract(collected.run);
logger_bin = collected.logger_bin;
raw = require_raw_signals(logger_bin, ...
  ["ff_value", "control_input", "load_position", "motor_position", ...
   "load_velocity", "motor_velocity"]);

sample_count = double(scenario.expected_sample_count);
if double(logger_bin.record_count) < sample_count
  error("experiment:workflow:exp01LoggerTooShort", ...
    "Expected at least %d logger records, got %d.", ...
    sample_count, double(logger_bin.record_count));
end
input = double(raw.ff_value(1:sample_count));
control_input = double(raw.control_input(1:sample_count));
loadpos = double(raw.load_position(1:sample_count));
motorpos = double(raw.motor_position(1:sample_count));
loadvel = double(raw.load_velocity(1:sample_count));
motorvel = double(raw.motor_velocity(1:sample_count));
input = input(:);
control_input = control_input(:);
loadpos = loadpos(:);
motorpos = motorpos(:);
loadvel = loadvel(:);
motorvel = motorvel(:);

Ts = double(scenario.Ts);
window_samples = round(double(scenario.Tcycle) / Ts);
start_index = round(double(scenario.transient_cycles) * ...
  double(scenario.Tcycle) / Ts) + 1;
if start_index > sample_count || window_samples < 2
  error("experiment:workflow:invalidExp01AnalysisWindow", ...
    "The transient and cycle settings leave no analyzable data.");
end
analysis_input = input(start_index:end);
load_velocity = loadvel(start_index:end);
motor_velocity = motorvel(start_index:end);
window = rectwin(window_samples);
fs = 1 / Ts;

[load_velocity_frf, load_velocity_frequency_hz] = tfestimate( ...
  analysis_input, load_velocity, window, 0, window_samples, fs);
[motor_velocity_frf, motor_velocity_frequency_hz] = tfestimate( ...
  analysis_input, motor_velocity, window, 0, window_samples, fs);
if ~isequal(load_velocity_frequency_hz, motor_velocity_frequency_hz)
  error("experiment:workflow:exp01FrequencyMismatch", ...
    "Load- and motor-side velocity FRF frequency grids differ.");
end
frequency_hz = load_velocity_frequency_hz;
load_coherence = mscohere( ...
  analysis_input, load_velocity, window, 0, window_samples, fs);
motor_coherence = mscohere( ...
  analysis_input, motor_velocity, window, 0, window_samples, fs);

Pd_vel_load = frd(load_velocity_frf, frequency_hz, "FrequencyUnit", "Hz");
Pd_vel_load.Ts = Ts;
Pd_vel_motor = frd(motor_velocity_frf, frequency_hz, "FrequencyUnit", "Hz");
Pd_vel_motor.Ts = Ts;
s = tf("s");
z = tf("z", Ts);
% The runtime plant and logger use theta(k)=theta(k-1)+Ts*omega(k).
% This backward-Euler identity is exact for the deployed semi-implicit
% update and avoids a continuous/Tustin approximation of the position FRF.
position_integrator = Ts*z/(z-1);
Pd_load = Pd_vel_load * position_integrator;
Pd_motor = Pd_vel_motor * position_integrator;
Jn = double(scenario.nominal.Jn);
Dn = double(scenario.nominal.Dn);
Ndelay = double(scenario.nominal.Ndelay);
Pdn = c2d(1 / (Jn * s + Dn) / s, Ts, "zoh") / z^Ndelay;
Pd = Pd_load;

signals = struct( ...
  "time_s", (0:sample_count - 1)' * Ts, ...
  "input", input, "load_position", loadpos, ...
  "motor_position", motorpos, ...
  "control_input", control_input, ...
  "analysis_input", analysis_input, ...
  "load_velocity", load_velocity, ...
  "motor_velocity", motor_velocity);
band = frequency_hz >= 1 & frequency_hz <= 500;
metrics = struct( ...
  "sample_count", sample_count, ...
  "nonzero_motion", max(abs(loadpos)) > 0 && max(abs(motorpos)) > 0, ...
  "max_abs_input_A", max(abs(input)), ...
  "frequency_hz", frequency_hz(:), ...
  "load_coherence", load_coherence(:), ...
  "motor_coherence", motor_coherence(:), ...
  "minimum_load_coherence_1_500_hz", min(load_coherence(band)), ...
  "minimum_motor_coherence_1_500_hz", min(motor_coherence(band)));
plant = struct( ...
  "Pd", Pd, "Pd_motor", Pd_motor, "Pd_load", Pd_load, ...
  "Pd_vel_load", Pd_vel_load, "Pd_vel_motor", Pd_vel_motor, ...
  "Pdn", Pdn, "Jn", Jn, "Dn", Dn, "Ndelay", Ndelay, "Ts", Ts);

artifacts = struct("saved", false, "chirp_result", "", "plant", "", ...
  "runner", string(scenario.paths.runner));
if scenario.save_results
  Tend = double(scenario.Tend);
  Tcycle = double(scenario.Tcycle);
  save(scenario.paths.chirp_result, ...
    "input", "loadpos", "motorpos", "Ts", "Tend", "Tcycle");
  save(scenario.paths.plant, ...
    "Pd", "Pd_motor", "Pd_load", "Pd_vel_load", "Pd_vel_motor", ...
    "Pdn", "Jn", "Dn", "Ndelay", "Ts");
  artifacts.saved = true;
  artifacts.chirp_result = string(scenario.paths.chirp_result);
  artifacts.plant = string(scenario.paths.plant);
end

result = struct( ...
  "scenario", scenario, "run", collected.run, "logger", logger_bin, ...
  "signals", signals, "metrics", metrics, "artifacts", artifacts, ...
  "plant", plant, "startup_timing", collected.startup_timing);
end

function validate_scenario(scenario, expected_name)
if ~isstruct(scenario) || ~isfield(scenario, "name") || ...
    string(scenario.name) ~= expected_name
  error("experiment:workflow:invalidScenario", ...
    "Expected an %s scenario.", expected_name);
end
end

function ensure_result_directory(scenario)
if scenario.save_results && ~isfolder(scenario.paths.result_dir)
  mkdir(scenario.paths.result_dir);
end
end

function raw = require_raw_signals(logger_bin, names)
if ~isstruct(logger_bin) || ~isfield(logger_bin, "raw") || ...
    ~isstruct(logger_bin.raw)
  error("experiment:workflow:invalidLogger", "logger_bin.raw is required.");
end
raw = logger_bin.raw;
missing = names(~isfield(raw, names));
if ~isempty(missing)
  error("experiment:workflow:invalidLogger", ...
    "Logger is missing signal(s): %s.", strjoin(missing, ", "));
end
end
