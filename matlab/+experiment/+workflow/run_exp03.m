function result = run_exp03(scenario, varargin)
% run_exp03  Execute the feedforward scenario and persist its result.

p = inputParser;
p.addParameter("collector", @experiment.exp0n.run_and_collect, ...
  @(x) isa(x, "function_handle"));
p.parse(varargin{:});
validate_scenario(scenario, "exp03");
ensure_result_directory(scenario);

collected = p.Results.collector(scenario.cfg);
experiment.exp0n.assert_run_contract(collected.run);
[signals, metrics] = experiment.exp02.signals_from_logger_bin( ...
  collected.logger_bin, ...
  "expected_sample_count", scenario.expected_sample_count);
repeat_count = double(scenario.cfg.repeat_count);
reference = repmat(double(scenario.trajectory.p(:)), repeat_count, 1);
feedforward = repmat(double(scenario.feedforward(:)), repeat_count, 1);
metrics = add_tracking_metrics(metrics, signals, feedforward);

artifacts = struct("saved", false, "result", "", ...
  "runner", string(scenario.paths.runner));
if scenario.save_results
  t = signals.time_s;
  r = reference;
  y = signals.position_act;
  e = signals.error;
  u = signals.control_input;
  f = feedforward;
  Kd = scenario.Kd;
  feedforward_metrics = metrics;
  stability = scenario.stability;
  feedforward_gains = scenario.feedforward_gains;
  save(scenario.paths.result, ...
    "t", "r", "y", "e", "u", "f", "Kd", ...
    "feedforward_metrics", "stability", "feedforward_gains");
  artifacts.saved = true;
  artifacts.result = string(scenario.paths.result);
end

signals.reference = reference;
signals.feedforward = feedforward;
result = struct( ...
  "scenario", scenario, "run", collected.run, ...
  "logger", collected.logger_bin, "signals", signals, ...
  "metrics", metrics, "artifacts", artifacts, ...
  "startup_timing", collected.startup_timing);
end

function metrics = add_tracking_metrics(metrics, signals, feedforward)
metrics.tracking_error_rms = rms(signals.error);
metrics.tracking_error_peak = max(abs(signals.error));
metrics.final_error = signals.error(end);
metrics.integral_absolute_error = trapz(signals.time_s, abs(signals.error));
metrics.max_abs_feedforward = max(abs(feedforward));
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
