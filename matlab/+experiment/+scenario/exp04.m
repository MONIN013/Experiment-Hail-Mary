function out = exp04(plant_data, trajectory, varargin)
% exp04  Pure configuration for the ten-trial ILC experiment.
required_plant = ["Pd", "Pdn", "Jn", "Dn", "Ts"];
if ~isstruct(plant_data) || any(~isfield(plant_data, required_plant))
  error("experiment:scenario:invalidPlant", "plant_data is missing required fields.");
end
if ~isstruct(trajectory) || any(~isfield(trajectory, ["t", "p"]))
  error("experiment:scenario:invalidTrajectory", "trajectory is missing required fields.");
end
p = inputParser;
p.addParameter("cfg", experiment.ExperimentConfig.defaults(), @(x) isa(x, "experiment.ExperimentConfig"));
p.addParameter("omega", 15, @is_positive_scalar);
p.addParameter("Smax", 2, @is_positive_scalar);
p.addParameter("Kd", [], @(x) isempty(x) || isa(x, "lti"));
p.addParameter("trial_count", 10, @is_positive_integer);
p.addParameter("alpha", 0.6, @(x) is_positive_scalar(x) && x <= 1);
p.addParameter("q_cutoff_hz", 120, @is_positive_scalar);
p.addParameter("noQ", false, @is_logical_scalar);
p.addParameter("max_input_A", 1.6, @is_positive_scalar);
p.addParameter("Npad", 100, @is_nonnegative_integer);
p.addParameter("transient_samples", 200, @is_nonnegative_integer);
p.addParameter("learning_error_quantum_rad", 2*pi/8388608, @is_positive_scalar);
p.addParameter("settling_tail_s", 9.0, @is_nonnegative_scalar);
p.addParameter("hold_margin_s", 1.0, @is_nonnegative_scalar);
p.addParameter("save_results", true, @is_logical_scalar);
p.addParameter("result_dir", experiment.scenario.default_result_dir(), @is_text_scalar);
p.parse(varargin{:});
o = p.Results;

Ts = double(plant_data.Ts);
Kd = o.Kd;
if isempty(Kd)
  Kpid = experiment.exp02.designpid( ...
    double(plant_data.Dn) / double(plant_data.Jn), 0, ...
    1 / double(plant_data.Jn), double(o.omega));
  Kd = c2d(Kpid, Ts, "tustin");
end
controller = experiment.controller.from_discrete_tf(Kd);
stability = experiment.exp02.stability_check( ...
  plant_data.Pd, plant_data.Pdn, Kd, double(o.Smax), "Plot", false);
learning_filters = experiment.exp04.design_learning_filters( ...
  plant_data.Pd, plant_data.Pdn, Kd, Ts, double(o.alpha), ...
  double(o.q_cutoff_hz), logical(o.noQ), ...
  double(o.learning_error_quantum_rad));
campaign_trajectory = append_settling_tail( ...
  trajectory, Ts, double(o.settling_tail_s));
reference = double(campaign_trajectory.p(:));
cfg = experiment.scenario.configure_run( ...
  o.cfg, reference, zeros(size(reference)), zeros(size(reference)), controller, ...
  "repeat_count", 1, "hold_margin_s", o.hold_margin_s, "save_path", "");

out = struct( ...
  "name", "exp04", "cfg", cfg, "plant", plant_data, ...
  "trajectory", campaign_trajectory, "Kd", Kd, "controller", controller, ...
  "stability", stability, "learning_filters", learning_filters, ...
  "trial_count", double(o.trial_count), "alpha", double(o.alpha), ...
  "q_cutoff_hz", double(o.q_cutoff_hz), "noQ", logical(o.noQ), ...
  "max_input_A", double(o.max_input_A), "Npad", double(o.Npad), ...
  "transient_samples", double(o.transient_samples), ...
  "learning_error_quantum_rad", double(o.learning_error_quantum_rad), ...
  "settling_tail_s", double(o.settling_tail_s), ...
  "settling_tail_samples", numel(reference) - numel(trajectory.p), ...
  "learning_sample_count", numel(trajectory.p), ...
  "hold_margin_s", double(o.hold_margin_s), ...
  "save_results", logical(o.save_results), ...
  "expected_sample_count", numel(reference), ...
  "result_dir", string(o.result_dir));
end

function trajectory = append_settling_tail(trajectory, Ts, duration_s)
sample_count = numel(trajectory.p);
tail_count = round(duration_s / Ts);
if abs(tail_count * Ts - duration_s) > 16 * eps(max([duration_s, Ts]))
  error("experiment:scenario:invalidSettlingTail", ...
    "settling_tail_s must align exactly to the experiment sample time.");
end
if tail_count == 0
  return;
end

trajectory.t = [double(trajectory.t(:)); ...
  double(trajectory.t(end)) + (1:tail_count)' * Ts];
signal_fields = ["p", "v", "a", "position", "velocity", "acceleration"];
for field_name = signal_fields
  if isfield(trajectory, field_name) && ...
      isvector(trajectory.(field_name)) && ...
      numel(trajectory.(field_name)) == sample_count
    trajectory.(field_name) = [double(trajectory.(field_name)(:)); ...
      zeros(tail_count, 1)];
  end
end
if isfield(trajectory, "sample_count")
  trajectory.sample_count = sample_count + tail_count;
end
end

function tf = is_positive_scalar(x), tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0; end
function tf = is_nonnegative_scalar(x), tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0; end
function tf = is_positive_integer(x), tf = is_positive_scalar(x) && fix(x) == x; end
function tf = is_nonnegative_integer(x), tf = is_nonnegative_scalar(x) && fix(x) == x; end
function tf = is_logical_scalar(x), tf = islogical(x) && isscalar(x); end
function tf = is_text_scalar(x), tf = ischar(x) || (isstring(x) && isscalar(x)); end
