%% SI demo using FF chirp injection and ExperimentLogger bin
%
%  ref=0, dist=0 のまま ff_profile に周期 chirp を注入し、ExperimentLogger
%  の load_velocity を使って FRF / coherence を算出する。
%
%  注意:
%    - SIL の current branch では motor_velocity が未配線のため対象外
%    - f1 は Nyquist 未満にクランプして使用する

base_dir = fileparts(mfilename("fullpath"));
restoredefaultpath;
addpath(genpath(base_dir));

sys = experiment.SystemConfig;
cfg = experiment.ExperimentConfig.defaults();
logger_file_glob = "*.bin";
logger_dir = string(fileparts(char(sys.LOGGER_DEFAULT_FILE_PATH)));

%% SI parameters (mirrors old temp.md flow)
Ts = 1 / cfg.task_rate_hz;
Tend = 100;
Tcycle = 10;
f0 = 0.1;
f1 = 500;
A = 1;
transient_cycles = 2;
initial_phase = 0;
hold_margin_s = 1.0;
Kp = 0;

nyquist_guard_hz = 0.45 / Ts;
f1_effective = min(f1, nyquist_guard_hz);
if f1_effective < f1
  warning("experiment:run_si_demo:f1Clamped", ...
    "Requested f1=%.3f Hz exceeds Nyquist guard; using %.3f Hz instead.", ...
    f1, f1_effective);
end

chirp_cfg = experiment.build_periodic_chirp( ...
  "Ts", Ts, ...
  "Tend", Tend, ...
  "Tcycle", Tcycle, ...
  "f0", f0, ...
  "f1", f1_effective, ...
  "A", A, ...
  "initial_phase", initial_phase);
sample_n = chirp_cfg.sample_count;

%% Runtime config
cfg.ref_profile = zeros(sample_n, 1);
cfg.ff_profile = chirp_cfg.signal(:);
cfg.dist_profile = zeros(sample_n, 1);
cfg.repeat_count = 1;
cfg.wait_for_done = true;
cfg.hold_seconds = Tend + hold_margin_s;
cfg.done_timeout_s = Tend + hold_margin_s + 5.0;
cfg.logger_release_timeout_s = max(5.0, Tend / 10);
cfg.plant = experiment.PlantConfig.from_struct(struct( ...
  "m", 0.02, ...
  "d", 0.2, ...
  "rated_current", 1.2, ...
  "max_permille", 0.0, ...
  "tau_limit", 2.4, ...
  "vel_limit", 2*pi*60));
cfg.controller = experiment.ControllerConfig.p_only(Kp);

fprintf("=== SI Demo (FF chirp, load_velocity FRF) ===\n");
fprintf("Ts=%.6f s, Tend=%.3f s, Tcycle=%.3f s, A=%.3f\n", Ts, Tend, Tcycle, A);
fprintf("f0=%.3f Hz, f1(requested)=%.3f Hz, f1(effective)=%.3f Hz, transient_cycles=%d\n", ...
  f0, f1, f1_effective, transient_cycles);
fprintf("Samples=%d, cycles=%.2f, loggerDir=%s\n", sample_n, chirp_cfg.cycle_count, logger_dir);

%% ADS connect
seq_transport = twincat_ads.AdsTransport();
ctrl_transport = twincat_ads.AdsTransport();
mod_transport = twincat_ads.AdsTransport();
cleanup = onCleanup(@() disconnect_all(seq_transport, ctrl_transport, mod_transport)); %#ok<NASGU>

seq_transport.connect(cfg.ams_net_id, cfg.seq_port);
ctrl_transport.connect(cfg.ams_net_id, cfg.control_port);
mod_transport.connect(cfg.ams_net_id, cfg.module_port);
fprintf("Connected: SEQ=%d, CTRL=%d, MODULE=%d\n", cfg.seq_port, cfg.control_port, cfg.module_port);

%% Run experiment and read logger
conn = struct("seq", seq_transport, "ctrl", ctrl_transport, "module", mod_transport);
run_out = experiment.ExperimentRunner.run(conn, cfg);
latest_bin = experiment.read_latest_logger_bin(logger_dir, logger_file_glob);
if ~latest_bin.ok
  error("experiment:run_si_demo:loggerUnavailable", ...
    "ExperimentLogger bin is unavailable (%s).", string(latest_bin.reason));
end

logger_bin = latest_bin.logger_bin;
frf_out = experiment.analyze_si_frf(logger_bin, ...
  "Ts", Ts, ...
  "Tcycle", Tcycle, ...
  "transient_cycles", transient_cycles);

fprintf("\n--- Result ---\n");
fprintf("done=%d timed_out=%d\n", logical(run_out.host.done), logical(run_out.host.timed_out));
fprintf("logger=%s records=%d file=%s\n", ...
  string(latest_bin.reason), logger_bin.record_count, string(logger_bin.file_path));
fprintf("FRF input=%s output=%s windowSamples=%d usablePeriods=%d\n", ...
  frf_out.input_signal_name, frf_out.output_signal_name, ...
  frf_out.window_samples, frf_out.trim_info.usable_period_count);

if any(frf_out.coherence < 0.2)
  warning("experiment:run_si_demo:lowCoherence", ...
    "Coherence drops below 0.2 in part of the analyzed band.");
end

%% Plot
t_log = logger_bin.raw.t_s(:);
if ~isempty(t_log)
  t_log = t_log - t_log(1);
else
  t_log = chirp_cfg.t;
end

figure("Name", "SI Demo", "Color", "w");
tiledlayout(3, 1, "Padding", "compact", "TileSpacing", "compact");

nexttile;
plot(t_log, logger_bin.raw.ff_value(:), "-", "LineWidth", 1.0, "DisplayName", "ffValue"); hold on;
plot(t_log, logger_bin.raw.control_input(:), "-", "LineWidth", 1.0, "DisplayName", "controlInput");
if any(abs(logger_bin.raw.current_cmd(:)) > 0)
  plot(t_log, logger_bin.raw.current_cmd(:), "--", "LineWidth", 0.9, "DisplayName", "currentCmd");
end
hold off;
grid on;
xlabel("Time [s]");
ylabel("Current [A]");
legend("Location", "best");
title("Input-side Signals");

nexttile;
yyaxis left;
semilogx(frf_out.freq_hz, mag2db(abs(frf_out.frf)), "-", "LineWidth", 1.2, "DisplayName", "FRF magnitude");
ylabel("Magnitude [dB]");
yyaxis right;
semilogx(frf_out.freq_hz, rad2deg(unwrap(angle(frf_out.frf))), "-", "LineWidth", 1.0, "DisplayName", "FRF phase");
ylabel("Phase [deg]");
grid on;
xlabel("Frequency [Hz]");
title("FRF: ffValue -> loadVelocity");

nexttile;
semilogx(frf_out.freq_hz, frf_out.coherence, "-", "LineWidth", 1.2);
grid on;
xlabel("Frequency [Hz]");
ylabel("Coherence");
ylim([0, 1.05]);
title(sprintf("Coherence (transient cycles removed = %d)", transient_cycles));

si_out = struct( ...
  "run", run_out, ...
  "logger_bin", logger_bin, ...
  "frf", frf_out, ...
  "chirp", chirp_cfg); %#ok<NASGU>

function disconnect_all(varargin)
for k = 1:numel(varargin)
  try
    varargin{k}.disconnect();
  catch
  end
end
end
