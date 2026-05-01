%[text] # exp01 System Identification
%[text] 実機を対象とした System Identification 用の実験ファイル。
%[text] 学生はこのファイルを Live Editor で開き、下の「学生が調整するパラメータ」だけを変更して実行する。
%[text]
%[text] ## 安全確認
%[text] - TwinCAT は実機マッピング側の project / runtime を使用していること。
%[text] - 可動範囲、非常停止、配線、logger 保存先を実行前に確認すること。
%[text] - chirp 振幅と周波数帯は必ず小さい条件から始めること。
%[text] - 環境設定は `run('matlab/setup_matlab_environment.m')` で初回作成し、通常の実験中は変更しないこと。
%%
%[text] ## 学生が調整するパラメータ
Tend_s = 10;
Tcycle_s = 10;
repeat_count = 10;
f0_hz = 0.5;
f1_hz = 4000;
chirp_amplitude = 0.1;
transient_cycles = 3;
initial_phase_rad = 0;
hold_margin_s = 1.0;
Kp = 0;
%%
%[text] ## 環境読み込み
cfg = experiment.ExperimentConfig.defaults();
logger_file_glob = "*.bin";
logger_dir = string(fileparts(char(cfg.env.logger_host_file_path)));
Ts = 1 / cfg.env.task_rate_hz;
%%
%[text] ## chirp 生成
nyquist_guard_hz = 0.5 / Ts;
f1_effective_hz = min(f1_hz, nyquist_guard_hz);
if f1_effective_hz < f1_hz
  warning("experiment:exp01_SI:f1Clamped", ...
    "Requested f1=%.3f Hz exceeds Nyquist guard; using %.3f Hz instead.", ...
    f1_hz, f1_effective_hz);
end

chirp_cfg = experiment.waveform.periodic_chirp( ...
  "Ts", Ts, ...
  "Tend", Tend_s, ...
  "Tcycle", Tcycle_s, ...
  "f0", f0_hz, ...
  "f1", f1_effective_hz, ...
  "A", chirp_amplitude, ...
  "initial_phase", initial_phase_rad);
sample_n = chirp_cfg.sample_count;

figure("Name", "Chirp Signal", "Color", "w");
plot(chirp_cfg.signal);
grid on;
title("Chirp Signal");
xlabel("Sample");
ylabel("Amplitude");
%%
%[text] ## 実験実行
cfg.ref_profile = zeros(sample_n, 1);
cfg.ff_profile = chirp_cfg.signal(:);
cfg.dist_profile = zeros(sample_n, 1);
cfg.repeat_count = repeat_count;
cfg.wait_for_done = true;
cfg.hold_seconds = Tend_s + hold_margin_s;
cfg.done_timeout_s = repeat_count * Tend_s + hold_margin_s + 5.0;
cfg.logger_release_timeout_s = max(5.0, repeat_count * Tend_s / 10);
cfg.controller = experiment.ControllerConfig.p_only(Kp);

status_text = struct();
status_text.header = sprintf("=== Real Motor SI Template ===\n");
status_text.config_line = sprintf("Ts=%.6f s, Tend=%.3f s, Tcycle=%.3f s, repeats=%d, total=%.3f s, A=%.3f\n", ...
  Ts, Tend_s, Tcycle_s, repeat_count, repeat_count * Tend_s, chirp_amplitude);
status_text.band_line = sprintf("f0=%.3f Hz, f1(requested)=%.3f Hz, f1(effective)=%.3f Hz, transient_cycles=%d\n", ...
  f0_hz, f1_hz, f1_effective_hz, transient_cycles);
status_text.logger_line = sprintf("Samples=%d, cycles=%.2f, loggerDir=%s\n", sample_n, chirp_cfg.cycle_count, logger_dir);

conn = experiment.ConnectionManager.create(cfg);
cleanup = onCleanup(@() conn.session.close());
status_text.connection_line = sprintf("Connected: SEQ=%d, CTRL=%d, MODULE=%d\n", cfg.env.seq_port, cfg.env.control_port, cfg.env.module_port);

run_out = experiment.ExperimentRunner.run(conn, cfg);
latest_bin = experiment.io.read_latest_logger_bin(logger_dir, logger_file_glob);
if ~latest_bin.ok
  error("experiment:exp01_SI:loggerUnavailable", ...
    "ExperimentLogger bin is unavailable (%s).", string(latest_bin.reason));
end
logger_bin = latest_bin.logger_bin;
%%
%[text] ## FRF 解析
frf_out = experiment.analyze_si_frf(logger_bin, ...
  "Ts", Ts, ...
  "Tcycle", Tcycle_s, ...
  "transient_cycles", transient_cycles);

status_text.result_header = sprintf("\n--- Result ---\n");
status_text.run_line = sprintf("done=%d timed_out=%d\n", logical(run_out.host.done), logical(run_out.host.timed_out));
status_text.result_logger_line = sprintf("logger=%s records=%d file=%s\n", ...
  string(latest_bin.reason), logger_bin.record_count, string(logger_bin.file_path));
status_text.frf_line = sprintf("FRF input=%s output=%s windowSamples=%d usablePeriods=%d\n", ...
  frf_out.input_signal_name, frf_out.output_signal_name, ...
  frf_out.window_samples, frf_out.trim_info.usable_period_count);

if any(frf_out.coherence < 0.2)
  warning("experiment:exp01_SI:lowCoherence", ...
    "Coherence drops below 0.2 in part of the analyzed band.");
end
%%
%[text] ## 可視化
freq_hz = frf_out.freq_hz(:);
omega_rad_s = 2 * pi * freq_hz;
vm_cfg = experiment.exp01.nominal_overlay_plant();
frf_nominal = experiment.analysis.nominal_two_inertia_frf( ...
  vm_cfg, omega_rad_s, ...
  "Ts", Ts, ...
  "sample_delay", 4);

experiment.plot.si_frf(freq_hz, frf_out.frf(:), frf_nominal, frf_out.coherence(:), transient_cycles);

si_out = struct( ...
  "run", run_out, ...
  "logger_bin", logger_bin, ...
  "frf", frf_out, ...
  "chirp", chirp_cfg);
%%
%[text] ## 次の調整指針
%[text] - `chirp_amplitude` は 0.1 から始め、飽和や異常振動がなければ段階的に上げる。
%[text] - `repeat_count` を増やす前に単発で logger と coherence を確認する。
%[text] - `f1_hz` は機械共振帯とサンプリング上限の両方を見て設定する。
%[text] - coherence が低い帯域は振幅不足、非線形、ログ不足を疑う。
%[text] - 必要なら `si_out` を起点に Live Editor 上で追加解析を行う。
