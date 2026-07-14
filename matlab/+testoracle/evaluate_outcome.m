function report = evaluate_outcome(entry_name, actual, gate)
% evaluate_outcome  Evaluate purpose-level results frozen before execution.
entry_name = string(entry_name);
if ~isstruct(actual) || ~isscalar(actual) || ~isstruct(gate)
  error("testoracle:outcome:invalidInput", ...
    "actual and gate must be scalar structs.");
end
failures = strings(0, 1);
switch entry_name
  case "experiment.exp01"
    g = gate.experiment;
    failures = require_equal(actual, g, ["Ts_s", "Jn", "Dn", "delay_samples"], failures);
    failures = require_logical(actual, "nonzero_motion", ...
      g.require_nonzero_motion, failures);
    failures = check_torsional_feature( ...
      actual, g, "torsional feature", failures);
    band = actual.frequency_hz >= g.frequency_band_min_hz & ...
      actual.frequency_hz <= g.frequency_band_max_hz;
    failures = require_any(band, "no 1-500 Hz bins", failures);
    if any(band)
      failures = check_max(min(actual.coherence(band)), g.coherence_min_1_500_hz, ...
        "coherence below 0.95", failures, "minimum");
      failures = check_error_distribution(actual.magnitude_error_db(band), ...
        g.magnitude_error_p95_db, g.magnitude_error_max_db, "magnitude", failures);
      failures = check_error_distribution(actual.phase_error_deg(band), ...
        g.phase_error_p95_deg, g.phase_error_max_deg, "phase", failures);
    end
    failures = require_logical(actual, "artifact_prediction_match", ...
      g.require_artifact_prediction_match, failures);
    failures = require_logical(actual, "above_500_hz_artifact_only", ...
      g.compare_above_500_hz_by_artifact_only, failures);
  case "experiment.exp02"
    g = gate.experiment;
    failures = require_logical(actual, "closed_loop_stable", ...
      g.closed_loop_stable, failures);
    failures = require_max(actual, "sensitivity_peak", g.sensitivity_peak_max, failures);
    failures = require_near(actual, "travel_rad", g.travel_rad, ...
      g.travel_tolerance_rad, failures);
    failures = check_ranges(actual, g.predicted_ranges, failures);
  case "experiment.exp03"
    g = gate.experiment;
    failures = require_max(actual, "feedforward_formula_max_abs_error", ...
      g.feedforward_formula_tolerance, failures);
    failures = require_near(actual, "advance_samples", g.advance_samples, 0, failures);
    if all(isfield(actual, ["error_norm", "exp02_error_norm"]))
      failures = check_max(actual.error_norm / actual.exp02_error_norm, ...
        g.error_norm_ratio_exp02_max, "exp03 error norm ratio", failures, "maximum");
    else
      failures(end + 1, 1) = "missing exp02/exp03 error norms";
    end
    failures = require_max(actual, "max_input_A", g.max_input_A, failures);
  case "experiment.exp04"
    g = gate.experiment;
    failures = require_near(actual, "completed_trials", g.trial_count, 0, failures);
    failures = require_near(actual, "best_trial", g.best_trial, 0, failures);
    if ~isfield(actual, "error_norm") || numel(actual.error_norm) ~= g.trial_count
      failures(end + 1, 1) = "missing ten-trial error norm";
    elseif any(~isfinite(double(actual.error_norm(:))))
      failures(end + 1, 1) = "nonfinite ten-trial error norm";
    else
      monotonic = all(diff(actual.error_norm) < 0);
      if monotonic ~= g.strict_monotonic_error_norm
        failures(end + 1, 1) = "strict monotonic error norm mismatch";
      end
      failures = check_max(actual.error_norm(end), g.final_error_norm_max, ...
        "final error norm", failures, "maximum");
      failures = check_max(actual.error_norm(end) / actual.error_norm(1), ...
        g.final_to_initial_ratio_max, "final/initial error norm", failures, "maximum");
    end
    failures = require_max(actual, "convergence_factor", g.convergence_factor_max, failures);
    failures = require_max(actual, "max_feedforward_A", g.max_feedforward_A, failures);
    failures = require_max(actual, "max_total_input_A", g.max_total_input_A, failures);
    failures = require_max(actual, "max_final_velocity_count", g.final_velocity_count, failures);
    failures = require_max(actual, "max_final_position_delta_count", ...
      g.max_motor_load_position_delta_count, failures);
    failures = require_near(actual, "restart_before_campaign", ...
      g.restart_before_campaign, 0, failures);
    failures = require_near(actual, "restart_between_trials", ...
      g.restart_between_trials, 0, failures);
  case "tools.run_position_command_demo"
    g = gate.experiment;
    failures = require_near(actual, "sample_count", g.sample_count, 0, failures);
    failures = require_logical(actual, "step_direction_motion", ...
      g.require_step_direction_motion, failures);
    if all(isfield(actual, ["tail_mean", "target"]))
      failures = check_max(abs(actual.tail_mean - actual.target), ...
        g.target_tolerance_fraction * abs(actual.target), ...
        "position tail target error", failures, "maximum");
    else
      failures(end + 1, 1) = "missing target tail metrics";
    end
    failures = require_max(actual, "tail_velocity_abs_rad_s", ...
      g.tail_velocity_abs_max_rad_s, failures);
    failures = check_ranges(actual, g.predicted_ranges, failures);
  case "tools.run_si_demo"
    g = gate.experiment;
    failures = require_near(actual, "sample_count", g.sample_count, 0, failures);
    failures = check_torsional_feature( ...
      actual, g, "SI torsional feature", failures);
    if isfield(actual, "same_phase_cycle_drift_max_rad") && ...
        isnumeric(actual.same_phase_cycle_drift_max_rad) && ...
        isscalar(actual.same_phase_cycle_drift_max_rad) && ...
        isfinite(actual.same_phase_cycle_drift_max_rad)
      drift_ok = actual.same_phase_cycle_drift_max_rad <= ...
        g.same_phase_cycle_drift_max_rad;
      if logical(drift_ok) ~= g.require_no_drift
        failures(end + 1, 1) = "logical mismatch: no_drift";
      end
    else
      failures(end + 1, 1) = ...
        "missing metric: same_phase_cycle_drift_max_rad";
    end
    failures = require_logical(actual, "no_saturation", ...
      g.require_no_saturation, failures);
    valid = actual.frequency_hz >= max(g.f0_hz, 1/g.cycle_s) & ...
      actual.frequency_hz <= g.nyquist_fraction_max*actual.nyquist_hz & ...
      actual.input_psd_db >= max(actual.input_psd_db) + ...
        g.input_psd_floor_from_peak_db & ...
      actual.coherence >= g.coherence_min;
    failures = require_any(valid, "no valid SI bins", failures);
    if any(valid)
      failures = check_error_distribution(actual.magnitude_error_db(valid), ...
        g.magnitude_error_p95_db, g.magnitude_error_max_db, "SI magnitude", failures);
      failures = check_error_distribution(actual.phase_error_deg(valid), ...
        g.phase_error_p95_deg, g.phase_error_max_deg, "SI phase", failures);
    end
  case "tools.run_controller_benchmark"
    g = gate.experiment;
    failures = require_near(actual, "controller_count", g.controller_count, 0, failures);
    failures = require_string_vector(actual, "controllers", g.controllers, failures);
    failures = require_logical(actual, "all_real_siso", g.require_real_siso, failures);
    failures = require_logical(actual, "all_proper_causal", g.require_proper_causal, failures);
    failures = require_logical(actual, "all_no_explicit_delay", g.require_no_explicit_delay, failures);
    failures = require_logical(actual, "all_closed_loop_stable", g.require_closed_loop_stable, failures);
    failures = require_logical(actual, "all_fault_free", g.require_fault_free, failures);
    failures = require_logical(actual, "all_metric_ranges_match", g.require_metric_ranges_match, failures);
    failures = require_logical(actual, "separated_ranks_match", g.require_separated_ranks_match, failures);
    failures = require_logical(actual, "notch_reduction_confirmed", ...
      g.notch_reduces_200_hz_gain, failures);
    failures = require_logical(actual, "integral_bias_reduction_confirmed", ...
      g.integral_reduces_steady_state_bias, failures);
    failures = require_max(actual, "maximum_sensitivity_peak", g.sensitivity_peak_max, failures);
    failures = require_max(actual, "maximum_input_A", g.max_input_A, failures);
    failures = require_max(actual, "maximum_sos_sections", ...
      gate.common.controller_max_sos_sections, failures);
  otherwise
    failures = require_logical(actual, "pass", gate.tool.expected_pass, failures);
end
report = struct("pass", isempty(failures), "failures", failures);
end

function failures = check_torsional_feature(actual, gate, label, failures)
required = ["feature_hz", "predicted_feature_hz", "fft_bin_hz"];
if ~all(isfield(actual, required))
  failures(end + 1, 1) = "missing " + label + " metrics";
  return;
end
failures = check_max(abs(actual.feature_hz-gate.torsional_mode_hz), ...
  gate.mode_center_tolerance_hz, label + " center", failures, "maximum");
failures = check_max(abs(actual.feature_hz-actual.predicted_feature_hz), ...
  gate.prediction_feature_tolerance_fft_bins*actual.fft_bin_hz, ...
  label + " prediction", failures, "maximum");
end

function failures = require_equal(actual, expected, names, failures)
for name = names(:)'
  tolerance = 16*eps(max(1, abs(double(expected.(char(name))))));
  failures = require_near(actual, name, expected.(char(name)), tolerance, failures);
end
end
function failures = require_logical(actual, name, expected, failures)
if ~isfield(actual, name) || ...
    ~(islogical(actual.(name)) && isscalar(actual.(name))) || ...
    ~(islogical(expected) && isscalar(expected)) || actual.(name) ~= expected
  failures(end + 1, 1) = "logical mismatch: " + name;
end
end
function failures = require_string_vector(actual, name, expected, failures)
if ~isfield(actual, name) || ...
    ~isequal(string(actual.(name)), string(expected))
  failures(end + 1, 1) = "value mismatch: " + name;
end
end
function failures = require_near(actual, name, expected, tolerance, failures)
if ~isfield(actual, name) || ~isnumeric(actual.(name)) || ...
    ~isscalar(actual.(name)) || ~isfinite(double(actual.(name))) || ...
    ~isfinite(double(expected)) || ~isfinite(double(tolerance)) || ...
    abs(double(actual.(name)) - double(expected)) > tolerance
  failures(end + 1, 1) = "value mismatch: " + name;
end
end
function failures = require_max(actual, name, maximum, failures)
if ~isfield(actual, name)
  failures(end + 1, 1) = "missing metric: " + name;
else
  failures = check_max(actual.(name), maximum, name, failures, "maximum");
end
end
function failures = check_max(value, threshold, label, failures, direction)
if direction == "minimum"
  failed = ~(isscalar(value) && isfinite(value) && value >= threshold);
else
  failed = ~(isscalar(value) && isfinite(value) && value <= threshold);
end
if failed, failures(end + 1, 1) = label + " gate failed"; end
end
function failures = require_any(mask, label, failures)
if ~any(mask), failures(end + 1, 1) = label; end
end
function failures = check_error_distribution(values, p95_limit, max_limit, label, failures)
values = abs(double(values(:)));
if isempty(values) || any(~isfinite(values))
  failures(end + 1, 1) = label + " errors missing/nonfinite";
  return;
end
if percentile(values, 95) > p95_limit
  failures(end + 1, 1) = label + " p95 exceeded";
end
if max(values) > max_limit
  failures(end + 1, 1) = label + " maximum exceeded";
end
end
function value = percentile(values, percent)
values = sort(values);
position = 1 + (numel(values)-1) * percent/100;
lower_index = floor(position); upper_index = ceil(position);
if lower_index == upper_index
  value = values(lower_index);
else
  value = values(lower_index) + (position-lower_index) * ...
    (values(upper_index)-values(lower_index));
end
end
function failures = check_ranges(actual, ranges, failures)
names = string(fieldnames(ranges));
for name = names(:)'
  if ~isfield(actual, name)
    failures(end + 1, 1) = "missing predicted metric: " + name; %#ok<AGROW>
    continue;
  end
  bounds = double(ranges.(char(name)));
  value = actual.(char(name));
  if numel(bounds) ~= 2 || any(~isfinite(bounds)) || ...
      ~(isnumeric(value) && isscalar(value) && isfinite(double(value))) || ...
      double(value) < bounds(1) || double(value) > bounds(2)
    failures(end + 1, 1) = "outside frozen range: " + name; %#ok<AGROW>
  end
end
end
