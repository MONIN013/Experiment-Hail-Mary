function result = exp05_Higs(mode, varargin)
% exp05_Higs  Preview or run one linear/HIGS comparison trial.
%   preview = exp05_Higs();                         % no ADS connection
%   linear = exp05_Higs("linear", "target_label", "bench-A");
%   integrator = exp05_Higs("integrator", "target_label", "bench-A");
% target_label is a record label only. ADS connects using cfg.env; this
% function neither selects nor verifies VM versus hardware I/O mappings.
% The repository RealMotor project is a scaffold.

if nargin < 1, mode = "preview"; end
mode = string(validatestring(mode, ["preview", "linear", "integrator", "lowpass", "both"]));
repo_root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
data_dir = experiment.scenario.default_result_dir();
p = inputParser;
p.addParameter("design_path", fullfile(repo_root, "simulations", "higs_design.json"), @is_text);
p.addParameter("plant_path", fullfile(data_dir, "plant.mat"), @is_text);
p.addParameter("result_dir", data_dir, @is_text);
p.addParameter("target_label", "", @is_text);
p.addParameter("plot", true, @(x) islogical(x) && isscalar(x));
p.parse(varargin{:});
o = p.Results;

cfg = experiment.ExperimentConfig.defaults();
design = jsondecode(fileread(o.design_path));
[linear, integrator, lowpass, both, t, reference] = prepare_design(design, cfg.env.task_rate_hz);
if numel(reference) > cfg.env.table_max_n
  error("experiment:higs:tableTooLong", "HIGS reference exceeds table_max_n.");
end
result = struct("mode", mode, "design", design, "linear", linear.to_struct(), ...
  "integrator", integrator.to_struct(), "lowpass", lowpass.to_struct(), "both", both.to_struct(), "t", t, "reference", reference, ...
  "target_label", string(o.target_label), "io_backend_verified", false, ...
  "connection_environment", cfg.env.to_struct());
if mode == "preview"
  if o.plot
    figure; plot(t, reference); xlabel("Time [s]"); ylabel("Load reference [rad]");
  end
  fprintf("Preview: %d samples, Ts=%g s, reference peak=%g rad. No ADS connection.\n", ...
    numel(reference), design.sample_time_s, max(abs(reference)));
  if isfield(design, "provenance")
    fprintf("Design source: %s\n", string(design.provenance));
  end
  fprintf("I/O mapping and encoder/current scaling are not verified by this preview.\n");
  return;
end
if strlength(strtrim(string(o.target_label))) == 0
  error("experiment:higs:targetLabelRequired", ...
    "Specify target_label for this trial; it labels records and does not select the ADS target.");
end

% Gate the measured linear reference before opening ADS. This is a linear
% commissioning check, not a nonlinear stability certificate for HIGS.
plant = experiment.exp0n.load_plant_data(o.plant_path, ...
  "expected_sample_time_s", design.sample_time_s);
stability = experiment.higs_linear_check(plant, linear, ...
  design.sensitivity_limit, o.plot);

controller = linear;
if mode == "integrator", controller = integrator; end
if mode == "lowpass", controller = lowpass; end
if mode == "both", controller = both; end
trial_root = fullfile(string(o.result_dir), "exp05");
if ~isfolder(trial_root), mkdir(trial_root); end
[~, suffix] = fileparts(tempname(trial_root));
stamp = string(datetime("now", "TimeZone", "UTC", "Format", "yyyyMMdd'T'HHmmssSSS"));
trial_dir = fullfile(trial_root, stamp + "_" + string(suffix));
[created, message] = mkdir(trial_dir);
if ~created, error("experiment:higs:resultDirectory", "%s", message); end
result_path = fullfile(trial_dir, "result.mat");
result.trial_directory = trial_dir;
result.accepted = false;
cfg = experiment.scenario.configure_run(cfg, reference, zeros(size(reference)), ...
  zeros(size(reference)), controller, "repeat_count", 1, ...
  "save_path", fullfile(trial_dir, "runner.mat"));
result.plant_path = string(o.plant_path);
result.plant = plant;
result.stability = stability;
result.config = cfg.to_struct();
save(result_path, "result");
failure_path = fullfile(trial_dir, "failure.mat");
try
collected = run_guarded(cfg, design, failure_path);
result.run = collected.run;
result.logger = collected.logger_bin;
result.safety = collected.safety;
result.input_scaling = collected.input_scaling;
result.accepted = false;
% Keep the raw result even if an acceptance check below rejects this trial.
save(result_path, "result");
if collected.safety.tripped
  error("experiment:higs:safetyTrip", ...
    "DriverAdapter safety stopped the trial (code %u). Raw result is saved.", collected.safety.code);
end
if ~collected.safety.cleanup_ok
  error("experiment:higs:cleanupFailed", ...
    "Stop/limit restoration did not complete; inspect failure.mat and active driver limits.");
end
experiment.exp0n.assert_run_contract(collected.run);
[signals, metrics] = experiment.exp02.signals_from_logger_bin( ...
  collected.logger_bin, "expected_sample_count", numel(reference));
if ~collected.run.host.done || collected.run.host.timed_out || collected.run.host.abort_requested
  error("experiment:higs:incompleteTrial", "Trial did not finish normally; raw result is saved.");
end
if any(abs(diff(signals.time_s) - design.sample_time_s) > 1e-9)
  error("experiment:higs:sampleTiming", "Logger time increments differ from the task period.");
end
raw = collected.logger_bin.raw;
physical_signals = [raw.motor_position(:); raw.motor_velocity(:); ...
  raw.load_velocity(:); raw.motor_current_act(:)];
if any(~isfinite(physical_signals))
  error("experiment:higs:invalidPhysicalSignal", "Motor/load measurements must be finite.");
end
metrics.error_rms_rad = sqrt(mean(signals.error.^2));
metrics.error_peak_rad = max(abs(signals.error));
metrics.current_peak_a = max(abs(signals.current_cmd));
metrics.command_peak_a = max(abs(signals.control_input));
metrics.measured_current_peak_a = max(abs(raw.motor_current_act));
metrics.motor_velocity_peak_rad_s = max(abs(raw.motor_velocity));
metrics.load_velocity_peak_rad_s = max(abs(raw.load_velocity));
result.signals = signals;
result.metrics = metrics;
% Post-trial acceptance includes ACTUAL current, not only the clamped command.
% This does not replace the drive's real-time overcurrent protection.
result.accepted = experiment.higs_current_accepted(metrics, design.max_current_a);
save(result_path, "result");
if ~result.accepted
  error("experiment:higs:currentCriterionExceeded", ...
    "A commanded/measured current peak is invalid or reaches %.6g A; inspect the saved result before continuing.", ...
    design.max_current_a);
end
catch cause
  if ~isfile(failure_path)
    failure = struct("identifier", string(cause.identifier), "message", string(cause.message), ...
      "target_label", result.target_label, "config", cfg.to_struct());
    save(failure_path, "failure");
  end
  rethrow(cause);
end
fprintf("%s/%s: error RMS %.6g rad, peak %.6g rad, current peak %.6g A.\n", ...
  mode, result.target_label, metrics.error_rms_rad, metrics.error_peak_rad, metrics.current_peak_a);
if o.plot
  figure;
  subplot(3,1,1); plot(signals.time_s, [reference, signals.position_act]);
  ylabel("Position [rad]"); legend("reference", "load");
  subplot(3,1,2); plot(signals.time_s, signals.error); ylabel("Error [rad]");
  subplot(3,1,3); plot(signals.time_s, signals.current_cmd);
  ylabel("Current [A]"); xlabel("Time [s]");
end
end

function [linear, integrator, lowpass, both, t, r] = prepare_design(d, rate)
required = ["tuning","sample_time_s","reference_amplitude_rad","move_time_s", ...
  "dwell_time_s","settle_time_s","sensitivity_limit","max_current_a", ...
  "max_position_rad","max_velocity_rad_s","max_twist_rad"];
if ~isstruct(d)||~isscalar(d)||any(~isfield(d,required))||~isstruct(d.tuning)
  error("experiment:higs:invalidDesign","Design JSON is missing required fields.");
end
tuning_required=["kp","integral_hz","lead_zero_hz","lead_pole_hz","lowpass_hz", ...
  "higs_lp_corner_hz","higs_i_corner_hz","higs_lp_gain","higs_i_gain"];
if any(~isfield(d.tuning,tuning_required))
  error("experiment:higs:invalidDesign","Design tuning is missing required fields.");
end
positive=["sample_time_s","reference_amplitude_rad","move_time_s","dwell_time_s", ...
  "settle_time_s","sensitivity_limit","max_current_a","max_position_rad", ...
  "max_velocity_rad_s","max_twist_rad"];
for name=positive
  v=d.(name);if ~(isnumeric(v)&&isreal(v)&&isscalar(v)&&isfinite(v)&&v>0)
    error("experiment:higs:invalidDesign","%s must be a finite positive scalar.",name);
  end
end
for name=tuning_required
  v=d.tuning.(name);if ~(isnumeric(v)&&isreal(v)&&isscalar(v)&&isfinite(v))
    error("experiment:higs:invalidDesign","tuning.%s must be a finite real scalar.",name);
  end
end
if any([d.tuning.kp,d.tuning.integral_hz,d.tuning.lead_zero_hz,d.tuning.lead_pole_hz, ...
    d.tuning.lowpass_hz,d.tuning.higs_lp_corner_hz,d.tuning.higs_i_corner_hz,d.tuning.higs_lp_gain,d.tuning.higs_i_gain]<=0) || ...
    d.tuning.lead_zero_hz>=d.tuning.lead_pole_hz
  error("experiment:higs:invalidDesign","Controller tuning values are outside their valid range.");
end
if d.reference_amplitude_rad>=d.max_position_rad|| ...
    2.1875*d.reference_amplitude_rad/d.move_time_s>=d.max_velocity_rad_s
  error("experiment:higs:trajectoryLimit","Reference position or velocity reaches a configured safety limit.");
end
Ts=d.sample_time_s;wn=2*pi*d.tuning.lowpass_hz;wi=2*pi*d.tuning.integral_hz;
wz=2*pi*d.tuning.lead_zero_hz;wp=2*pi*d.tuning.lead_pole_hz;
wcLp=2*pi*d.tuning.higs_lp_corner_hz;wcI=2*pi*d.tuning.higs_i_corner_hz;
khLp=d.tuning.higs_lp_gain;khI=d.tuning.higs_i_gain;kp=d.tuning.kp;
LPF=tf(wn^2,[1,sqrt(2)*wn,wn^2]);
lead=tf([1/wz,1],[1/wp,1]);
Hlp=tf(khLp*wcLp,[1,wcLp]);Hi=tf(khI*wcI,[1,wcI]);
Vlp=LPF/Hlp;Vi=(wi/(khI*wcI))*tf([1,wcI],[1,0]);
% Optional eq. 8.8c notch (Post) and eq. 8.14 weighting filter W_i (iPre, with W_i^-1 folded into iPost); absent fields = absent filter.
[hasNotch,notchValues]=optional_filter(d.tuning,["notch_zero_hz","notch_pole_hz","notch_zero_beta","notch_pole_beta"]);
[hasWi,wiValues]=optional_filter(d.tuning,["wi_zero_hz","wi_pole_hz","wi_zero_beta","wi_pole_beta"]);
lpPre=zeros(0,6);lpPost=experiment.controller.tustin_sos(Vlp,Ts);
p=experiment.controller.tustin_sos(kp*lead,Ts);
iPre=zeros(0,6);iPost=experiment.controller.tustin_sos(kp*lead*Vi,Ts);post=zeros(0,6);
if hasNotch
  wnz=2*pi*notchValues(1);wnp=2*pi*notchValues(2);
  post=experiment.controller.tustin_sos(tf([1,2*notchValues(3)*wnz,wnz^2],[1,2*notchValues(4)*wnp,wnp^2]),Ts);
end
if hasWi
  wwz=2*pi*wiValues(1);wwp=2*pi*wiValues(2);
  Wi=(wwp^2/wwz^2)*tf([1,2*wiValues(3)*wwz,wwz^2],[1,2*wiValues(4)*wwp,wwp^2]);
  iPre=experiment.controller.tustin_sos(Wi,Ts);
  iPost=experiment.controller.tustin_sos(kp*lead*Vi*inv(Wi),Ts);
end
hlpSos=experiment.controller.tustin_sos(Hlp,Ts);hiSos=experiment.controller.tustin_sos(Hi,Ts);
packed=[lpPre;hlpSos;lpPost;p;iPre;hiSos;iPost;post];
counts=struct("lp_pre_section_count",size(lpPre,1),"lp_post_section_count",size(lpPost,1), ...
  "p_section_count",size(p,1),"i_pre_section_count",size(iPre,1), ...
  "i_post_section_count",size(iPost,1),"post_section_count",size(post,1));
base=counts;base.sos=packed;base.sample_time_s=Ts;
base.higs_lp_gain=khLp;base.higs_lp_omega_ts=khLp*wcLp*Ts/sqrt(1+16/pi^2);
base.higs_i_gain=khI;base.higs_i_omega_ts=khI*wcI*Ts/sqrt(1+16/pi^2);
linear=experiment.ControllerConfig.from_struct(base);
base.higs_i_enabled=true;integrator=experiment.ControllerConfig.from_struct(base);
base.higs_i_enabled=false;base.higs_lp_enabled=true;lowpass=experiment.ControllerConfig.from_struct(base);
base.higs_i_enabled=true;both=experiment.ControllerConfig.from_struct(base);
for c={linear,integrator,lowpass,both},c{1}.validate_for_task_rate(rate);end
end_time=2*d.settle_time_s+2*d.move_time_s+d.dwell_time_s;
t=(0:round(end_time/Ts))'*Ts;
u_forward=min(1,max(0,(t-d.settle_time_s)/d.move_time_s));
u_return=min(1,max(0,(t-d.settle_time_s-d.move_time_s-d.dwell_time_s)/d.move_time_s));
r=d.reference_amplitude_rad*(smoothstep7(u_forward)-smoothstep7(u_return));
end

function [present,values]=optional_filter(tuning,names)
% All four fields of a filter or none; every value finite, real and positive.
have=isfield(tuning,names);
if ~any(have),present=false;values=zeros(1,4);return;end
if ~all(have)
  error("experiment:higs:invalidDesign","Filter tuning needs all of %s.",strjoin(names,", "));
end
values=zeros(1,4);
for k=1:4
  v=tuning.(names(k));
  if ~(isnumeric(v)&&isreal(v)&&isscalar(v)&&isfinite(v)&&v>0)
    error("experiment:higs:invalidDesign","tuning.%s must be a finite positive scalar.",names(k));
  end
  values(k)=v;
end
present=true;
end

function y = smoothstep7(u)
y = u.^4 .* (35 - 84*u + 70*u.^2 - 20*u.^3);
end

function tf_out = is_text(x)
tf_out = ischar(x) || (isstring(x) && isscalar(x));
end

function collected = run_guarded(cfg, design, failure_path)
% The DriverAdapter protects every scan; this callback records its latch.
state = containers.Map("KeyType", "char", "ValueType", "any");
state("owns_run") = false;
state("restore_limits") = false;
state("previous") = [];
state("tripped") = false;
state("code") = uint32(0);
state("safety_observation_valid") = false;
state("cleanup_ok") = false;
state("cleanup_error") = "";
state("input_scaling") = struct();
types = twincat_ads.AdsTransport.net_types();
prefix = "DriverAdapter_Obj1 (Module1).";
names = prefix + ["MotorParams.maxCurrentA", "SafetyLimits.maxPositionRad", ...
  "SafetyLimits.maxVelocityRadS", "SafetyLimits.maxTwistRad"];
requested = [design.max_current_a, design.max_position_rad, ...
  design.max_velocity_rad_s, design.max_twist_rad];
try
  conn = experiment.ConnectionManager.create(cfg);
  % One cleanup, with explicit captures and a nonnested cleanup function.
  cleanup = onCleanup(@() cleanup_driver_session(conn, names, state, types, cfg.reset_timeout_s));
  require_idle(conn, types);
  state("input_scaling") = read_input_scaling(conn, prefix, types);
  observe_safety([]);
  if state("tripped")
    error("experiment:higs:existingSafetyTrip", ...
      "A DriverAdapter trip remains latched (code %u). Inspect it before an explicit safety reset.", state("code"));
  end
  previous = zeros(1, numel(names));
  for k = 1:numel(names)
    previous(k) = conn.module.read_scalar(names(k), types.double);
  end
  if any(~isfinite(previous)) || any(previous < 0) || previous(1) == 0
    error("experiment:higs:invalidPreviousLimits", "Existing DriverAdapter limits must be finite and valid.");
  end
  state("previous") = previous;
  relaxed = find(previous > 0 & requested > previous, 1);
  if ~isempty(relaxed)
    error("experiment:higs:limitWouldRelaxProtection", ...
      "Requested %s=%.6g exceeds its active limit %.6g. Reduce the design limit before running.", ...
      names(relaxed), requested(relaxed), previous(relaxed));
  end
  state("owns_run") = true;
  state("restore_limits") = true;
  for k = 1:numel(names)
    conn.module.write_scalar(names(k), requested(k), types.double);
  end
  for k = 1:numel(names)
    if conn.module.read_scalar(names(k), types.double) ~= requested(k)
      error("experiment:higs:safetyReadback", "DriverAdapter limit readback failed for %s.", names(k));
    end
  end
  scaling = state("input_scaling");
  scaling.motor.maxCurrentA = conn.module.read_scalar(names(1), types.double);
  state("input_scaling") = scaling;
  run = experiment.ExperimentRunner.run(conn, cfg, "abort_condition", @observe_safety);
  observe_safety([]); % Normal runner reset does not clear the safety latch.
catch cause
  % A servo-ready/ADS error can occur before the regular abort callback.
  % Retain its original error even if this last safety observation fails.
  state("safety_observation_valid") = false;
  try
    observe_safety([]);
  catch
  end
  clear cleanup
  failure = struct("identifier", string(cause.identifier), "message", string(cause.message), ...
    "safety_trip", state("tripped"), "safety_code", state("code"), ...
    "safety_observation_valid", state("safety_observation_valid"), ...
    "cleanup_ok", state("cleanup_ok"), "cleanup_error", state("cleanup_error"), ...
    "previous_limits", state("previous"), ...
    "input_scaling", state("input_scaling"), "design", design, "config", cfg.to_struct());
  save(failure_path, "failure");
  rethrow(cause);
end
clear cleanup
collected = struct("run", run, "logger_bin", run.logger_bin, ...
  "input_scaling", state("input_scaling"), ...
  "safety", struct("tripped", state("tripped"), "code", state("code"), ...
  "observation_valid", state("safety_observation_valid"), ...
  "limits", requested, "previous_limits", state("previous"), "cleanup_ok", state("cleanup_ok")));
if ~state("cleanup_ok")
  failure = struct("identifier", "experiment:higs:cleanupFailed", ...
    "message", state("cleanup_error"), "safety_trip", state("tripped"), ...
    "safety_code", state("code"), "safety_observation_valid", state("safety_observation_valid"), ...
    "cleanup_ok", false, "cleanup_error", state("cleanup_error"), ...
    "input_scaling", state("input_scaling"), ...
    "design", design, "config", cfg.to_struct());
  save(failure_path, "failure");
end

  function abort = observe_safety(~)
    state("safety_observation_valid") = false;
    if logical(conn.module.read_scalar(prefix + "Outputs.safetyTrip", types.bool))
      state("tripped") = true;
      state("code") = uint32(conn.module.read_scalar(prefix + "Outputs.safetyCode", types.u32));
    end
    state("safety_observation_valid") = true;
    abort = state("tripped");
  end
end

function scaling = read_input_scaling(conn, prefix, types)
% Record active engineering-unit conversions; never infer them from old data.
fields = ["encoderResolution", "ratedCurrentA", "maxCurrentA", ...
  "positionSign", "velocitySign", "currentSign", "enableRelativePosition"];
field_types = {types.u32, types.double, types.double, ...
  types.i32, types.i32, types.i32, types.bool};
channels = ["MotorParams", "LoadParams"];
labels = ["motor", "load"];
scaling = struct();
for k = 1:numel(channels)
  params = struct();
  for n = 1:numel(fields)
    params.(fields(n)) = conn.module.read_scalar( ...
      prefix + channels(k) + "." + fields(n), field_types{n});
  end
  scaling.(labels(k)) = params;
end
end

function require_idle(conn, types)
if conn.ctrl.read_scalar("GVL_MODE.modeFlags", types.u16) ~= 0 || ...
    conn.ctrl.read_scalar("GVL_MODE.modeState", types.i16) ~= 0 || ...
    logical(conn.ctrl.read_scalar("GVL_MODE.experimentActive", types.bool))
  error("experiment:higs:notIdle", "Driver limits may change only in IDLE with servo disabled.");
end
end

function cleanup_driver_session(conn, names, state, types, timeout_s)
% Explicit order: servo off -> confirmed IDLE -> restore limits -> close ADS.
% Never writes SafetyResetRevision. A trip remains latched for inspection.
cleanup_error = "";
try
  if state("owns_run")
    conn.ctrl.write_scalar("GVL_MODE.modeFlags", uint16(0), types.u16);
    % Normal reset returns DONE to IDLE; it does not clear the safety latch.
    conn.ctrl.write_scalar("GVL_MODE.resetReq", true, types.bool);
    timer = tic;
    while true
      try
        require_idle(conn, types);
        break;
      catch cause
        if toc(timer) >= timeout_s, rethrow(cause); end
        pause(0.01);
      end
    end
    if state("restore_limits")
      previous = state("previous");
      for k = 1:numel(names)
        conn.module.write_scalar(names(k), previous(k), types.double);
      end
      for k = 1:numel(names)
        if conn.module.read_scalar(names(k), types.double) ~= previous(k)
          error("experiment:higs:safetyReadback", "Restored limit readback failed for %s.", names(k));
        end
      end
    end
  end
catch cause
  cleanup_error = string(cause.message);
end
try
  conn.session.close();
catch cause
  cleanup_error = cleanup_error + " ADS close: " + string(cause.message);
end
state("cleanup_ok") = strlength(cleanup_error) == 0;
state("cleanup_error") = cleanup_error;
if ~state("cleanup_ok")
  warning("experiment:higs:cleanupFailed", ...
    "Stop/limit restoration did not complete; inspect the active limits before another run: %s", cleanup_error);
end
end
