function cfg = configure_run(cfg, reference, feedforward, disturbance, controller, varargin)
% configure_run  Build the shared ExperimentConfig portion of a pure scenario.

arguments
  cfg experiment.ExperimentConfig
  reference {mustBeNumeric, mustBeReal, mustBeFinite}
  feedforward {mustBeNumeric, mustBeReal, mustBeFinite}
  disturbance {mustBeNumeric, mustBeReal, mustBeFinite}
  controller experiment.ControllerConfig
end
arguments (Repeating)
  varargin
end

p = inputParser;
p.addParameter("repeat_count", 1, @is_positive_integer);
p.addParameter("hold_margin_s", 1.0, @is_nonnegative_scalar);
p.addParameter("save_path", "", @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.parse(varargin{:});

reference = double(reference(:));
feedforward = double(feedforward(:));
disturbance = double(disturbance(:));
if numel(feedforward) ~= numel(reference) || numel(disturbance) ~= numel(reference)
  error("experiment:scenario:waveformLengthMismatch", ...
    "Reference, feedforward, and disturbance lengths must match.");
end

repeat_count = double(p.Results.repeat_count);
per_trial_s = numel(reference) / double(cfg.env.task_rate_hz);
hold_margin_s = double(p.Results.hold_margin_s);
cfg.ref_profile = reference;
cfg.ff_profile = feedforward;
cfg.dist_profile = disturbance;
cfg.repeat_count = repeat_count;
cfg.wait_for_done = true;
cfg.hold_seconds = per_trial_s + hold_margin_s;
cfg.done_timeout_s = repeat_count * per_trial_s + hold_margin_s + 5.0;
cfg.logger_release_timeout_s = max(5.0, repeat_count * per_trial_s / 10);
cfg.controller = controller;
cfg.host_heartbeat_enable = false;
cfg.external_host_heartbeat_enable = true;
cfg.save_path = string(p.Results.save_path);
cfg = cfg.normalize();
cfg.validate();
end

function tf = is_positive_integer(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && ...
  double(value) >= 1 && fix(double(value)) == double(value);
end

function tf = is_nonnegative_scalar(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && double(value) >= 0;
end
