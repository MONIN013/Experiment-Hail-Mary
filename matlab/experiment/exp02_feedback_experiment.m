%[text] # exp02 Feedback Experiment
%[text] 実機を対象とした Feedback Control 用の実験ファイル。
%[text] 学生はこのファイルを Live Editor で開き、下の「学生が調整するパラメータ」だけを変更して実行する。
%[text]
%[text] ## 安全確認
%[text] - TwinCAT は実機マッピング側の project / runtime を使用していること。
%[text] - 可動範囲、非常停止、配線、logger 保存先を実行前に確認すること。
%[text] - PID ゲインと軌道は小さい条件から段階的に調整すること。
%[text] - 環境設定は `run('matlab/setup_matlab_environment.m')` で初回作成し、通常の実験中は変更しないこと。
%%
%[text] ## 学生が調整するパラメータ
Kp = 0.7;
Ki = 0.4;
Kd = 2.5e-03;
Tf = 0.025;

trajectory_mat_path = "";
trajectory_variable_name = "ref_profile";

target_position_rad = deg2rad(2);
pre_step_s = 1.0;
step_hold_s = 2.0;
repeat_count = 1;
hold_margin_s = 1.0;
%%
%[text] ## 環境読み込み
cfg = experiment.ExperimentConfig.defaults();
logger_file_glob = "*.bin";
logger_dir = string(fileparts(char(cfg.env.logger_host_file_path)));
Ts = 1 / cfg.env.task_rate_hz;
%%
%[text] ## 制御器設計
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
%[text] ## 軌道生成
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
cfg.ref_profile = ref_profile(:);
cfg.ff_profile = zeros(sample_n, 1);
cfg.dist_profile = zeros(sample_n, 1);
cfg.repeat_count = repeat_count;
cfg.wait_for_done = true;
cfg.hold_seconds = per_trial_s + hold_margin_s;
cfg.done_timeout_s = repeat_count * per_trial_s + hold_margin_s + 5.0;
cfg.logger_release_timeout_s = max(5.0, repeat_count * per_trial_s / 10);
cfg.controller = controller_cfg;

status_text = struct();
status_text.header = sprintf("=== Real Motor Feedback Template ===\n");
status_text.config_line = sprintf("Ts=%.6f s, samples=%d, perTrial=%.3f s, repeats=%d\n", ...
  Ts, sample_n, per_trial_s, repeat_count);
status_text.controller_line = sprintf("PIDF: Kp=%.6g, Ki=%.6g, Kd=%.6g, Tf=%.6g\n", ...
  Kp, Ki, Kd, Tf);
status_text.logger_line = sprintf("loggerDir=%s\n", logger_dir);

conn = experiment.ConnectionManager.create(cfg);
cleanup = onCleanup(@() conn.session.close());
status_text.connection_line = sprintf("Connected: SEQ=%d, CTRL=%d, MODULE=%d\n", ...
  cfg.env.seq_port, cfg.env.control_port, cfg.env.module_port);

run_out = experiment.ExperimentRunner.run(conn, cfg);
latest_bin = experiment.io.read_latest_logger_bin(logger_dir, logger_file_glob);
if ~latest_bin.ok
  error("experiment:exp02_feedback:loggerUnavailable", ...
    "ExperimentLogger bin is unavailable (%s).", string(latest_bin.reason));
end
logger_bin = latest_bin.logger_bin;
%%
%[text] ## 結果整理
[signals, feedback_metrics] = experiment.exp02.signals_from_logger_bin(logger_bin);

status_text.result_header = sprintf("\n--- Result ---\n");
status_text.run_line = sprintf("done=%d timed_out=%d stopReason=%s\n", ...
  logical(run_out.host.done), logical(run_out.host.timed_out), string(run_out.host.stop_reason));
status_text.result_logger_line = sprintf("logger=%s records=%d file=%s\n", ...
  string(latest_bin.reason), logger_bin.record_count, string(logger_bin.file_path));
status_text.error_line = sprintf("trackingErrorL2=%.6g, maxAbsError=%.6g, maxAbsControlInput=%.6g A\n", ...
  feedback_metrics.tracking_error_l2, feedback_metrics.max_abs_error, feedback_metrics.max_abs_control_input);

feedback_out = struct( ...
  "run", run_out, ...
  "logger_bin", logger_bin, ...
  "controller", controller_summary, ...
  "reference", struct( ...
    "profile", ref_profile(:), ...
    "time_s", t_ref, ...
    "trajectory_mat_path", string(trajectory_mat_path), ...
    "trajectory_variable_name", string(trajectory_variable_name)), ...
  "signals", signals, ...
  "metrics", feedback_metrics);
%%
%[text] ## 可視化
experiment.plot.feedback_result(signals, feedback_metrics);
%%
%[text] ## 次の調整指針
%[text] - 最初は小さいステップで logger records / error / current を確認する。
%[text] - S 字軌道へ移行する場合は mat 内の `ref_profile` を [rad] の列ベクトルで保存する。
%[text] - PID を強くする前に `max_abs_control_input` と機械系の可動範囲を確認する。
%[text] - Plant 同定結果がある場合は、制御器確認節に開ループ安定性確認を追加する。
%[text] - 必要なら `feedback_out` を起点に Live Editor 上で追加解析を行う。
