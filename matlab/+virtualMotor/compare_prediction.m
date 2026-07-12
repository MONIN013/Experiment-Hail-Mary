function metrics = compare_prediction(logger_source, prediction, varargin)
% compare_prediction  Compare an ExperimentLogger payload to a fixed VM oracle.

p = inputParser;
p.addParameter("double_abs_tol", 1e-10, @is_nonnegative_scalar);
p.addParameter("current_command_abs_tol", 1e-5, @is_nonnegative_scalar);
p.addParameter("encoder_quantum_factor", 2.0, @is_positive_scalar);
p.parse(varargin{:});
opts = p.Results;

actual = extract_raw(logger_source);
expected = prediction.raw;
required = string(fieldnames(expected));
missing = required(~isfield(actual, required));
if ~isempty(missing)
  error("virtualMotor:prediction:missingSignal", ...
    "Logger source is missing field(s): %s.", strjoin(missing, ", "));
end

position_tol = double(opts.encoder_quantum_factor) * ...
  max(double(prediction.encoder_quantum_motor_rad), double(prediction.encoder_quantum_load_rad));
velocity_tol = position_tol;
double_tol = double(opts.double_abs_tol);
current_command_tol = max(double_tol, double(opts.current_command_abs_tol));
current_quantum = double(prediction.driver_current_quantum_A);
current_feedback_tol = max(double_tol, current_quantum + 4 * eps(current_quantum));

spec = {
  "ref_value", 0.0
  "ff_value", 0.0
  "dist_value", 0.0
  "control_input", current_command_tol
  "current_cmd", current_command_tol
  "error", position_tol
  "motor_current_act", current_feedback_tol
  "motor_position", position_tol
  "load_position", position_tol
  "motor_velocity", velocity_tol
  "load_velocity", velocity_tol
};

signals = struct();
all_signal_pass = true;
count_match = true;
for k = 1:size(spec, 1)
  name = spec{k, 1};
  tolerance = spec{k, 2};
  actual_values = double(actual.(name)(:));
  expected_values = double(expected.(name)(:));
  same_count = numel(actual_values) == numel(expected_values);
  count_match = count_match && same_count;
  if same_count && ~isempty(expected_values)
    delta = actual_values - expected_values;
    max_abs_error = max(abs(delta));
    rmse = sqrt(mean(delta.^2));
    finite = all(isfinite(actual_values));
    pass = finite && max_abs_error <= tolerance;
  elseif same_count
    max_abs_error = 0.0;
    rmse = 0.0;
    finite = true;
    pass = true;
  else
    max_abs_error = Inf;
    rmse = Inf;
    finite = all(isfinite(actual_values));
    pass = false;
  end
  signals.(name) = struct( ...
    "pass", logical(pass), ...
    "same_count", logical(same_count), ...
    "finite", logical(finite), ...
    "tolerance", double(tolerance), ...
    "max_abs_error", double(max_abs_error), ...
    "rmse", double(rmse));
  all_signal_pass = all_signal_pass && pass;
end

actual_seq = uint32(actual.seq(:));
expected_seq = uint32(expected.seq(:));
seq_match = isequal(actual_seq, expected_seq);
actual_t_ns = uint64(actual.t_ns(:));
expected_t_ns = uint64(expected.t_ns(:));
timestamp_match = isequal(actual_t_ns, expected_t_ns);

metrics = struct( ...
  "pass", logical(count_match && seq_match && timestamp_match && ...
    all_signal_pass && ~prediction.fault.motor && ~prediction.fault.load && ...
    ~prediction.position_saturated), ...
  "sample_count_match", logical(count_match), ...
  "seq_exact_match", logical(seq_match), ...
  "timestamp_exact_match", logical(timestamp_match), ...
  "predicted_fault_free", logical(~prediction.fault.motor && ~prediction.fault.load), ...
  "predicted_position_unsaturated", logical(~prediction.position_saturated), ...
  "position_tolerance_rad", position_tol, ...
  "velocity_tolerance_rad_s", velocity_tol, ...
  "signals", signals);
end

function raw = extract_raw(value)
if ~isstruct(value)
  error("virtualMotor:prediction:invalidLogger", "Logger source must be a struct.");
end
if isfield(value, "raw") && isstruct(value.raw)
  raw = value.raw;
else
  raw = value;
end
end

function tf = is_nonnegative_scalar(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && double(value) >= 0;
end

function tf = is_positive_scalar(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && double(value) > 0;
end
