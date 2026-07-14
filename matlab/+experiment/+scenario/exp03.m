function out = exp03(plant_data, trajectory, varargin)
% exp03  Pure configuration for the feedforward experiment.
required_plant = ["Pd", "Pdn", "Jn", "Dn", "Ndelay", "Ts"];
required_trajectory = ["t", "p", "v", "a"];
if ~isstruct(plant_data) || any(~isfield(plant_data, required_plant))
  error("experiment:scenario:invalidPlant", "plant_data is missing required fields.");
end
if ~isstruct(trajectory) || any(~isfield(trajectory, required_trajectory))
  error("experiment:scenario:invalidTrajectory", "trajectory is missing required fields.");
end
p = inputParser;
p.addParameter("cfg", experiment.ExperimentConfig.defaults(), @(x) isa(x, "experiment.ExperimentConfig"));
p.addParameter("omega", 15, @is_positive_scalar);
p.addParameter("Smax", 2, @is_positive_scalar);
p.addParameter("Kd", [], @(x) isempty(x) || isa(x, "lti"));
p.addParameter("Kfa", [], @(x) isempty(x) || is_finite_scalar(x));
p.addParameter("Kfv", [], @(x) isempty(x) || is_finite_scalar(x));
p.addParameter("Kfc", [], @(x) isempty(x) || is_finite_scalar(x));
p.addParameter("repeat_count", 1, @is_positive_integer);
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
Kfa = value_or_default(o.Kfa, double(plant_data.Jn));
Kfv = value_or_default(o.Kfv, double(plant_data.Dn));
Kfc = value_or_default(o.Kfc, 0);
reference = double(trajectory.p(:));
velocity = double(trajectory.v(:));
acceleration = double(trajectory.a(:));
feedforward = Kfa * acceleration + Kfv * velocity + Kfc * sign(velocity);
delay_n = double(plant_data.Ndelay);
if delay_n > 0
  if delay_n >= numel(feedforward)
    error("experiment:scenario:invalidFeedforwardDelay", ...
      "Ndelay must be smaller than the trajectory length.");
  end
  feedforward = [feedforward(1 + delay_n:end); repmat(feedforward(end), delay_n, 1)];
end

controller = experiment.controller.from_discrete_tf(Kd);
stability = experiment.exp02.stability_check( ...
  plant_data.Pd, plant_data.Pdn, Kd, double(o.Smax), "Plot", false);
result_dir = string(o.result_dir);
paths = struct( ...
  "result_dir", result_dir, ...
  "result", fullfile(result_dir, "feedforward_result.mat"), ...
  "runner", fullfile(result_dir, "exp03_runner.mat"));
save_path = "";
if logical(o.save_results), save_path = paths.runner; end
cfg = experiment.scenario.configure_run( ...
  o.cfg, reference, feedforward, zeros(size(reference)), controller, ...
  "repeat_count", o.repeat_count, "hold_margin_s", o.hold_margin_s, ...
  "save_path", save_path);

out = struct( ...
  "name", "exp03", "cfg", cfg, "plant", plant_data, ...
  "trajectory", trajectory, "Kd", Kd, "controller", controller, ...
  "stability", stability, "Smax", double(o.Smax), ...
  "feedforward", feedforward, ...
  "feedforward_gains", struct("Kfa", Kfa, "Kfv", Kfv, "Kfc", Kfc), ...
  "save_results", logical(o.save_results), ...
  "expected_sample_count", numel(reference) * double(o.repeat_count), ...
  "paths", paths);
end

function value = value_or_default(value, fallback)
if isempty(value), value = fallback; else, value = double(value); end
end
function tf = is_positive_scalar(x), tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0; end
function tf = is_nonnegative_scalar(x), tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0; end
function tf = is_finite_scalar(x), tf = isnumeric(x) && isscalar(x) && isfinite(x); end
function tf = is_positive_integer(x), tf = is_positive_scalar(x) && fix(x) == x; end
function tf = is_logical_scalar(x), tf = islogical(x) && isscalar(x); end
function tf = is_text_scalar(x), tf = ischar(x) || (isstring(x) && isscalar(x)); end
