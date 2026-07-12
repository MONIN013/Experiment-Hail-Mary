function plan = precompute_virtual_motor_plan(cfg, reference, learning_filters, varargin)
% precompute_virtual_motor_plan  Predict the complete VM-only ILC campaign.

arguments
  cfg experiment.ExperimentConfig
  reference {mustBeNumeric, mustBeReal, mustBeFinite}
  learning_filters struct
end
arguments (Repeating)
  varargin
end

p = inputParser;
p.addParameter("trial_count", 10, @is_positive_integer);
p.addParameter("alpha", 0.6, @is_positive_scalar);
p.addParameter("Npad", 100, @is_nonnegative_integer);
p.addParameter("transient_samples", 200, @is_nonnegative_integer);
p.addParameter("max_input", 1.6, @is_positive_scalar);
p.parse(varargin{:});
opts = p.Results;

reference = double(reference(:));
n = numel(reference);
trial_count = double(opts.trial_count);
ff = zeros(n, trial_count);
error_signal = zeros(n, trial_count);
position = zeros(n, trial_count);
control_input = zeros(n, trial_count);
error_norm = zeros(1, trial_count);
max_abs_input = zeros(1, trial_count);
error_increased = false(1, trial_count);
predictions = cell(1, trial_count);
completed_trials = 0;
stop_reason = "completed";

for trial = 1:trial_count
  trial_cfg = cfg;
  trial_cfg.ref_profile = reference;
  trial_cfg.ff_profile = ff(:, trial);
  trial_cfg.dist_profile = zeros(n, 1);
  prediction = virtualMotor.predict_logger(trial_cfg);
  if prediction.fault.motor || prediction.fault.load || prediction.position_saturated
    error("experiment:exp04:unsafeVirtualMotorPrediction", ...
      "Precomputed trial %d reaches a VirtualMotor fault or position saturation.", trial);
  end

  predictions{trial} = prediction;
  error_signal(:, trial) = prediction.raw.error;
  position(:, trial) = prediction.raw.load_position;
  control_input(:, trial) = prediction.raw.control_input;
  error_norm(trial) = norm(error_signal(:, trial));
  max_abs_input(trial) = max(abs(control_input(:, trial)));
  completed_trials = trial;

  if trial > 1
    error_increased(trial) = experiment.exp04.error_norm_increased( ...
      error_norm(trial - 1), error_norm(trial));
  end

  if trial < trial_count
    [next_ff, update_status] = experiment.exp04.learning_update( ...
      ff(:, trial), error_signal(:, trial), learning_filters, ...
      "alpha", opts.alpha, "Npad", opts.Npad, ...
      "transient_samples", opts.transient_samples, ...
      "max_input", opts.max_input);
    if ~update_status.ok
      error("experiment:exp04:inputLimitExceeded", ...
        "Predicted next-trial feedforward %.6g A exceeds max_input=%.6g A.", ...
        update_status.max_abs_input, update_status.limit);
    end
    ff(:, trial + 1) = next_ff;
  end
end

plan = struct( ...
  "completedTrials", completed_trials, ...
  "stopReason", stop_reason, ...
  "f", ff(:, 1:completed_trials), ...
  "e", error_signal(:, 1:completed_trials), ...
  "y", position(:, 1:completed_trials), ...
  "u", control_input(:, 1:completed_trials), ...
  "eNorm", error_norm(1:completed_trials), ...
  "maxAbsInput", max_abs_input(1:completed_trials), ...
  "errorIncreased", error_increased(1:completed_trials), ...
  "predictions", {predictions(1:completed_trials)});
if isfield(learning_filters, "max_convergence_gain")
  plan.maxConvergenceGain = double(learning_filters.max_convergence_gain);
else
  plan.maxConvergenceGain = NaN;
end
[plan.bestErrorNorm, plan.bestTrial] = min(plan.eNorm);
end

function tf = is_positive_integer(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && ...
  double(value) > 0 && fix(double(value)) == double(value);
end

function tf = is_nonnegative_integer(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && ...
  double(value) >= 0 && fix(double(value)) == double(value);
end

function tf = is_positive_scalar(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && double(value) > 0;
end
