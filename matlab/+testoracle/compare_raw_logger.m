function report = compare_raw_logger(actual_source, prediction, varargin)
% compare_raw_logger  Apply the frozen per-signal VM logger tolerances.
p = inputParser;
p.addParameter("actual_tables", struct(), @isstruct);
p.addParameter("expected_tables", struct(), @isstruct);
p.addParameter("require_table_match", false, @(x) islogical(x) && isscalar(x));
p.addParameter("contract", struct(), @isstruct);
p.parse(varargin{:});

actual = extract_raw(actual_source);
if ~isstruct(prediction) || ~isfield(prediction, "raw")
  error("testoracle:raw:invalidPrediction", "prediction.raw is required.");
end
expected = prediction.raw;
required_meta = ["encoder_quantum_motor_rad", "encoder_quantum_load_rad", ...
  "driver_current_quantum_A"];
if any(~isfield(prediction, required_meta))
  error("testoracle:raw:invalidPrediction", ...
    "Prediction quantization metadata is incomplete.");
end
contract = p.Results.contract;
if isempty(fieldnames(contract))
  contract = default_contract(prediction);
end
contract_fields = ["signals", "signal_count", ...
  "position_velocity_encoder_quanta", ...
  "current_feedback_driver_quanta", "control_current_tolerance_A", ...
  "seq_exact", "timestamp_exact", "table_exact"];
if ~isscalar(contract) || any(~isfield(contract, contract_fields))
  error("testoracle:raw:invalidContract", ...
    "Raw comparison contract is incomplete.");
end
position_quanta = finite_nonnegative( ...
  contract.position_velocity_encoder_quanta, ...
  "position_velocity_encoder_quanta");
current_quanta = finite_nonnegative( ...
  contract.current_feedback_driver_quanta, ...
  "current_feedback_driver_quanta");
control_tolerance = finite_nonnegative( ...
  contract.control_current_tolerance_A, ...
  "control_current_tolerance_A");

spec = {
  "motor_position", position_quanta * double(prediction.encoder_quantum_motor_rad)
  "motor_velocity", position_quanta * double(prediction.encoder_quantum_motor_rad)
  "motor_current_act", current_quanta * double(prediction.driver_current_quantum_A)
  "load_position", position_quanta * double(prediction.encoder_quantum_load_rad)
  "load_velocity", position_quanta * double(prediction.encoder_quantum_load_rad)
  "current_cmd", control_tolerance
  "error", position_quanta * double(prediction.encoder_quantum_load_rad)
  "ref_value", 0
  "ff_value", 0
  "dist_value", 0
  "control_input", control_tolerance
};

missing = string(spec(:, 1));
missing = missing(~isfield(actual, missing) | ~isfield(expected, missing));
if ~isempty(missing)
  error("testoracle:raw:missingSignal", ...
    "Actual or expected logger is missing: %s.", strjoin(missing, ", "));
end
if ~all(isfield(actual, ["seq", "t_ns"])) || ...
    ~all(isfield(expected, ["seq", "t_ns"]))
  error("testoracle:raw:missingSignal", "seq and t_ns are required.");
end

signals = struct();
all_signals_pass = true;
for index = 1:size(spec, 1)
  name = spec{index, 1};
  tolerance = double(spec{index, 2});
  observed = double(actual.(name)(:));
  predicted = double(expected.(name)(:));
  same_shape = isequal(size(actual.(name)), size(expected.(name)));
  if same_shape && ~isempty(observed)
    delta = observed - predicted;
    max_abs_error = max(abs(delta));
    rms_error = sqrt(mean(delta.^2));
    finite = all(isfinite(observed));
    pass = finite && max_abs_error <= tolerance;
  elseif same_shape
    max_abs_error = 0;
    rms_error = 0;
    finite = true;
    pass = true;
  else
    max_abs_error = Inf;
    rms_error = Inf;
    finite = all(isfinite(observed));
    pass = false;
  end
  signals.(name) = struct( ...
    "pass", pass, "same_shape", same_shape, "finite", finite, ...
    "tolerance", tolerance, "max_abs_error", max_abs_error, ...
    "rms_error", rms_error);
  all_signals_pass = all_signals_pass && pass;
end

seq_match = isequal(actual.seq, expected.seq);
timestamp_match = isequal(actual.t_ns, expected.t_ns);
[table_match, table_detail] = compare_tables( ...
  p.Results.actual_tables, p.Results.expected_tables);
if logical(p.Results.require_table_match) && isnan(table_match)
  table_match = false;
  table_detail = "command tables were required but not supplied";
end
table_required = logical_scalar(contract.table_exact, "table_exact");
seq_required = logical_scalar(contract.seq_exact, "seq_exact");
timestamp_required = logical_scalar(contract.timestamp_exact, "timestamp_exact");
table_gate = ~table_required || (~isnan(table_match) && table_match);
seq_gate = ~seq_required || seq_match;
timestamp_gate = ~timestamp_required || timestamp_match;
signals_match = isequal(string(spec(:, 1)), string(contract.signals(:)));
signal_count_match = double(contract.signal_count) == size(spec, 1) && ...
  double(contract.signal_count) == numel(contract.signals);
fault_free = ~isfield(prediction, "fault") || ...
  (~logical(prediction.fault.motor) && ~logical(prediction.fault.load));
unsaturated = ~isfield(prediction, "position_saturated") || ...
  ~logical(prediction.position_saturated);

report = struct( ...
  "pass", all_signals_pass && signals_match && signal_count_match && ...
    seq_gate && timestamp_gate && table_gate && fault_free && unsaturated, ...
  "signal_count", size(spec, 1), ...
  "signal_contract_match", signals_match, ...
  "signal_count_match", signal_count_match, ...
  "signals", signals, ...
  "seq_exact_match", seq_match, ...
  "timestamp_exact_match", timestamp_match, ...
  "table_exact_match", table_match, ...
  "table_detail", table_detail, ...
  "predicted_fault_free", fault_free, ...
  "predicted_position_unsaturated", unsaturated);
end

function contract = default_contract(prediction)
contract = struct( ...
  "signals", ["motor_position", "motor_velocity", "motor_current_act", ...
    "load_position", "load_velocity", "current_cmd", "error", ...
    "ref_value", "ff_value", "dist_value", "control_input"], ...
  "signal_count", 11, "position_velocity_encoder_quanta", 2, ...
  "current_feedback_driver_quanta", 1, ...
  "control_current_tolerance_A", 1e-5, ...
  "seq_exact", true, "timestamp_exact", true, "table_exact", true, ...
  "motor_encoder_quantum_rad", prediction.encoder_quantum_motor_rad, ...
  "load_encoder_quantum_rad", prediction.encoder_quantum_load_rad, ...
  "current_quantum_A", prediction.driver_current_quantum_A);
end

function value = finite_nonnegative(value, name)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0)
  error("testoracle:raw:invalidContract", "%s must be finite and nonnegative.", name);
end
value = double(value);
end

function value = logical_scalar(value, name)
if ~(islogical(value) && isscalar(value))
  error("testoracle:raw:invalidContract", "%s must be scalar logical.", name);
end
end

function raw = extract_raw(value)
if ~isstruct(value)
  error("testoracle:raw:invalidLogger", "Logger source must be a struct.");
end
if isfield(value, "raw"), raw = value.raw; else, raw = value; end
if ~isstruct(raw)
  error("testoracle:raw:invalidLogger", "Logger raw payload must be a struct.");
end
end

function [match, detail] = compare_tables(actual, expected)
if isempty(fieldnames(actual)) && isempty(fieldnames(expected))
  match = NaN;
  detail = "not supplied";
  return;
end
names = ["ref_profile", "ff_profile", "dist_profile"];
if any(~isfield(actual, names)) || any(~isfield(expected, names))
  match = false;
  detail = "ref_profile/ff_profile/dist_profile are required";
  return;
end
match = true;
for name = names
  match = match && isequal(actual.(char(name)), expected.(char(name)));
end
if match, detail = "exact"; else, detail = "value or shape mismatch"; end
end
