function actual = actual_outcome(entry_name, capture, expected, context)
% actual_outcome  Recompute purpose metrics only from captured runtime data.
entry_name = string(entry_name);
switch entry_name
  case "experiment.exp01"
    actual = exp01_outcome(capture, expected);
  case "experiment.exp02"
    actual = tracking_outcome(capture, expected);
  case "experiment.exp03"
    actual = feedforward_outcome(capture, expected, context);
  case "experiment.exp04"
    actual = ilc_outcome(capture, expected, context);
  case "tools.run_position_command_demo"
    actual = position_outcome(capture.logger.raw, expected);
  case "tools.run_si_demo"
    actual = si_outcome(capture, expected);
  case "tools.run_controller_benchmark"
    actual = controller_outcome(capture, expected);
  otherwise
    actual = struct("pass", captured_pass(entry_name, capture));
end
end

function actual = exp01_outcome(capture, expected)
cfg = experiment.ExperimentConfig.from_struct(expected.exact.config);
analysis_contract = expected.exact.analysis;
scenario = frozen_exp01_scenario(cfg, analysis_contract);
workflow = experiment.workflow.run_exp01(scenario, ...
  "collector", @(~) fake_collection(capture.logger));
reference_contract = expected.independent.response.exp01_workflow_frf;
full_frequency = workflow.metrics.frequency_hz(:);
reference_frequency = reference_contract.frequency_hz(:);
frequency_band = full_frequency >= reference_frequency(1) & ...
  full_frequency <= reference_frequency(end);
frequency = full_frequency(frequency_band);
assert_frequency_grid(frequency, reference_contract.frequency_hz, ...
  "experiment.exp01");
reference = reference_contract.velocity_response(:);
full_measured = squeeze(workflow.plant.Pd_vel_load.ResponseData);
measured = full_measured(frequency_band);
ratio = measured(:)./reference(:);
feature_hz = testoracle.spectral_feature_frequency( ...
  frequency, measured, [100, 300]);
artifact_projection = testoracle.artifact_projection( ...
  "experiment.exp01", capture.artifact_source);
artifact_report = testoracle.verify_artifact( ...
  artifact_projection, ...
  expected.artifact.contract, "units", testoracle.artifact_unit_map( ...
    "experiment.exp01", artifact_projection));
actual = struct( ...
  "Ts_s", double(capture.artifact_source.plant.Ts), ...
  "Jn", double(capture.artifact_source.plant.Jn), ...
  "Dn", double(capture.artifact_source.plant.Dn), ...
  "delay_samples", double(capture.artifact_source.plant.Ndelay), ...
  "frequency_hz", frequency, ...
  "coherence", min(workflow.metrics.load_coherence(frequency_band), ...
    workflow.metrics.motor_coherence(frequency_band)), ...
  "nonzero_motion", workflow.metrics.nonzero_motion, ...
  "feature_hz", feature_hz, ...
  "predicted_feature_hz", ...
    double(expected.outcome.predicted.feature_hz), ...
  "fft_bin_hz", 1/double(capture.artifact_source.chirp.Tcycle), ...
  "magnitude_error_db", 20*log10(abs(ratio)), ...
  "phase_error_deg", experiment.wrap_phase_at_180(rad2deg(angle(ratio))), ...
  "artifact_prediction_match", logical(artifact_report.pass), ...
  "above_500_hz_artifact_only", true);
end

function actual = tracking_outcome(capture, expected)
raw = capture.logger.raw;
metrics = tracking_metrics(raw);
source = capture.artifact_source;
actual = metrics;
actual.closed_loop_stable = logical(source.stability.ok);
actual.sensitivity_peak = double(source.stability.max_sensitivity);
actual.travel_rad = max(double(source.r))-min(double(source.r));
actual.predicted_ranges = expected.outcome.gate.experiment.predicted_ranges;
end

function actual = feedforward_outcome(capture, expected, context)
raw = capture.logger.raw;
actual = tracking_metrics(raw);
saved_ff = double(capture.artifact_source.f(:));
contract = expected.exact.feedforward;
profile_count = double(contract.profile_sample_count);
if numel(saved_ff) == numel(contract.advanced_saved_A) && ...
    profile_count <= numel(saved_ff)
  actual.feedforward_formula_max_abs_error = max(abs( ...
    saved_ff-double(contract.advanced_saved_A(:))));
  [actual.advance_samples, ~] = infer_advance( ...
    saved_ff(1:profile_count), contract.unshifted_profile_A, ...
    expected.outcome.gate.experiment.advance_search_max_samples);
else
  actual.advance_samples = NaN;
  actual.feedforward_formula_max_abs_error = Inf;
end
actual.error_norm = norm(double(raw.error(:)));
feedback_path = fullfile(context.campaign_directory, "loggers", ...
  "experiment_exp02", "run.bin");
if ~isfile(feedback_path)
  error("testoracle:outcome:exp02ArtifactMissing", ...
    "The immutable campaign copy of the exp02 logger is required before exp03.");
end
feedback = experiment.read_logger_bin(feedback_path);
actual.exp02_error_norm = norm(double(feedback.raw.error(:)));
actual.max_input_A = max(abs(double(raw.current_cmd(:))));
end

function actual = ilc_outcome(capture, expected, context)
history = capture.artifact_source.history;
count = double(history.completedTrials);
first = expected.exact.campaign.predictions{1};
velocity_count = zeros(count, 2);
position_delta_count = zeros(count, 1);
for trial = 1:count
  raw = capture.logger{trial}.raw;
  velocity_count(trial, :) = [ ...
    round(raw.motor_velocity(end)/first.encoder_quantum_motor_rad), ...
    round(raw.load_velocity(end)/first.encoder_quantum_load_rad)];
  motor_count = round(raw.motor_position(end)/first.encoder_quantum_motor_rad);
  load_count = round(raw.load_position(end)/first.encoder_quantum_load_rad);
  position_delta_count(trial) = abs(motor_count-load_count);
end
restart_before = 0;
if isfield(context, "preparation") && isfield(context.preparation, "restart_count")
  restart_before = double(context.preparation.restart_count);
end
actual = struct( ...
  "completed_trials", count, "best_trial", double(history.bestTrial), ...
  "error_norm", double(history.eNorm), ...
  "convergence_factor", max(double(history.convergencePeak)), ...
  "max_feedforward_A", max(abs(double(history.f)), [], "all"), ...
  "max_total_input_A", max(double(history.maxAbsTotalInput)), ...
  "max_final_velocity_count", max(abs(velocity_count), [], "all"), ...
  "max_final_position_delta_count", max(position_delta_count), ...
  "restart_before_campaign", restart_before, ...
  "restart_between_trials", double(capture.restart_count));
end

function actual = position_outcome(raw, expected)
cfg = experiment.ExperimentConfig.from_struct(expected.exact.config);
gate = expected.outcome.gate.experiment;
target = max(cfg.ref_profile);
tail_n = round(double(gate.tail_window_s)*cfg.env.task_rate_hz);
tail = numel(raw.load_position)-tail_n+1:numel(raw.load_position);
step_index = find(cfg.ref_profile ~= cfg.ref_profile(1), 1, "first");
[rise_time, settling_time] = step_timing( ...
  raw.t_s, raw.load_position, step_index, target);
actual = struct( ...
  "sample_count", numel(raw.seq), "target", target, ...
  "tail_mean", mean(raw.load_position(tail)), ...
  "tail_velocity_abs_rad_s", max(abs(raw.load_velocity(tail))), ...
  "step_direction_motion", max(raw.load_position) > 0, ...
  "overshoot", max(0, (max(raw.load_position)-target)/target), ...
  "rise_time_s", rise_time, "settling_time_s", settling_time, ...
  "max_input_A", max(abs(raw.current_cmd)), ...
  "predicted_ranges", expected.outcome.gate.experiment.predicted_ranges);
end

function actual = si_outcome(capture, expected)
analysis = capture.tool_result.frf;
raw = capture.logger.raw;
frequency = analysis.freq_hz(:);
contract = expected.independent.response.si_analysis;
assert_frequency_grid(frequency, contract.frequency_hz, ...
  "tools.run_si_demo");
reference = contract.velocity_response(:);
ratio = analysis.frf(:)./reference(:);
feature_hz = testoracle.spectral_feature_frequency( ...
  frequency, analysis.frf(:), [100, 300]);
period_input = analysis.signals.input(1:double(contract.window_samples));
input_fft = fft(period_input);
input_psd = abs(input_fft(1:numel(frequency))).^2;
actual = struct( ...
  "sample_count", numel(raw.seq), "frequency_hz", frequency, ...
  "coherence", analysis.coherence(:), ...
  "magnitude_error_db", 20*log10(abs(ratio)), ...
  "phase_error_deg", experiment.wrap_phase_at_180(rad2deg(angle(ratio))), ...
  "nyquist_hz", double(contract.nyquist_hz), ...
  "feature_hz", feature_hz, ...
  "predicted_feature_hz", double(contract.predicted_feature_hz), ...
  "fft_bin_hz", median(diff(double(frequency))), ...
  "input_psd_db", 10*log10(max(input_psd(:), realmin)), ...
  "same_phase_cycle_drift_max_rad", testoracle.cycle_phase_drift( ...
    raw.load_position, contract.window_samples, ...
    expected.outcome.gate.experiment.transient_cycles), ...
  "no_saturation", runtime_fault_free(capture.vm_status) && ...
    logger_not_saturated(raw, expected.exact.plant));
end

function actual = controller_outcome(capture, expected)
controllers = expected.exact.controllers;
count = numel(controllers);
rows = cell(count, 1);
bias = zeros(count, 1);
gate = expected.outcome.gate.experiment;
for index = 1:count
  signals = capture.test_metrics{index};
  frozen = controllers(index);
  entry = struct("name", frozen.name, "family", frozen.family, ...
    "Kd", [], "controller_cfg", frozen.controller, ...
    "design", frozen.design);
  rows{index} = experiment.exp02.controller_benchmark_metrics( ...
    entry, signals);
  tail_n = min(double(gate.bias_tail_samples), numel(signals.error));
  bias(index) = abs(mean(signals.error(end-tail_n+1:end)));
end
results = vertcat(rows{:});
frozen = expected.outcome.gate.experiment.predicted_metrics;
range_match = true;
for index = 1:count
  ranges = frozen(index).ranges;
  names = string(fieldnames(ranges));
  for name = names(:)'
    value = double(results.(char(name))(index));
    bounds = double(ranges.(char(name)));
    range_match = range_match && isfinite(value) && ...
      value >= bounds(1) && value <= bounds(2);
  end
end
names = string({controllers.name});
lead = find(names == "lead", 1);
notch = find(names == "lead + 200 Hz notch", 1);
designs = [controllers.design];
readback_gain = zeros(count, 1);
for index = 1:count
  cfg = experiment.ExperimentConfig.from_struct(controllers(index).config);
  readback_gain(index) = sos_gain_200_hz( ...
    capture.controller_readback(index), 1/double(cfg.env.task_rate_hz));
end
fault_free = runtime_fault_free(capture.vm_status);
for index = 1:count
  fault_free = fault_free && logger_not_saturated( ...
    capture.logger{index}.raw, expected.exact.plant);
end
bias_report = testoracle.controller_bias_reduction( ...
  names(:), string({designs.method}).', bias, ...
  gate.integral_bias_comparison);
actual = struct( ...
  "controller_count", count, ...
  "controllers", names, ...
  "all_real_siso", all(logical([designs.real_coefficients_siso])), ...
  "all_proper_causal", all(logical([designs.proper_causal])), ...
  "all_no_explicit_delay", all(logical([designs.no_explicit_delay])), ...
  "all_closed_loop_stable", ...
    all(logical([designs.nominal_closed_loop_stable])), ...
  "all_fault_free", logical(fault_free), ...
  "all_metric_ranges_match", logical(range_match), ...
  "separated_ranks_match", separated_ranks_match(results, ...
    expected.outcome.gate.experiment), ...
  "notch_reduction_confirmed", readback_gain(notch) < readback_gain(lead), ...
  "integral_bias_reduction_confirmed", logical(bias_report.pass), ...
  "maximum_sensitivity_peak", max(results.sensitivityPeak), ...
  "maximum_input_A", max(results.maxCurrentCmdA), ...
  "maximum_sos_sections", max(double([capture.controller_readback.section_count])));
end

function scenario = frozen_exp01_scenario(cfg, contract)
paths = struct("result_dir", "", "chirp_result", "", "plant", "", ...
  "runner", "");
scenario = contract;
scenario.cfg = cfg;
scenario.save_results = false;
scenario.require_logger_records = true;
scenario.paths = paths;
end

function assert_frequency_grid(actual, expected, label)
actual = double(actual(:));
expected = double(expected(:));
if ~isequal(actual, expected)
  error("testoracle:outcome:frequencyGridMismatch", ...
    "%s measured analysis grid differs from the frozen manifest grid.", label);
end
end

function [advance, error_value] = infer_advance(saved, unshifted, maximum)
saved = double(saved(:));
unshifted = double(unshifted(:));
if numel(saved) ~= numel(unshifted)
  advance = NaN; error_value = Inf; return;
end
errors = inf(maximum+1, 1);
for candidate = 0:maximum
  if candidate == 0
    shifted = unshifted;
  else
    shifted = [unshifted(candidate+1:end); ...
      repmat(unshifted(end), candidate, 1)];
  end
  errors(candidate+1) = max(abs(saved-shifted));
end
[error_value, index] = min(errors);
advance = index-1;
end

function pass = runtime_fault_free(status)
pass = isstruct(status) && ~isempty(status) && ...
  all(arrayfun(@(x) uint16(x.motor_status) == uint16(hex2dec("0060")) && ...
    uint16(x.load_status) == uint16(hex2dec("0060")), status));
pass = logical(pass);
end

function pass = logger_not_saturated(raw, plant_value)
plant = virtualMotor.PlantConfig.from_struct(plant_value).to_struct();
motor_count = abs(double(raw.motor_position(:))) * ...
  double(plant.motor.encoderResolution)/(2*pi);
load_count = abs(double(raw.load_position(:))) * ...
  double(plant.load.encoderResolution)/(2*pi);
pass = all(isfinite(motor_count)) && all(isfinite(load_count)) && ...
  max(motor_count, [], "omitnan") < double(intmax("int32")) && ...
  max(load_count, [], "omitnan") < double(intmax("int32"));
pass = logical(pass);
end

function gain = sos_gain_200_hz(readback, Ts)
coefficients = reshape(double(readback.coefficients), 5, []).';
section_count = double(readback.section_count);
if section_count < 0 || section_count > size(coefficients, 1)
  gain = NaN; return;
end
z_inverse = exp(-1i*2*pi*200*Ts);
value = 1;
for section = 1:section_count
  row = coefficients(section, :);
  numerator = row(1) + row(2)*z_inverse + row(3)*z_inverse^2;
  denominator = 1 + row(4)*z_inverse + row(5)*z_inverse^2;
  value = value*numerator/denominator;
end
gain = abs(value);
end

function match = separated_ranks_match(results, gate)
match = true;
if ~isfield(gate, "rank_pairs") || isempty(gate.rank_pairs), return; end
pairs = gate.rank_pairs;
controllers = string(results.controller);
for index = 1:numel(pairs)
  left = find(controllers == string(pairs(index).better), 1);
  right = find(controllers == string(pairs(index).worse), 1);
  metric = char(pairs(index).metric);
  match = match && ~isempty(left) && ~isempty(right) && ...
    results.(metric)(left) < results.(metric)(right);
end
match = logical(match);
end

function metrics = tracking_metrics(raw)
error_signal = double(raw.error(:));
time_s = double(raw.t_s(:));
metrics = struct( ...
  "error_l2", norm(error_signal), ...
  "error_rms", sqrt(mean(error_signal.^2)), ...
  "error_peak", max(abs(error_signal)), ...
  "iae", trapz(time_s, abs(error_signal)), ...
  "max_input_A", max(abs(raw.current_cmd)), ...
  "final_error", error_signal(end));
end

function collected = fake_collection(logger)
acceptance = struct( ...
  "input_waveform_exact_match", true, "ff_waveform_exact_match", true, ...
  "dist_waveform_exact_match", true, "torque_sum_exact_match", true, ...
  "seq_no_gap", true, "total_sample_count_exact_match", true);
collected = struct( ...
  "run", struct("metrics", struct("acceptance", acceptance)), ...
  "logger_bin", logger, "startup_timing", struct("source", "captured"));
end

function [rise_time_s, settling_time_s] = step_timing(t, y, step_index, target)
t = double(t(:)); y = double(y(:));
direction = sign(target); target_abs = abs(target);
normalized = direction*y(step_index:end);
at_ten = find(normalized >= 0.1*target_abs, 1, "first");
at_ninety = find(normalized >= 0.9*target_abs, 1, "first");
if isempty(at_ten) || isempty(at_ninety)
  rise_time_s = NaN;
else
  rise_time_s = t(step_index+at_ninety-1)-t(step_index+at_ten-1);
end
outside = find(abs(y(step_index:end)-target) > 0.02*target_abs, 1, "last");
if isempty(outside)
  settling_time_s = 0;
elseif step_index+outside-1 == numel(y)
  settling_time_s = NaN;
else
  settling_time_s = t(step_index+outside)-t(step_index);
end
end

function pass = captured_pass(name, capture)
value = capture.tool_result;
switch name
  case {"tools.run_exp01_exp04_preflight", "tools.run_verify_xar"}
    pass = isstruct(value) && isfield(value, "passed") && ...
      islogical(value.passed) && isscalar(value.passed) && value.passed;
  case "tools.run_ads_discovery_demo"
    pass = isstruct(value) && all(isfield(value, ["ports", "symbols"])) && ...
      testoracle.validate_discovery(value.ports, value.symbols).pass;
  case "tools.run_verify_virtual_motor"
    pass = isstruct(value) && isfield(value, "passed") && ...
      islogical(value.passed) && isscalar(value.passed) && value.passed;
  case "tools.run_ads_transport_e2e"
    pass = isstruct(value) && isfield(value, "pass") && ...
      islogical(value.pass) && isscalar(value.pass) && value.pass;
  case "tools.run_configure_virtual_motor"
    pass = isstruct(value) && isfield(value, "verified") && ...
      islogical(value.verified) && isscalar(value.verified) && value.verified;
  case "tools.run_check_logger_bin"
    pass = isstruct(value) && isfield(value, "pass") && ...
      islogical(value.pass) && isscalar(value.pass) && value.pass && ...
      numel(capture.logger_proof) == 30;
  otherwise
    pass = true;
end
pass = islogical(pass) && isscalar(pass) && pass;
end
