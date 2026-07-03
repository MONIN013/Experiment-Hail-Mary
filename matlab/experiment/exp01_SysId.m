%[text] ## Demo1: System Identification using chirp signal
%%
%[text] ### STEP 1: LOAD CONFIGURATION
%[text] load settings for the experiment
clear; close all;
cfg = experiment.ExperimentConfig.defaults();
Ts = 1 / cfg.env.task_rate_hz;
%%
%[text] ### STEP2 DESIGN EXCITATION SIGNAL

Tcycle_s = 10;
repeat_count = 10;
f0_hz = 0.5;
f1_hz = 4000;
chirp_amplitude = 0.1;
transient_cycles = 3;
initial_phase_rad = 0;
hold_margin_s = 1.0;
Kp = 0;
nominal_sample_delay = 4;

%%
%[text] ### STEP3: GENERATE CHIRP SIGNAL
%[text] Nyquist guard
nyquist_guard_hz = 0.5 / Ts;
f1_effective_hz = min(f1_hz, nyquist_guard_hz);
if f1_effective_hz < f1_hz
  warning("experiment:exp01_SI:f1Clamped", ...
    "Requested f1=%.3f Hz exceeds Nyquist guard; using %.3f Hz instead.", ...
    f1_hz, f1_effective_hz);
end

%[text] Generate chirp signal
chirp_cfg = experiment.waveform.periodic_chirp( ...
  "Ts", Ts, ...
  "Tend", Tcycle_s, ...
  "Tcycle", Tcycle_s, ...
  "f0", f0_hz, ...
  "f1", f1_effective_hz, ...
  "A", chirp_amplitude, ...
  "initial_phase", initial_phase_rad);
sample_n = chirp_cfg.sample_count;

%[text] visualize chirp signal
figure("Name", "Chirp Signal", "Color", "w");
plot(chirp_cfg.signal);
grid on;
title("Chirp Signal");
xlabel("Sample");
ylabel("Amplitude");
%%
%[text] ### STEP4: RUN EXPERIMENT
%[text] prepare experiment configuration and run the experiment.
%[text] The reference profile is set to the designed chirp signal, and the disturbance is set to zero.
%[text] The controller is set to P-only with a small gain to keep the system stable during the experiment.
%[text] The experiment will be repeated for a specified number of cycles, and the data will be logged for analysis.
cfg.ref_profile = zeros(sample_n, 1);
cfg.ff_profile = chirp_cfg.signal(:);
cfg.dist_profile = zeros(sample_n, 1);
cfg.repeat_count = repeat_count;
cfg.wait_for_done = true;
cfg.hold_seconds = Tcycle_s + hold_margin_s;
cfg.done_timeout_s = repeat_count * Tcycle_s + hold_margin_s + 5.0;
cfg.logger_release_timeout_s = max(5.0, repeat_count * Tcycle_s / 10);
cfg.controller = experiment.ControllerConfig.p_only(Kp);

%[text] run experiment
collect_out = experiment.exp0n.run_and_collect(cfg);
run_out = collect_out.run;
logger_bin = collect_out.logger_bin;
%%
%[text] ### STEP5: ANALYZE FRF
frf_out = experiment.analyze_si_frf(logger_bin, ...
  "Ts", Ts, ...
  "Tcycle", Tcycle_s, ...
  "transient_cycles", transient_cycles);

status_text.result_header = sprintf("\n--- Result ---\n");
status_text.run_line = sprintf("done=%d timed_out=%d\n", logical(run_out.host.done), logical(run_out.host.timed_out));
status_text.result_logger_line = sprintf("records=%d file=%s\n", ...
  logger_bin.record_count, string(logger_bin.file_path));
status_text.frf_line = sprintf("FRF input=%s output=%s windowSamples=%d usablePeriods=%d\n", ...
  frf_out.input_signal_name, frf_out.output_signal_name, ...
  frf_out.window_samples, frf_out.trim_info.usable_period_count)

if any(frf_out.coherence < 0.2)
  warning("experiment:exp01_SI:lowCoherence", ...
    "Coherence drops below 0.2 in part of the analyzed band.");
end
%%
%[text] ### STEP6: PLOT AND SAVE RESULTS

freq_hz = frf_out.freq_hz(:);
omega_rad_s = 2 * pi * freq_hz;
vm_cfg = experiment.exp01.nominal_overlay_plant();
frf_nominal = experiment.analysis.nominal_two_inertia_frf( ...
  vm_cfg, omega_rad_s, ...
  "Ts", Ts, ...
  "sample_delay", nominal_sample_delay);

experiment.plot.si_frf(freq_hz, frf_out.frf(:), frf_nominal, frf_out.coherence(:), transient_cycles);

si_out = struct( ...
  "run", run_out, ...
  "logger_bin", logger_bin, ...
  "frf", frf_out, ...
  "chirp", chirp_cfg);

save("exp01_SI_results.mat", "si_out", "-v7.3");
