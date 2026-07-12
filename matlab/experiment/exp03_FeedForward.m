%[text] ## Demo3: Feedforward Control Experiment
%%
%[text] ### STEP 1: DESIGN FEEDBACK CONTROLLER
%[text] load settings for the experiment
omega = 15; % desired pole [rad/s], not [Hz]
Smax = 2; % maximum gain of sensitivity function, 6 dB

% Student-tunable FF gains. [] selects the nominal-model compensation
% Kfa=Jn, Kfv=Dn, Kfc=0 after plant.mat is loaded.
Kfa = [];
Kfv = [];
Kfc = [];

repeat_count = 1;
hold_margin_s = 1.0;
save_results = true;
use_virtual_motor = true; % false on the RealMotor project; skips all VM parameter writes

script_dir = string(fileparts(mfilename("fullpath")));
result_dir = fullfile(script_dir, "data");
plant_mat_path = fullfile(result_dir, "plant.mat");
feedforward_result_path = fullfile(result_dir, "feedforward_result.mat");
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
Ndelay = plant_data.Ndelay;
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
  "error_id", "experiment:exp03_feedforward:sensitivityLimitExceeded");
fprintf("Measured sensitivity peak: %.6g (limit %.6g)\n", stability.max_sensitivity, Smax);
%%
%[text] ### STEP 2: FEEDFORWARD EXPERIMENT
%[text] set reference trajectory
trajectory = experiment.exp0n.load_trajectory( ...
  "expected_sample_time_s", Ts, "table_max_n", cfg.env.table_max_n);
t = trajectory.t;
r = trajectory.p;
v = trajectory.v;
a = trajectory.a;
N = numel(r);

figure;
subplot(3, 1, 1);
plot(t, r, "b");
grid off;
xlabel("Time [s]"); ylabel("Position [rad]");
subplot(3, 1, 2);
plot(t, v, "b");
grid off;
xlabel("Time [s]"); ylabel("Velocity [rad/s]");
subplot(3, 1, 3);
plot(t, a, "b");
grid off;
xlabel("Time [s]"); ylabel("Acceleration [rad/s^2]");
%%
%[text] ### **Design Feedforward input**
if isempty(Kfa)
  Kfa = Jn;
end
if isempty(Kfv)
  Kfv = Dn;
end
if isempty(Kfc)
  Kfc = 0;
end

f = Kfa*a + Kfv*v + Kfc*sign(v); % feedforward signal
f = [f(1+Ndelay:end); repmat(f(end), [Ndelay, 1])]; % delay compensation
%%
%[text] build simulink model "twomass\_exp\_**tunable**\_2019a.slx"
%[text] (unlike demo1 and demo2, changing the reference and feedforward signal **does not** require rebuild! however, be aware that using long signal length may crash matlab, e.g., N = 400,000)
%%
%[text] execute experiment via simulink
%[text] \*make sure to close all simulink files before executing this section
per_trial_s = N * Ts;
cfg.ref_profile = r;
cfg.ff_profile = f;
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
cfg.restart_virtual_motor_runtime = false; % lifecycle restart is reserved for test-only prediction oracles
if use_virtual_motor
  cfg.virtual_motor_plant = experiment.exp01.nominal_overlay_plant();
end
if save_results
  cfg.save_path = char(fullfile(result_dir, "exp03_runner.mat"));
end
collect_out = experiment.exp0n.run_and_collect(cfg);
logger_bin = collect_out.logger_bin;
[signals, feedforward_metrics] = experiment.exp02.signals_from_logger_bin( ...
  logger_bin, "expected_sample_count", N * repeat_count);
y = signals.position_act(:);
e = signals.error(:);
u = signals.control_input(:);

expected_log_n = N * repeat_count;
experiment.exp0n.assert_run_contract(collect_out.run);
t = (0:expected_log_n-1)' * Ts;
r = repmat(r, repeat_count, 1);
f = repmat(f, repeat_count, 1);

%%
%[text] save experiment data
if save_results
  if ~isfolder(char(result_dir))
    mkdir(char(result_dir));
  end
  save(char(feedforward_result_path), "t", "r", "y", "e", "u", "f", "Kd");
end
%%
%[text] ### STEP 3: Analyze the results of the experiment
%[text] download data
%%
%[text] plot tracking result of feedforward control
figure;
subplot(3, 1, 1);
plot(t, r, t, y);
xlabel("Time [s]"); ylabel("Position [rad]");
grid on;

subplot(3, 1, 2);
plot(t, e);
xlabel("Time [s]"); ylabel("Tracking error [rad]");
grid on;

subplot(3, 1, 3);
plot(t, f); hold on; plot(t, u - f); hold off;
xlabel("Time [s]"); ylabel("Input [A]");
legend("FF", "FB");
grid on;
%%
%[text] display error norm
fprintf("Tracking error norm: %.6g, max |u|: %.6g A\n", ...
  norm(e), feedforward_metrics.max_abs_control_input);
