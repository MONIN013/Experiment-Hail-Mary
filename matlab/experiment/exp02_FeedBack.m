%[text] ## Demo2: Feedback Control Experiment
%[text] use PI/PD/PID Controller and compare the performance.
%[text] modify the P, I, D gain and (if you have time) add other filters for further analysis and performance enhancement.
%%
%[text] ### STEP 1: DESIGN FEEDBACK CONTROLLER
%[text] load settings for the experiment
clear; close all;

omega = 15; % set by yourself [rad/s] (not [Hz])
Smax = 2; % Maximum gain of sensitivity function (= 6 dB)

save_results = true;
repeat_count = 1;
hold_margin_s = 1.0;
use_virtual_motor = true; % false on the RealMotor project; skips all VM parameter writes

script_dir = string(fileparts(mfilename("fullpath")));
data_dir = fullfile(script_dir, "data");
plant_mat_path = fullfile(data_dir, "plant.mat");
feedback_result_path = fullfile(data_dir, "feedback_result.mat");
cfg = experiment.ExperimentConfig.defaults();

expected_Ts = 1 / cfg.env.task_rate_hz;
plant_data = experiment.exp0n.load_plant_data( ...
  plant_mat_path, "expected_sample_time_s", expected_Ts);
if use_virtual_motor
  experiment.exp01.assert_plant_provenance( ...
    plant_data, experiment.exp01.nominal_overlay_plant());
end

Pd = plant_data.Pd;
Pdn = plant_data.Pdn;
Jn = double(plant_data.Jn);
Dn = double(plant_data.Dn);
Ts = double(plant_data.Ts);

%[text] $K\\;＝\\;k\_p +\\frac{k\_i }{s}+k\_d \\frac{s}{1+T\_f s}${"editStyle":"visual"}
%[text] see what happens when $k\_p${"editStyle":"visual"}, $k\_i${"editStyle":"visual"}, $k\_d${"editStyle":"visual"} is changed.
% Kpi = experiment.exp02.designpi(Dn/Jn, 0, 1/Jn, omega); % uncomment to use PI controller
% Kpd = experiment.exp02.designpd(Dn/Jn, 0, 1/Jn, omega); % uncomment to use PD controller
Kpid = experiment.exp02.designpid(Dn/Jn, 0, 1/Jn, omega); % uncomment to use PID controller
% Kpid.Kp = 0; % set Kp to 0
% Kpid.Ki = 0; % set Ki to 0
% Kpid.Kd = 0; % set Kd to 0
%[text] ### (optional: Design other controllers)
%[text] (hint: change to I-PD, add leadlag filter, add notch filter)
%%
%[text] ### Check the stability and performance of FB Controller (Always check before experiment!!!)
%[text] use nyquist and sensitivity plot
%[text] (note: Pd is actual system, Pdn is modelled system)
Kd = c2d(Kpid, Ts, "tustin"); % digital feedback controller
controller_cfg = experiment.controller.from_discrete_tf(Kd);

stability = experiment.exp02.stability_check( ...
  Pd, Pdn, Kd, Smax, ...
  "error_id", "experiment:exp02_feedback:sensitivityLimitExceeded");
fprintf("Measured sensitivity peak: %.6g (limit %.6g)\n", stability.max_sensitivity, Smax);
%%
%[text] ### STEP 2: FEEDBACK EXPERIMENT
%[text] set reference trajectory
trajectory = experiment.exp0n.load_trajectory( ...
  "expected_sample_time_s", Ts, "table_max_n", cfg.env.table_max_n);
r = trajectory.p;
t = trajectory.t;

figure;
plot(t, r);
grid off;
xlabel("Time [s]"); ylabel("Position [rad]");

%%
%[text] build simulink model "twomass\_exp\_2019a.slx" after executing this section
%[text] (build only needed 1 time. rebuild required if you change the following parameters or the feedback controller Kd.)
sample_n = numel(r);
per_trial_s = sample_n * Ts;

cfg.ref_profile = r;
cfg.ff_profile = zeros(sample_n, 1);
cfg.dist_profile = zeros(sample_n, 1);
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
  if ~isfolder(char(data_dir))
    mkdir(char(data_dir));
  end
  cfg.save_path = char(fullfile(data_dir, "exp02_runner.mat"));
end
%%
%[text] execute experiment via simulink
%[text] \*make sure to close all simulink files before executing this section
collect_out = experiment.exp0n.run_and_collect(cfg);
logger_bin = collect_out.logger_bin;
expected_log_n = sample_n * repeat_count;
[signals, feedback_metrics] = experiment.exp02.signals_from_logger_bin( ...
  logger_bin, "expected_sample_count", expected_log_n);
experiment.exp0n.assert_run_contract(collect_out.run);

t = signals.time_s(1:expected_log_n);
r = repmat(r, repeat_count, 1);
y = signals.position_act; % output load position [rad]
e = signals.error; % tracking error [rad]
u = signals.control_input; % control input [A]

%%
%[text] save experiment data
if save_results
  save(char(feedback_result_path), "t", "r", "y", "e", "u", "Kd");
end
%%
%[text] ### STEP 3: Analyze the results of the experiment
%[text] download data
%%
%[text] plot tracking result of feedback control
experiment.plot.feedback_result(signals, feedback_metrics);

%[text] display error norm
fprintf("Tracking error norm: %.6g\n", norm(e));
