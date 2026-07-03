%[text] # exp02 Feedback Experiment
%[text] Demo2: Feedback Control Experiment
%[text]
%[text] 実機を対象とした Feedback Control 用の実験ファイル。PI / PD / PID Controller のゲインを変更し、実験前に安定性と性能を確認する。
%[text]
%[text] ## 安全確認
%%
%[text] ## 学生が調整するパラメータ
%[text] STEP 1 DESIGN FEEDBACK CONTROLLER: まず PIDF のゲインを決める。必要に応じて trajectory の読み込み先も指定する。
Kp = 0.7;
Ki = 0.03;
Kd = 2.5e-03;
Tf = 0.025;
Smax = 2;

trajectory_mat_path = "";
trajectory_variable_name = "ref_profile";

target_position_rad = deg2rad(2);
pre_step_s = 1.0;
step_hold_s = 2.0;
repeat_count = 1;
hold_margin_s = 1.0;

save_results = true;
nominal_sample_delay = 4;
script_dir = string(fileparts(mfilename("fullpath")));
result_dir = fullfile(script_dir, "data");
plant_mat_path = fullfile(result_dir, "plant.mat");
feedback_result_path = fullfile(result_dir, "feedback_result.mat");
%%
%[text] ## 環境読み込み
%[text] ADS 接続情報、logger path、task rate は ExperimentConfig から取得する。
cfg = experiment.ExperimentConfig.defaults();
Ts = 1 / cfg.env.task_rate_hz;
%%
%[text] ## 制御器設計
%[text] proto の PIDF: K = Kp + Ki/s + Kd*s/(1+Tf*s) を作り、Tustin で離散化する。
K_cont = pid(Kp, Ki, Kd, Tf);
Kd_z = c2d(K_cont, Ts, "tustin");
controller_cfg = experiment.controller.from_discrete_tf(Kd_z);

controller_params = controller_cfg.to_flat_struct();
controller_summary = struct( ...
  "Kp", Kp, ...
  "Ki", Ki, ...
  "Kd", Kd, ...
  "Tf", Tf, ...
  "Ts", Ts, ...
  "pid_b0", controller_params.pid_b0, ...
  "pid_b1", controller_params.pid_b1, ...
  "pid_b2", controller_params.pid_b2, ...
  "pid_a1", controller_params.pid_a1, ...
  "pid_a2", controller_params.pid_a2);

figure("Name", "Feedback Controller", "Color", "w");
bode(Kd_z);
grid on;
title("Discrete PIDF Controller");
%%
%[text] ## 安定性・性能確認
%[text] Always check before experiment. `data/plant.mat` がある場合は、測定 FRF と nominal plant で Nyquist と sensitivity を確認する。
stability_check = experiment.exp02.stability_check(Kd_z, plant_mat_path, Smax, Ts, nominal_sample_delay);
%%
%[text] ## 軌道生成
%[text] STEP 2 FEEDBACK EXPERIMENT: reference trajectory を作成する。純粋な feedback 実験なので feedforward は 0 のままにする。
ref_profile = experiment.exp02.reference_profile( ...
  trajectory_mat_path, ...
  trajectory_variable_name, ...
  target_position_rad, ...
  pre_step_s, ...
  step_hold_s, ...
  Ts);

sample_n = numel(ref_profile);
per_trial_s = sample_n * Ts;
t_ref = (0:sample_n-1)' * Ts;

figure("Name", "Reference Profile", "Color", "w");
plot(t_ref, ref_profile, "-", "LineWidth", 1.2);
grid on;
xlabel("Time [s]");
ylabel("Position [rad]");
title("Reference Profile");
%%
%[text] ## 実験実行
%[text] proto の `set_ref=r; set_ff=zeros` に対応する設定で実機へ書き込む。
cfg.ref_profile = ref_profile(:);
cfg.ff_profile = zeros(sample_n, 1);
cfg.dist_profile = zeros(sample_n, 1);
cfg.repeat_count = repeat_count;
cfg.wait_for_done = true;
cfg.hold_seconds = per_trial_s + hold_margin_s;
cfg.done_timeout_s = repeat_count * per_trial_s + hold_margin_s + 5.0;
cfg.logger_release_timeout_s = max(5.0, repeat_count * per_trial_s / 10);
cfg.controller = controller_cfg;
if save_results
  cfg.save_path = char(fullfile(result_dir, "exp02_runner.mat"));
end

status_text = struct();
status_text.header = sprintf("=== Real Motor Feedback Template ===\n");
status_text.config_line = sprintf("Ts=%.6f s, samples=%d, perTrial=%.3f s, repeats=%d\n", ...
  Ts, sample_n, per_trial_s, repeat_count);
status_text.controller_line = sprintf("PIDF: Kp=%.6g, Ki=%.6g, Kd=%.6g, Tf=%.6g\n", ...
  Kp, Ki, Kd, Tf);
status_text.logger_line = sprintf("loggerFile=%s\n", string(cfg.env.logger_host_file_path));

collect_out = experiment.exp0n.run_and_collect(cfg);
run_out = collect_out.run;
logger_bin = collect_out.logger_bin;
status_text.connection_line = sprintf("Connected: SEQ=%d, CTRL=%d, MODULE=%d\n", ...
  cfg.env.seq_port, cfg.env.control_port, cfg.env.module_port);
%%
%[text] ## 結果整理
%[text] STEP 3 Analyze results: tracking, error, input current を整理し、proto の `norm(e)` に相当する値を表示する。
[signals, feedback_metrics] = experiment.exp02.signals_from_logger_bin(logger_bin);
tracking_error_norm = norm(signals.error);
fprintf("norm(error) = %.6g\n", tracking_error_norm);

status_text.result_header = sprintf("\n--- Result ---\n");
status_text.run_line = sprintf("done=%d timed_out=%d stopReason=%s\n", ...
  logical(run_out.host.done), logical(run_out.host.timed_out), string(run_out.host.stop_reason));
status_text.result_logger_line = sprintf("logger=%s records=%d file=%s\n", ...
  string(logger_bin.file_path), logger_bin.record_count, string(logger_bin.file_path));
status_text.error_line = sprintf("trackingErrorL2=%.6g, maxAbsError=%.6g, maxAbsControlInput=%.6g A\n", ...
  feedback_metrics.tracking_error_l2, feedback_metrics.max_abs_error, feedback_metrics.max_abs_control_input);
status_text.error_norm_line = sprintf("norm(error)=%.6g\n", tracking_error_norm);

feedback_out = struct( ...
  "run", run_out, ...
  "logger_bin", logger_bin, ...
  "controller", controller_summary, ...
  "stability_check", stability_check, ...
  "reference", struct( ...
    "profile", ref_profile(:), ...
    "time_s", t_ref, ...
    "trajectory_mat_path", string(trajectory_mat_path), ...
    "trajectory_variable_name", string(trajectory_variable_name)), ...
  "signals", signals, ...
  "metrics", feedback_metrics);

if save_results
  if ~isfolder(char(result_dir))
    mkdir(char(result_dir));
  end
  save(char(feedback_result_path), ...
    "feedback_out", "signals", "feedback_metrics", "tracking_error_norm", ...
    "controller_summary", "K_cont", "Kd_z", "stability_check", "ref_profile", "t_ref", "Ts");
end
%%
%[text] ## 可視化
experiment.plot.feedback_result(signals, feedback_metrics);
%%
%[text] ## 次の調整指針
%[text] Nyquist が -1 点や Smax circle に近い場合は Kp/Ki/Kd/Tf を下げる、または filter を追加する。tracking error が大きい場合は安定余裕を確認した上でゲインを調整する。
