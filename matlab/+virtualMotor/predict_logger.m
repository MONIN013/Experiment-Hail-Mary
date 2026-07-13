function out = predict_logger(cfg, plant_cfg, varargin)
% predict_logger  Predict ExperimentLogger signals for the VirtualMotor runtime.
%
% The recurrence mirrors the checked-in ControllerCore, DriverAdapter, and
% VirtualMotorCore implementations. Fixed one-cycle process-image delays are
% part of the deployed 8 kHz contract and are intentionally not estimated
% from the measured log.

arguments
  cfg experiment.ExperimentConfig
  plant_cfg
end
arguments (Repeating)
  varargin
end

p = inputParser;
p.addParameter("driver_rated_current_A", 1.6, @is_positive_scalar);
p.addParameter("driver_max_current_A", 1.6, @is_positive_scalar);
p.addParameter("initial_state", struct(), @isstruct);
p.parse(varargin{:});
opts = p.Results;

cfg = experiment.ExperimentConfig.from_varargin(cfg);
plant_cfg = virtualMotor.PlantConfig.from_struct(plant_cfg);
plant = plant_cfg.to_struct();
controller_cfg = cfg.controller.normalize();
controller_sos = controller_cfg.sos;
initial = normalize_initial_state(opts.initial_state);

repeat_count = double(cfg.repeat_count);
cmd_ref = repmat(double(cfg.ref_profile(:)), repeat_count, 1);
cmd_ff = repmat(double(cfg.ff_profile(:)), repeat_count, 1);
cmd_dist = repmat(double(cfg.dist_profile(:)), repeat_count, 1);
n = numel(cmd_ref);

ref_value = zeros(n, 1);
ff_value = zeros(n, 1);
dist_value = zeros(n, 1);
if n > 1
  % ExperimentSequencer output reaches the logger one task cycle later.
  ref_value(2:end) = cmd_ref(1:end-1);
  ff_value(2:end) = cmd_ff(1:end-1);
  dist_value(2:end) = cmd_dist(1:end-1);
end

control_input = zeros(n, 1);
current_cmd = zeros(n, 1);
error_value = zeros(n, 1);
motor_position = zeros(n, 1);
motor_velocity = zeros(n, 1);
motor_current_act = zeros(n, 1);
load_position = zeros(n, 1);
load_velocity = zeros(n, 1);

theta_m = initial.theta_motor;
omega_m = initial.omega_motor;
theta_l = initial.theta_load;
omega_l = initial.omega_load;

encoder_m = double(plant.motor.encoderResolution);
encoder_l = double(plant.load.encoderResolution);
scale_m = encoder_m / (2 * pi);
scale_l = encoder_l / (2 * pi);
offset_m_count = saturating_round(theta_m * scale_m, "int32");
offset_l_count = saturating_round(theta_l * scale_l, "int32");

sos_state = zeros(size(controller_sos, 1), 2);

dt_s = 1 / double(cfg.env.task_rate_hz);
rated_current_A = double(opts.driver_rated_current_A);
max_current_A = double(opts.driver_max_current_A);
motor_fault = false;
load_fault = false;
first_motor_fault_sample = NaN;
first_load_fault_sample = NaN;
position_saturated = false;

for k = 1:n
  % Logger sees the previous ControllerCore process image.
  if k > 1
    error_value(k) = ref_value(k - 1) - load_position(k - 1);
    y = error_value(k);
    [y, sos_state, controller_ok] = apply_sos_bank(y, controller_sos, sos_state);
    if controller_ok
      control_input(k) = finite_or_zero(y + ff_value(k - 1));
    else
      control_input(k) = 0.0;
    end

    % DriverAdapter output reaches the logger one task cycle later.
    current_cmd(k) = clamp_symmetric( ...
      control_input(k - 1) + dist_value(k - 1), max_current_A);
  end

  % Driver targetTorque reaches the VM and then returns through the VM and
  % Driver process images two logger samples after currentCmd.
  delayed_current_A = 0.0;
  if k > 2
    delayed_current_A = current_cmd(k - 2);
  end
  target_permille = saturating_round( ...
    delayed_current_A * (1000 / rated_current_A), "int16");

  if motor_fault || abs(double(target_permille)) > double(plant.motor.maxPermille)
    motor_fault = true;
    tau_motor = 0.0;
  else
    tau_request = double(target_permille) / 1000 * double(plant.motor.ratedTorque);
    if abs(tau_request) > abs(double(plant.motor.tauLimit))
      motor_fault = true;
      tau_motor = 0.0;
    else
      tau_motor = clamp_optional(tau_request, double(plant.motor.tauLimit));
    end
  end
  if motor_fault && isnan(first_motor_fault_sample)
    first_motor_fault_sample = k;
  end

  tau_shaft = double(plant.coupling.stiffness) * (theta_m - theta_l) + ...
    double(plant.coupling.damping) * (omega_m - omega_l);
  omega_m_unclamped = omega_m + dt_s * ( ...
    (tau_motor - tau_shaft - double(plant.motor.damping) * omega_m) / ...
    double(plant.motor.inertia));
  omega_l_unclamped = omega_l + dt_s * ( ...
    (tau_shaft - double(plant.load.damping) * omega_l) / ...
    double(plant.load.inertia));

  if abs(omega_m_unclamped) > abs(double(plant.motor.velLimit))
    motor_fault = true;
    if isnan(first_motor_fault_sample), first_motor_fault_sample = k; end
  end
  if abs(omega_l_unclamped) > abs(double(plant.load.velLimit))
    load_fault = true;
    if isnan(first_load_fault_sample), first_load_fault_sample = k; end
  end
  omega_m = clamp_optional(omega_m_unclamped, double(plant.motor.velLimit));
  omega_l = clamp_optional(omega_l_unclamped, double(plant.load.velLimit));
  if abs(omega_m) < 1e-9, omega_m = 0.0; end
  if abs(omega_l) < 1e-9, omega_l = 0.0; end

  theta_m = theta_m + dt_s * omega_m;
  theta_l = theta_l + dt_s * omega_l;
  tau_shaft_next = double(plant.coupling.stiffness) * (theta_m - theta_l) + ...
    double(plant.coupling.damping) * (omega_m - omega_l);
  if abs(tau_shaft_next) > abs(double(plant.load.tauLimit))
    load_fault = true;
    if isnan(first_load_fault_sample), first_load_fault_sample = k; end
  end

  motor_count_unclamped = theta_m * scale_m;
  load_count_unclamped = theta_l * scale_l;
  position_saturated = position_saturated || ...
    abs(motor_count_unclamped) > double(intmax("int32")) || ...
    abs(load_count_unclamped) > double(intmax("int32"));
  motor_count = saturating_round(motor_count_unclamped, "int32");
  load_count = saturating_round(load_count_unclamped, "int32");
  motor_velocity_count = saturating_round(omega_m * scale_m, "int32");
  load_velocity_count = saturating_round(omega_l * scale_l, "int32");
  motor_torque_permille = saturating_round( ...
    tau_motor / double(plant.motor.ratedTorque) * 1000, "int16");

  motor_position(k) = double(motor_count - offset_m_count) / scale_m;
  load_position(k) = double(load_count - offset_l_count) / scale_l;
  motor_velocity(k) = double(motor_velocity_count) / scale_m;
  load_velocity(k) = double(load_velocity_count) / scale_l;
  motor_current_act(k) = double(motor_torque_permille) * rated_current_A / 1000;
end

timestamp_ns = uint64((0:n-1)') * uint64(round(dt_s * 1e9));
raw = struct( ...
  "seq", uint32((0:n-1)'), ...
  "t_ns", timestamp_ns, ...
  "t_s", double(timestamp_ns) * 1e-9, ...
  "motor_position", motor_position, ...
  "motor_velocity", motor_velocity, ...
  "motor_current_act", motor_current_act, ...
  "load_position", load_position, ...
  "load_velocity", load_velocity, ...
  "current_cmd", current_cmd, ...
  "error", error_value, ...
  "ref_value", ref_value, ...
  "ff_value", ff_value, ...
  "dist_value", dist_value, ...
  "control_input", control_input);

out = struct( ...
  "raw", raw, ...
  "sample_count", n, ...
  "encoder_quantum_motor_rad", 1 / scale_m, ...
  "encoder_quantum_load_rad", 1 / scale_l, ...
  "driver_current_quantum_A", rated_current_A / 1000, ...
  "fault", struct( ...
    "motor", motor_fault, ...
    "load", load_fault, ...
    "first_motor_sample", first_motor_fault_sample, ...
    "first_load_sample", first_load_fault_sample), ...
  "position_saturated", logical(position_saturated), ...
  "final_state", struct( ...
    "theta_motor", theta_m, "omega_motor", omega_m, ...
    "theta_load", theta_l, "omega_load", omega_l));
end

function [y, states, ok] = apply_sos_bank(x, sos, states)
y = x;
ok = isfinite(y);
if ~ok
  y = 0.0;
  return;
end
for section_index = 1:size(sos, 1)
  row = sos(section_index, :);
  state = states(section_index, :);
  next_y = row(1) * y + state(1);
  next_state = [ ...
    row(2) * y - row(5) * next_y + state(2), ...
    row(3) * y - row(6) * next_y];
  if ~isfinite(next_y) || any(~isfinite(next_state))
    states(section_index, :) = [0.0, 0.0];
    y = 0.0;
    ok = false;
    return;
  end
  states(section_index, :) = next_state;
  y = next_y;
end
end

function y = clamp_symmetric(x, limit)
if ~isfinite(x) || ~isfinite(limit) || limit <= 0
  y = 0.0;
else
  y = min(max(x, -abs(limit)), abs(limit));
end
end

function y = clamp_optional(x, limit)
if ~isfinite(x)
  y = 0.0;
elseif ~isfinite(limit) || abs(limit) <= 0
  y = x;
else
  y = min(max(x, -abs(limit)), abs(limit));
end
end

function y = finite_or_zero(x)
if isfinite(x), y = x; else, y = 0.0; end
end

function value = saturating_round(value, type_name)
value = sign(value) .* floor(abs(value) + 0.5);
switch string(type_name)
  case "int16"
    value = min(max(value, double(intmin("int16"))), double(intmax("int16")));
  case "int32"
    value = min(max(value, double(intmin("int32"))), double(intmax("int32")));
  otherwise
    error("virtualMotor:prediction:invalidType", "Unsupported saturation type %s.", type_name);
end
end

function out = normalize_initial_state(value)
defaults = struct( ...
  "theta_motor", 0.0, "omega_motor", 0.0, ...
  "theta_load", 0.0, "omega_load", 0.0);
out = defaults;
fields = fieldnames(value);
unknown = setdiff(string(fields), string(fieldnames(defaults)));
if ~isempty(unknown)
  error("virtualMotor:prediction:invalidInitialState", ...
    "Unknown initial-state field(s): %s.", strjoin(unknown, ", "));
end
for k = 1:numel(fields)
  field = fields{k};
  scalar = double(value.(field));
  if ~isscalar(scalar) || ~isfinite(scalar)
    error("virtualMotor:prediction:invalidInitialState", ...
      "%s must be a finite scalar.", field);
  end
  out.(field) = scalar;
end
end

function tf = is_positive_scalar(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && double(value) > 0;
end
