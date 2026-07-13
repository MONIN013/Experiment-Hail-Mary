%% SI demo using FF chirp injection and ExperimentLogger bin
%
%  ref=0, dist=0 のまま ff_profile に周期 chirp を注入し、ExperimentLogger
%  の load_velocity を使って FRF / coherence を算出する。
%
%  注意:
%    - SIL の current branch では motor_velocity が未配線のため対象外
%    - f1 は Nyquist 未満にクランプして使用する

tool_file = mfilename("fullpath");
matlab_root = fileparts(fileparts(tool_file));
addpath(matlab_root, fullfile(matlab_root, "experiment"));
clear tool_file matlab_root;

cfg = experiment.ExperimentConfig.defaults();

%% SI parameters (mirrors old temp.md flow)
Ts = 1 / cfg.env.task_rate_hz;
Tend = 10;
Tcycle = 10;
repeat_count = 10;
f0 = 0.1;
f1 = 4000;
A = 0.25;
transient_cycles = 2;
initial_phase = 0;
remove_chirp_mean = true;
hold_margin_s = 1.0;
Kp = 0;

nyquist_guard_hz = 0.95 * 0.5 / Ts;
f1_effective = min(f1, nyquist_guard_hz);
if f1_effective < f1
  warning("experiment:run_si_demo:f1Clamped", ...
    "Requested f1=%.3f Hz exceeds Nyquist guard; using %.3f Hz instead.", ...
    f1, f1_effective);
end

chirp_cfg = experiment.waveform.periodic_chirp( ...
  "Ts", Ts, ...
  "Tend", Tend, ...
  "Tcycle", Tcycle, ...
  "f0", f0, ...
  "f1", f1_effective, ...
  "A", A, ...
  "initial_phase", initial_phase);
% The free rigid-body mode integrates any chirp DC bias into position drift.
chirp_dc_A = mean(chirp_cfg.signal);
chirp_cfg.signal = chirp_cfg.signal - double(remove_chirp_mean) * chirp_dc_A;
driver_current_quantum_A = 1.6 / 1000;
[balanced, balance_report] = experiment.waveform.balance_quantized_cycle( ...
  chirp_cfg.signal, driver_current_quantum_A);
chirp_cfg.signal = balanced;
chirp_cfg.balance = balance_report;
sample_n = chirp_cfg.sample_count;

%% Runtime config
cfg.ref_profile = zeros(sample_n, 1);
cfg.ff_profile = balanced;
cfg.dist_profile = zeros(sample_n, 1);
cfg.repeat_count = repeat_count;
cfg.wait_for_done = true;
cfg.hold_seconds = Tend + hold_margin_s;
cfg.done_timeout_s = repeat_count * Tend + hold_margin_s + 5.0;
cfg.logger_release_timeout_s = max(5.0, repeat_count * Tend / 10);
cfg.host_heartbeat_enable = false;
cfg.external_host_heartbeat_enable = true;
cfg.controller = experiment.ControllerConfig.p_only(Kp);

fprintf("=== SI Demo (FF chirp, load_velocity FRF) ===\n");
fprintf("Ts=%.6f s, Tend=%.3f s, Tcycle=%.3f s, repeats=%d, total=%.3f s, A=%.3f\n", ...
  Ts, Tend, Tcycle, repeat_count, repeat_count * Tend, A);
fprintf("f0=%.3f Hz, f1(requested)=%.3f Hz, f1(effective)=%.3f Hz, transient_cycles=%d\n", ...
  f0, f1, f1_effective, transient_cycles);
fprintf("Chirp DC bias=%.9f A, meanRemoval=%d\n", ...
  chirp_dc_A, logical(remove_chirp_mean));
fprintf("Quantized count balance=%d -> %d, adjustedSamples=%d\n", ...
  balance_report.original_count_sum, balance_report.balanced_count_sum, ...
  balance_report.adjusted_sample_count);
fprintf("Samples=%d, cycles=%.2f, loggerFile=%s\n", ...
  sample_n, chirp_cfg.cycle_count, string(cfg.env.logger_host_file_path));

%% Run experiment and read logger
collect_out = experiment.exp0n.run_and_collect(cfg);
run_out = collect_out.run;
logger_bin = collect_out.logger_bin;
if isempty(logger_bin) || double(logger_bin.record_count) <= 0
  error("experiment:run_si_demo:loggerUnavailable", ...
    "ExperimentLogger bin is unavailable at %s.", string(run_out.logger.file_path));
end
experiment.exp0n.assert_run_contract(run_out);
frf_out = experiment.analyze_si_frf(logger_bin, ...
  "Ts", Ts, ...
  "Tcycle", Tcycle, ...
  "transient_cycles", transient_cycles);

fprintf("\n--- Result ---\n");
fprintf("done=%d timed_out=%d\n", logical(run_out.host.done), logical(run_out.host.timed_out));
fprintf("logger=%s records=%d file=%s\n", ...
  "runner-confirmed", logger_bin.record_count, string(logger_bin.file_path));
fprintf("FRF input=%s output=%s windowSamples=%d usablePeriods=%d\n", ...
  frf_out.input_signal_name, frf_out.output_signal_name, ...
  frf_out.window_samples, frf_out.trim_info.usable_period_count);

if any(frf_out.coherence < 0.2)
  warning("experiment:run_si_demo:lowCoherence", ...
    "Coherence drops below 0.2 in part of the analyzed band.");
end

%% Plot
experiment.plot.si_frf( ...
  frf_out.position_freq_hz, frf_out.position_frf, [], ...
  frf_out.coherence(frf_out.freq_hz > 0), transient_cycles);

si_out = struct( ...
  "run", run_out, ...
  "logger_bin", logger_bin, ...
  "frf", frf_out, ...
  "position_frf", struct( ...
    "input_signal_name", frf_out.input_signal_name, ...
    "output_signal_name", "load_position", ...
    "derived_from", frf_out.output_signal_name + " via Ts/(1-z^-1)", ...
    "freq_hz", frf_out.position_freq_hz, ...
    "frf", frf_out.position_frf), ...
  "chirp", chirp_cfg);
