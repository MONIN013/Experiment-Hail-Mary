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
Tend = 10;
Tcycle = 10;
repeat_count = 10;
f0 = 0.1;
f1 = 4000;
A = 1;
transient_cycles = 2;
initial_phase = 0;
hold_margin_s = 1.0;
Kp = 0;

nyquist_guard_hz = 0.5 / Ts;
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
cfg.repeat_count = repeat_count;
cfg.wait_for_done = true;
cfg.hold_seconds = Tend + hold_margin_s;
cfg.done_timeout_s = repeat_count * Tend + hold_margin_s + 5.0;
cfg.logger_release_timeout_s = max(5.0, repeat_count * Tend / 10);
cfg.plant = experiment.PlantConfig.from_struct(struct( ...
  "motor", struct( ...
    "inertia", 0.02, ...
    "damping", 0.2, ...
    "ratedTorque", 1.2, ...
    "tauLimit", 2.4, ...
    "velLimit", 2*pi*60, ...
    "maxPermille", 0.0, ...
    "encoderResolution", uint32(8388608)), ...
  "load", struct( ...
    "inertia", 0.03, ...
    "damping", 0.15, ...
    "ratedTorque", 1.2, ...
    "tauLimit", 2.4, ...
    "velLimit", 2*pi*60, ...
    "encoderResolution", uint32(8388608)), ...
  "coupling", struct( ...
    "stiffness", 50.0, ...
    "damping", 0.5)));
cfg.controller = experiment.ControllerConfig.p_only(Kp);

fprintf("=== SI Demo (FF chirp, load_velocity FRF) ===\n");
fprintf("Ts=%.6f s, Tend=%.3f s, Tcycle=%.3f s, repeats=%d, total=%.3f s, A=%.3f\n", ...
  Ts, Tend, Tcycle, repeat_count, repeat_count * Tend, A);
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
freq_hz = frf_out.freq_hz(:);
omega_rad_s = 2 * pi * freq_hz;
frf_measured = frf_out.frf(:);
frf_nominal = compute_nominal_two_inertia_frf( ...
  cfg.plant, omega_rad_s, ...
  "Ts", Ts, ...
  "sample_delay", 4);

mag_measured_db = mag2db(abs(frf_measured));
mag_nominal_db = mag2db(abs(frf_nominal));
phase_measured_deg = wrap_phase_at_180(rad2deg(unwrap(angle(frf_measured))));
phase_nominal_deg = wrap_phase_at_180(rad2deg(unwrap(angle(frf_nominal))));

figure("Name", "SI Demo", "Color", "w");
tiledlayout(3, 1, "Padding", "compact", "TileSpacing", "compact");

nexttile;
semilogx(freq_hz, mag_measured_db, "-", "LineWidth", 1.2, "DisplayName", "Measured"); hold on;
semilogx(freq_hz, mag_nominal_db, "--", "LineWidth", 1.2, "DisplayName", "Nominal");
hold off;
grid on;
xlabel("Frequency [Hz]");
ylabel("Gain [dB]");
legend("Location", "best");
title("FRF Gain: ffValue -> loadVelocity");

nexttile;
semilogx(freq_hz, phase_measured_deg, "-", "LineWidth", 1.2, "DisplayName", "Measured"); hold on;
semilogx(freq_hz, phase_nominal_deg, "--", "LineWidth", 1.2, "DisplayName", "Nominal");
hold off;
grid on;
xlabel("Frequency [Hz]");
ylabel("Phase [deg]");
ylim([-180, 180]);
yticks([-180, -135, -90, -45, 0, 45, 90, 135, 180]);
legend("Location", "best");
title("FRF Phase: ffValue -> loadVelocity");

nexttile;
semilogx(freq_hz, frf_out.coherence, "-", "LineWidth", 1.2);
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

function phase_wrapped_deg = wrap_phase_at_180(phase_deg)
phase_wrapped_deg = mod(phase_deg + 180, 360) - 180;
end

function frf_nominal = compute_nominal_two_inertia_frf(plant_cfg, omega_rad_s, varargin)
parser = inputParser;
parser.addParameter("Ts", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
parser.addParameter("sample_delay", 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
parser.parse(varargin{:});
args = parser.Results;

s = 1i * omega_rad_s(:);
s(abs(s) == 0) = 1i * eps;
plant = plant_cfg.to_struct();
jm = plant.motor.inertia;
jl = plant.load.inertia;
bm = plant.motor.damping;
bl = plant.load.damping;
ks = plant.coupling.stiffness;
ds = plant.coupling.damping;
c = ds + ks ./ s;
den = (jm .* s + bm + c) .* (jl .* s + bl + c) - c .* c;
frf_nominal = c ./ den;

sample_delay = double(args.sample_delay);
if sample_delay > 0
  if isempty(args.Ts)
    error("experiment:run_si_demo:invalidConfig", ...
      "Ts is required when sample_delay is nonzero.");
  end
  frf_nominal = frf_nominal .* exp(-s * args.Ts * sample_delay);
end
end
