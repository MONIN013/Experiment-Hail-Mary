function out = exp02(plant_data, trajectory, varargin)
% exp02  Pure configuration for the feedback experiment.
validate_plant(plant_data);
validate_trajectory(trajectory, ["t", "p"]);
p = inputParser;
p.addParameter("cfg", experiment.ExperimentConfig.defaults(), @(x) isa(x, "experiment.ExperimentConfig"));
p.addParameter("omega", 15, @is_positive_scalar);
p.addParameter("Smax", 2, @is_positive_scalar);
p.addParameter("Kd", [], @(x) isempty(x) || isa(x, "lti"));
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
controller = experiment.controller.from_discrete_tf(Kd);
stability = experiment.exp02.stability_check( ...
  plant_data.Pd, plant_data.Pdn, Kd, double(o.Smax), "Plot", false);

reference = double(trajectory.p(:));
result_dir = string(o.result_dir);
paths = struct( ...
  "result_dir", result_dir, ...
  "result", fullfile(result_dir, "feedback_result.mat"), ...
  "runner", fullfile(result_dir, "exp02_runner.mat"));
save_path = "";
if logical(o.save_results), save_path = paths.runner; end
cfg = experiment.scenario.configure_run( ...
  o.cfg, reference, zeros(size(reference)), zeros(size(reference)), controller, ...
  "repeat_count", o.repeat_count, "hold_margin_s", o.hold_margin_s, ...
  "save_path", save_path);

out = struct( ...
  "name", "exp02", "cfg", cfg, "plant", plant_data, ...
  "trajectory", trajectory, "Kd", Kd, "controller", controller, ...
  "stability", stability, "Smax", double(o.Smax), ...
  "save_results", logical(o.save_results), ...
  "expected_sample_count", numel(reference) * double(o.repeat_count), ...
  "paths", paths);
end

function validate_plant(s)
required = ["Pd", "Pdn", "Jn", "Dn", "Ts"];
if ~isstruct(s) || any(~isfield(s, required))
  error("experiment:scenario:invalidPlant", "plant_data is missing required fields.");
end
end
function validate_trajectory(s, required)
if ~isstruct(s) || any(~isfield(s, required))
  error("experiment:scenario:invalidTrajectory", "trajectory is missing required fields.");
end
end
function tf = is_positive_scalar(x), tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0; end
function tf = is_nonnegative_scalar(x), tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0; end
function tf = is_positive_integer(x), tf = is_positive_scalar(x) && fix(x) == x; end
function tf = is_logical_scalar(x), tf = islogical(x) && isscalar(x); end
function tf = is_text_scalar(x), tf = ischar(x) || (isstring(x) && isscalar(x)); end
