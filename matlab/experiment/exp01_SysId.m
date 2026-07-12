%[text] ## Demo1: System Identification using chirp signal
%%
%[text] ### STEP 1: CHIRP EXCITATION
%[text] load settings for the experiment
clear; close all;

Tend = 100; % experiment length [s]
Tcycle = 10; % cycle time of chirp signal [s]
p = 0; % initial phase of chirp [rad]
f0 = 0.5; % min freq of chirp [Hz]
f1 = 4000; % max freq of chirp [Hz]
A = 0.25; % VM-safe feedforward chirp amplitude [A]
trans = 2; % number of transient periods
Jn = 7.1e-5; % student-tunable nominal inertia [A/(rad/s^2)], (Jmotor+Jload)/(ratedTorque/ratedCurrent)
Dn = 5.325e-4; % student-tunable nominal damping [A/(rad/s)], (Dmotor+Dload)/(ratedTorque/ratedCurrent)
Ndelay = 4; % student-tunable delay step of plant [samples]
use_virtual_motor = true; % false on the RealMotor project; skips all VM parameter writes

save_results = true;
require_logger_records = true;
hold_margin_s = 1.0;
script_dir = string(fileparts(mfilename("fullpath")));
result_dir = fullfile(script_dir, "data");
chirp_result_path = fullfile(result_dir, "chirp_result.mat");
plant_mat_path = fullfile(result_dir, "plant.mat");
runner_result_path = fullfile(result_dir, "exp01_runner.mat");

cfg = experiment.ExperimentConfig.defaults();
Ts = 1 / cfg.env.task_rate_hz;
%%
%[text] design excitation signal
chirp = experiment.waveform.periodic_chirp( ...
  "Ts", Ts, "Tend", Tend, "Tcycle", Tcycle, ...
  "f0", f0, "f1", f1, "A", A, "initial_phase", p);
N = chirp.sample_count;
t = chirp.t;
u = chirp.signal;

figure("Name", "Chirp Excitation", "Color", "w");
plot(t, u, "-", "LineWidth", 1.0);
grid on;
xlabel("Time [s]");
ylabel("Feedforward current [A]");
title("Open-loop chirp excitation");
%%
%[text] build simulink model "twomass\_exp\_2019a.slx" after executing this section
%[text] (build only needed 1 time.  rebuild required if you change the following parameters or the feedback controller Kd.)
if save_results && ~isfolder(char(result_dir))
  mkdir(char(result_dir));
end

fb_flag = 0;
% The GVL_SEQ playback table holds at most 100000 samples, so the periodic
% chirp is written as one Tcycle-long cycle and replayed repeat_count times.
% The chirp is Tcycle-periodic by construction, so replaying one cycle
% produces the requested full-length excitation exactly.
N_cycle = round(Tcycle/Ts);
n_repeat = round(Tend/Tcycle);
set_ref = zeros(N_cycle, 1);
set_ff = u(1:N_cycle);

cfg.ref_profile = set_ref;
cfg.ff_profile = set_ff;
cfg.dist_profile = zeros(N_cycle, 1);
cfg.repeat_count = n_repeat;
cfg.wait_for_done = true;
cfg.hold_seconds = Tend + hold_margin_s;
cfg.done_timeout_s = Tend + hold_margin_s + 5.0;
cfg.logger_release_timeout_s = max(5.0, Tend / 10);
cfg.controller = experiment.ControllerConfig.p_only(0);
cfg.host_heartbeat_enable = false;
cfg.external_host_heartbeat_enable = true;
cfg.write_virtual_motor_params = use_virtual_motor;
cfg.restart_virtual_motor_runtime = false; % lifecycle restart is reserved for test-only prediction oracles
vm_plant = []; %#ok<NASGU> assigned when the operator switches to RealMotor
vm_mode = []; %#ok<NASGU> assigned when the operator switches to RealMotor
if use_virtual_motor
  cfg.virtual_motor_plant = experiment.exp01.nominal_overlay_plant();
  vm_plant = cfg.virtual_motor_plant.to_struct();
  vm_mode = virtualMotor.torsional_mode(cfg.virtual_motor_plant);
  if abs(vm_mode.natural_frequency_hz - 200) > 0.5
    error("experiment:exp01_SysId:invalidVirtualMotorMode", ...
      "VirtualMotor torsional natural frequency must be approximately 200 Hz.");
  end
  fprintf("VirtualMotor torsional mode: fn=%.6f Hz, fd=%.6f Hz, zeta=%.6f\n", ...
    vm_mode.natural_frequency_hz, vm_mode.damped_frequency_hz, vm_mode.damping_ratio);
end
if save_results
  cfg.save_path = char(runner_result_path);
end
%%
%[text] execute experiment via simulink
%[text] \*make sure to close all simulink files before executing this section
collect_out = experiment.exp0n.run_and_collect(cfg);
run_out = collect_out.run;
logger_bin = collect_out.logger_bin;
raw = logger_bin.raw;

experiment.exp0n.assert_run_contract(run_out);

if ~isfield(raw, "control_input") || ~isfield(raw, "load_position") || ~isfield(raw, "motor_position")
  error("experiment:exp01_SysId:missingLoggerSignal", ...
    "logger_bin.raw must contain control_input, load_position, and motor_position.");
end
if require_logger_records && double(logger_bin.record_count) < N
  error("experiment:exp01_SysId:notEnoughLoggerRecords", ...
    "Expected at least %d logger records for Tend=%.3f s, got %d.", ...
    N, Tend, double(logger_bin.record_count));
end

input = double(raw.control_input(:)); % input current [A]
loadpos = double(raw.load_position(:)); % load-side position [rad]
motorpos = double(raw.motor_position(:)); % motor-side position [rad]
input = input(1:N);
loadpos = loadpos(1:N);
motorpos = motorpos(1:N);

status_text = struct();
status_text.result_header = sprintf("\n--- Result ---\n");
status_text.run_line = sprintf("done=%d timed_out=%d stopReason=%s fb_flag=%d\n", ...
  logical(run_out.host.done), logical(run_out.host.timed_out), char(string(run_out.host.stop_reason)), fb_flag);
status_text.result_logger_line = sprintf("logger=%s records=%d file=%s\n", ...
  char(string(logger_bin.file_path)), logger_bin.record_count, char(string(logger_bin.file_path)));
fprintf("%s%s%s", status_text.result_header, status_text.run_line, status_text.result_logger_line);

%%
%[text] save experiment data
if save_results
  save(chirp_result_path, 'input', 'loadpos', 'motorpos', 'Ts', 'Tend', 'Tcycle');
end
%%
%[text] ### STEP 2: TIME TREATMENT
%[text] download data
if save_results
  load(chirp_result_path, 'input', 'loadpos', 'motorpos', 'Ts', 'Tend', 'Tcycle');
end

%[text] remove transient periods
Nstart = trans*Tcycle/Ts+1;
N = Tend/Ts; % total sample points of data
nrofs = Tcycle/Ts;
input = input(Nstart:N); % control input of plant [A]
loadvel = diff([loadpos(Nstart:end); loadpos(end)])/Ts; % load-side velocity [rad/s]
motorvel = diff([motorpos(Nstart:end); motorpos(end)])/Ts; % motor-side velocity [rad/s]
%%
%[text] ### STEP 3: NON-PARAMETRIC ESTIMATION
%[text] fft data and vizualize in freq domain position data
[txy, f] = tfestimate(input, loadvel, rectwin(Tcycle/Ts), 0, Tcycle/Ts, 1/Ts);
Pd_vel_load = frd(txy, f, "FrequencyUnit", "Hz");
Pd_vel_load.Ts = Ts;
[txy, f] = tfestimate(input, motorvel, rectwin(Tcycle/Ts), 0, Tcycle/Ts, 1/Ts);
Pd_vel_motor = frd(txy, f, "FrequencyUnit", "Hz");
Pd_vel_motor.Ts = Ts;
%%
%[text] check coherence (good if close to 0dB)
figure("Name", "Load-side coherence", "Color", "w");
mscohere(input, loadvel, rectwin(Tcycle/Ts), 0, Tcycle/Ts, 1/Ts);
ax = gca; ax.XScale = 'log';
title("load-side coherence");

figure("Name", "Motor-side coherence", "Color", "w");
mscohere(input, motorvel, rectwin(Tcycle/Ts), 0, Tcycle/Ts, 1/Ts);
ax = gca; ax.XScale = 'log';
title("motor-side coherence");
%%
%[text] ### Manual data fitting of system $P${"editStyle":"visual"}
%[text] True system: $P=\\frac{1}{{\\textrm{Js}}^2 +\\textrm{Ds}}${"editStyle":"visual"}
%[text] Nominal system: $P\_n =\\frac{1}{{J\_n s}^2 +D\_n s}${"editStyle":"visual"}
%[text] design $J\_n${"editStyle":"visual"} and $D\_n${"editStyle":"visual"} so $P\_n${"editStyle":"visual"} becomes close to $P${"editStyle":"visual"}.
s = tf('s');
z = tf('z', Ts);

Pd_load = Pd_vel_load*c2d(1/s, Ts, 'tustin');
Pd_motor = Pd_vel_motor*c2d(1/s, Ts, 'tustin');
Pdn = c2d(1/(Jn*s+Dn)/s, Ts, 'zoh')/z^Ndelay;

bop_ = bodeoptions("cstprefs");
bop_.FreqUnits = 'Hz';
bop_.PhaseWrapping = 'on';
bop_.XLimMode = 'manual';
bop_.XLim = {[1, 1/2/Ts]};
bop_.Grid = 'off';
bop_.YLim = {[-80, 80]; [-180, 180]};
figure("Name", "Manual plant fitting", "Color", "w");
bode(Pd_load, Pd_motor, Pdn, bop_);
legend(["$P_{\mathrm{load}}$", "$P_{\mathrm{motor}}$", "$P_{n}$"], "Interpreter", "latex");
%%
%[text] save fitting data
%[text] load-side position will be the main objective of control for demo2 to demo4
Pd = Pd_load;
if save_results
  save(plant_mat_path, 'Pd', 'Pd_motor', 'Pd_load', 'Pd_vel_load', 'Pd_vel_motor', ...
    'Pdn', 'Jn', 'Dn', 'Ndelay', 'Ts', 'vm_plant', 'vm_mode');
end

fprintf("Saved chirp result: %s\n", char(chirp_result_path));
fprintf("Saved plant data for exp02-exp04: %s\n", char(plant_mat_path));
