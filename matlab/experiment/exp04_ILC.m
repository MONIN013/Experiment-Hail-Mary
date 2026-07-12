%[text] ## Demo4: Iterative Learning Control Experiment
%%
%[text] ### STEP 1: DESIGN FEEDBACK CONTROLLER
%[text] load settings for the experiment
clear; close all;

omega = 15; % desired pole [rad/s], not [Hz]
Smax = 2; % maximum gain of sensitivity function, 6 dB
use_virtual_motor = true; % false on the RealMotor project; skips all VM parameter writes

script_dir = string(fileparts(mfilename("fullpath")));
result_dir = fullfile(script_dir, "data");
plant_mat_path = fullfile(result_dir, "plant.mat");
cfg = experiment.ExperimentConfig.defaults();
plant_data = experiment.exp0n.load_plant_data( ...
  plant_mat_path, "expected_sample_time_s", 1 / cfg.env.task_rate_hz);
if use_virtual_motor
  experiment.exp01.assert_plant_provenance( ...
    plant_data, experiment.exp01.nominal_overlay_plant());
end
Pd = plant_data.Pd;
Pdn = plant_data.Pdn;
Jn = plant_data.Jn;
Dn = plant_data.Dn;
Ts = plant_data.Ts;
%%
%[text] design FB controller
%[text] (hint: during tuning of FF input the designed FB controller in demo2 may not be optimal)
Kpid = experiment.exp02.designpid(Dn/Jn, 0, 1/Jn, omega);
Kd = c2d(Kpid, Ts, "tustin"); % digital feedback controller
% load(fullfile(result_dir, "feedback_result.mat"), "Kd"); % uncomment to use FB controller designed at demo2

controller_cfg = experiment.controller.from_discrete_tf(Kd);
%%
%[text] ### Check the stability and performance of FB Controller (Always check before experiment!!!)
%[text] use nyquist and sensitivity plot
%[text] (note: Pd is actual system, Pdn is modelled system)
stability = experiment.exp02.stability_check( ...
  Pd, Pdn, Kd, Smax, ...
  "error_id", "experiment:exp04_ilc:sensitivityLimitExceeded");
fprintf("Measured sensitivity peak: %.6g (limit %.6g)\n", stability.max_sensitivity, Smax);
%%
%[text] ### STEP 2: ILC EXPERIMENT
%[text] configure ILC operation conditions
Ntrial = 10; % number of learning trials [int]
alpha = 0.6; % Temp reference learning gain (0<a<=1)
q_cutoff_hz = 120; % below the 200 Hz VM torsional mode; short enough for the 25 ms splice
noQ = false; % option of not using the robustness (Q) filter
maxInput = 1.6; % maximum control input [A]
Npad = 100; % padding samples used by srinv/filtfilt_clean
transient_samples = 200; % 25 ms transient splice length at 8 kHz

repeat_count = 1;
hold_margin_s = 1.0;
save_results = true;
%%
%[text] ### Design Learning filter and Robustness (Q) filter of ILC
%[text] **\*\*\*LEARNING WILL DIVERGE IF |Q|^2|1-JL| \> 1 FOR ANY FREQUENCY\*\*\***
%[text] (hint: typically Q filter is designed as a low-pass filter)
learning_filters = experiment.exp04.design_learning_filters( ...
  Pd, Pdn, Kd, Ts, alpha, q_cutoff_hz, noQ);
fprintf("ILC convergence peak: %.6g (must be < 1)\n", ...
  learning_filters.max_convergence_gain);

figure;
bop = bodeoptions("cstprefs");
bop.FreqUnits = "Hz";
bop.XLimMode = "manual";
bop.XLim = {[1, 1/2/Ts]};
bop.Grid = "off";
bodemag(learning_filters.convergence_condition, bop); hold on;
plot([1, 1/2/Ts], [0, 0], "Color", "black", "LineStyle", "--"); hold off;
title("Convergence condition of ILC");
%%
%[text] initialize storage variables
trajectory = experiment.exp0n.load_trajectory( ...
  "expected_sample_time_s", Ts, "table_max_n", cfg.env.table_max_n);
t = trajectory.t;
r = trajectory.p;
N = numel(r);

figure;
plot(t, r, "b");
grid off;
xlabel("Time [s]"); ylabel("Position [rad]");

history.t = t;
history.r = repmat(r, [1, Ntrial]);
history.y = zeros(N, Ntrial);
history.e = zeros(N, Ntrial);
history.eNorm = zeros(1, Ntrial);
history.f = zeros(N, Ntrial);
history.u = zeros(N, Ntrial);
history.maxAbsInput = zeros(1, Ntrial);
history.errorIncreased = false(1, Ntrial);
history.convergencePeak = repmat(learning_filters.max_convergence_gain, 1, Ntrial);
history.maxSensitivity = stability.max_sensitivity;
history.sensitivityLimitExceeded = stability.limit_exceeded;

%%
%[text] build simulink model "twomass\_exp\_**tunable**\_2019a.slx" after executing this section
%[text] (unlike demo1 and demo2, changing the reference and feedforward signal **does not** require rebuild! however, be aware that using long signal length may crash matlab, e.g., N = 400,000)
per_trial_s = N * Ts;
if use_virtual_motor
  vm_plant = experiment.exp01.nominal_overlay_plant();
end
cfg.repeat_count = repeat_count;
cfg.controller = controller_cfg;
cfg.write_virtual_motor_params = use_virtual_motor;
cfg.restart_virtual_motor_runtime = false; % lifecycle restart is reserved for test-only prediction oracles
if use_virtual_motor
  cfg.virtual_motor_plant = vm_plant;
end
completed_trials = 0;
history.stopReason = "completed";
if save_results
  run_stamp = char(datetime("now", "Format", "yyyyMMdd_HHmmss_SSS"));
  trial_result_dir = fullfile(result_dir, "exp04_runs", run_stamp);
  mkdir(char(trial_result_dir));
  ilc_result_path = fullfile(trial_result_dir, "ilc_result.mat");
end

%%
%[text] execute experiment via simulink
%[text] \*make sure to close all simulink files before executing this section
for j = 1:Ntrial
  cfg.ref_profile = r;
  cfg.ff_profile = history.f(:, j);
  cfg.dist_profile = zeros(N, 1);
  cfg.repeat_count = repeat_count;
  cfg.wait_for_done = true;
  cfg.hold_seconds = per_trial_s + hold_margin_s;
  cfg.done_timeout_s = repeat_count * per_trial_s + hold_margin_s + 5.0;
  cfg.logger_release_timeout_s = max(5.0, repeat_count * per_trial_s / 10);
  cfg.controller = controller_cfg;
  cfg.host_heartbeat_enable = false;
  cfg.external_host_heartbeat_enable = true;
  cfg.write_virtual_motor_params = use_virtual_motor;
  if use_virtual_motor
    cfg.virtual_motor_plant = vm_plant;
  end
  if save_results
    cfg.save_path = char(fullfile(trial_result_dir, sprintf("trial%02d.mat", j)));
  end
  collect_out = experiment.exp0n.run_and_collect(cfg);
  logger_bin = collect_out.logger_bin;
  [signals, feedback_metrics] = experiment.exp02.signals_from_logger_bin( ...
    logger_bin, "expected_sample_count", N);
  experiment.exp0n.assert_run_contract(collect_out.run);

  history.y(:, j) = signals.position_act;
  history.e(:, j) = signals.error;
  history.eNorm(j) = norm(history.e(:, j));
  history.u(:, j) = signals.control_input;
  history.maxAbsInput(j) = max(abs(signals.control_input));
  completed_trials = j;

  error_increased = j > 1 && experiment.exp04.error_norm_increased( ...
    history.eNorm(j - 1), history.eNorm(j));
  history.errorIncreased(j) = error_increased;
  if error_increased
    warning("experiment:exp04_ilc:errorNormIncreased", ...
      "Trial %d error norm increased from %.6g to %.6g; continuing the configured %d-trial campaign.", ...
      j, history.eNorm(j - 1), history.eNorm(j), Ntrial);
  end

  if j < Ntrial
    [f_jplus1, update_status] = experiment.exp04.learning_update( ...
      history.f(:, j), history.e(:, j), learning_filters, ...
      "alpha", alpha, "Npad", Npad, ...
      "transient_samples", transient_samples, "max_input", maxInput);
    if ~update_status.ok
      history.stopReason = "input_limit";
      error("experiment:exp04_ilc:inputLimitExceeded", ...
        "Next trial feedforward %.6g A exceeds maxInput=%.6g A.", ...
        update_status.max_abs_input, update_status.limit);
    end
    history.f(:, j + 1) = f_jplus1;
  end
  fprintf("trial=%d/%d norm(error)=%.6g maxAbsError=%.6g maxAbsControlInput=%.6g A " + ...
    "convergencePeak=%.6g errorIncreased=%d\n", ...
    j, Ntrial, history.eNorm(j), feedback_metrics.max_abs_error, ...
    history.maxAbsInput(j), history.convergencePeak(j), history.errorIncreased(j));
end
history.completedTrials = completed_trials;
history.r = history.r(:, 1:completed_trials);
history.y = history.y(:, 1:completed_trials);
history.e = history.e(:, 1:completed_trials);
history.eNorm = history.eNorm(1:completed_trials);
history.f = history.f(:, 1:completed_trials);
history.u = history.u(:, 1:completed_trials);
history.maxAbsInput = history.maxAbsInput(1:completed_trials);
history.errorIncreased = history.errorIncreased(1:completed_trials);
history.convergencePeak = history.convergencePeak(1:completed_trials);
[history.bestErrorNorm, history.bestTrial] = min(history.eNorm);
history.trialSummary = table( ...
  (1:completed_trials)', history.eNorm(:), history.maxAbsInput(:), ...
  history.errorIncreased(:), history.convergencePeak(:), ...
  history.convergencePeak(:) < 1, ...
  VariableNames=["trial", "errorNorm", "maxAbsInputA", ...
    "errorIncreased", "convergencePeak", "convergenceSatisfied"]);
disp(history.trialSummary);
%%
%[text] save experiment data
if save_results
  if ~isfolder(char(result_dir))
    mkdir(char(result_dir));
  end
  save(char(ilc_result_path), "t", "history", "Kd", "stability", "learning_filters");
end
%%
%[text] ### STEP 3: Analyze the results of the experiment
%[text] download data
%%
%[text] plot tracking result of ILC
j = history.bestTrial; % choose the best completed iteration

figure;
subplot(3, 1, 1);
plot(t, history.r(:, j), t, history.y(:, j));
xlabel("Time [s]"); ylabel("Position [rad]");
grid on;

subplot(3, 1, 2);
plot(t, history.e(:, j));
xlabel("Time [s]"); ylabel("Tracking error [rad]");
grid on;

subplot(3, 1, 3);
plot(t, history.f(:, j)); hold on; plot(t, history.u(:, j)-history.f(:, j)); hold off;
xlabel("Time [s]"); ylabel("Input [A]");
legend("FF", "FB");
grid on;
sgtitle(string(j) + " th iteration result");
%%
%[text] plot transition of error norm
figure;
semilogy(1:completed_trials, history.eNorm, "-o"); hold on;
grid on;
xlabel("Iteration"); ylabel("$\|e\|_2$", "Interpreter", "latex");
title("Position error");
%%
%[text] smallest 2 norm error in iteration
history.bestErrorNorm
