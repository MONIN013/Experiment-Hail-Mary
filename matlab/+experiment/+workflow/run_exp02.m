function result = run_exp02(scenario, varargin)
% run_exp02  Execute the feedback scenario and persist its numeric result.

p = inputParser;
p.addParameter("collector", @experiment.exp0n.run_and_collect, ...
  @(x) isa(x, "function_handle"));
p.parse(varargin{:});
validate_scenario(scenario, "exp02");
ensure_result_directory(scenario);

collected = p.Results.collector(scenario.cfg);
experiment.exp0n.assert_run_contract(collected.run);
[signals, metrics] = experiment.exp02.signals_from_logger_bin( ...
  collected.logger_bin, ...
  "expected_sample_count", scenario.expected_sample_count);
reference = repmat(double(scenario.trajectory.p(:)), ...
  double(scenario.cfg.repeat_count), 1);
metrics = add_tracking_metrics(metrics, signals);

artifacts = struct("saved", false, "result", "", ...
  "runner", string(scenario.paths.runner));
if scenario.save_results
  t = signals.time_s;
  r = reference;
  y = signals.position_act;
  e = signals.error;
  u = signals.control_input;
  Kd = scenario.Kd;
  feedback_metrics = metrics;
  stability = scenario.stability;
  save(scenario.paths.result, ...
    "t", "r", "y", "e", "u", "Kd", "feedback_metrics", "stability");
  artifacts.saved = true;
  artifacts.result = string(scenario.paths.result);
end

result = struct( ...
  "scenario", scenario, "run", collected.run, ...
  "logger", collected.logger_bin, "signals", signals, ...
  "metrics", metrics, "artifacts", artifacts, ...
  "startup_timing", collected.startup_timing);
end

function metrics = add_tracking_metrics(metrics, signals)
metrics.tracking_error_rms = rms(signals.error);
metrics.tracking_error_peak = max(abs(signals.error));
metrics.final_error = signals.error(end);
metrics.integral_absolute_error = trapz(signals.time_s, abs(signals.error));
metrics.max_abs_current_cmd = max(abs(signals.current_cmd));
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
