function report = compare_readback_freqresp( ...
    config_value, parameter_readback, controller_readback, frozen, varargin)
% compare_readback_freqresp  Rebuild the independent model from ADS readback.
p = inputParser;
p.addParameter("magnitude_tolerance_db", 1e-9, @valid_limit);
p.addParameter("phase_tolerance_deg", 1e-7, @valid_limit);
p.addParameter("feedforward_advance_samples", 0, @valid_nonnegative_integer);
p.parse(varargin{:});
if ~isstruct(parameter_readback) || ~isscalar(parameter_readback) || ...
    ~all(isfield(parameter_readback, ["plant", "taskDtNs"])) || ...
    ~isstruct(controller_readback) || ~isscalar(controller_readback) || ...
    ~isstruct(frozen) || ~isscalar(frozen) || ...
    ~all(isfield(frozen, ["frequency_hz", "frequency_response"]))
  error("testoracle:freqresp:invalidReadbackEvidence", ...
    "Plant/task, controller, and frozen frequency evidence are required.");
end

cfg = experiment.ExperimentConfig.from_struct(config_value);
cfg.controller = controller_from_readback( ...
  controller_readback, cfg.controller.sample_time_s);
actual = testoracle.independent_lsim( ...
  cfg, parameter_readback.plant, "frequency_hz", frozen.frequency_hz);
actual_response = actual.frequency_response;
frozen_response = frozen.frequency_response;
advance = double(p.Results.feedforward_advance_samples);
if advance > 0
  Ts = 1/double(cfg.env.task_rate_hz);
  phase = reshape(exp(1i*2*pi*double(frozen.frequency_hz(:))*Ts*advance), ...
    1, 1, []);
  actual_response(:, 2, :) = actual_response(:, 2, :).*phase;
  frozen_response(:, 2, :) = frozen_response(:, 2, :).*phase;
end
comparison = testoracle.compare_freqresp( ...
  actual_response, frozen_response, ...
  "magnitude_tolerance_db", p.Results.magnitude_tolerance_db, ...
  "phase_tolerance_deg", p.Results.phase_tolerance_deg);
task_dt_expected = uint64(cfg.env.task_dt_ns());
task_dt_actual = uint64(parameter_readback.taskDtNs);
report = comparison;
report.pass = logical(comparison.pass && task_dt_actual == task_dt_expected);
report.task_dt_ns_exact_match = task_dt_actual == task_dt_expected;
report.expected_task_dt_ns = task_dt_expected;
report.actual_task_dt_ns = task_dt_actual;
report.method = "independent freqresp from applied VM/SOS ADS readback";
report.feedforward_advance_samples = advance;
end

function controller = controller_from_readback(readback, sample_time_s)
required = ["coefficients", "section_count"];
if any(~isfield(readback, required))
  error("testoracle:freqresp:invalidControllerReadback", ...
    "Controller readback is missing padded SOS fields.");
end
rows = reshape(double(readback.coefficients), 5, []).';
count = double(readback.section_count);
if count < 0 || count > size(rows, 1) || fix(count) ~= count
  error("testoracle:freqresp:invalidControllerReadback", ...
    "Controller section count is outside the padded SOS payload.");
end
sos = [rows(1:count, 1:3), ones(count, 1), rows(1:count, 4:5)];
controller = experiment.ControllerConfig.from_struct( ...
  struct("sos", sos, "sample_time_s", sample_time_s));
end

function tf = valid_limit(value)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
  isfinite(value) && value >= 0;
end

function tf = valid_nonnegative_integer(value)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
  isfinite(value) && value >= 0 && fix(value) == value;
end
