function pred_x = simulate_position(log_i, cfg)
% Simulate load position from current using the 2-inertia VM forward model.
log_i = double(log_i(:));
sample_n = numel(log_i);
pred_x = zeros(sample_n, 1);
if sample_n == 0
  return;
end

plant = normalize_plant_cfg(cfg);
task_dt_s = 1 / double(resolve_task_rate_hz(cfg));

theta_m = 0.0;
omega_m = 0.0;
theta_l = 0.0;
omega_l = 0.0;

jm = max(0.0, plant.motor.inertia);
jl = max(0.0, plant.load.inertia);
bm = max(0.0, plant.motor.damping);
bl = max(0.0, plant.load.damping);
ks = max(0.0, plant.coupling.stiffness);
ds = max(0.0, plant.coupling.damping);
kt_abs = abs(plant.motor.ratedTorque);
tau_lim = abs(plant.motor.tauLimit);
vel_lim_motor = abs(plant.motor.velLimit);
vel_lim_load = abs(plant.load.velLimit);

if jm <= 0 || jl <= 0
  return;
end

for k = 1:sample_n
  tau_m = clamp_scalar(kt_abs * log_i(k), tau_lim);
  tau_s = ks * (theta_m - theta_l) + ds * (omega_m - omega_l);
  omega_m = clamp_scalar(omega_m + task_dt_s * ((tau_m - tau_s - bm * omega_m) / jm), vel_lim_motor);
  omega_l = clamp_scalar(omega_l + task_dt_s * ((tau_s - bl * omega_l) / jl), vel_lim_load);
  theta_m = theta_m + task_dt_s * omega_m;
  theta_l = theta_l + task_dt_s * omega_l;
  pred_x(k) = theta_l;
end
end

function plant = normalize_plant_cfg(cfg)
if isa(cfg, "virtualMotor.PlantConfig")
  plant = cfg.to_struct();
elseif isstruct(cfg) && isfield(cfg, "plant")
  plant = virtualMotor.PlantConfig.from_struct(cfg.plant).to_struct();
else
  plant = virtualMotor.PlantConfig.from_struct(cfg).to_struct();
end
end

function task_rate_hz = resolve_task_rate_hz(cfg)
if isstruct(cfg) && isfield(cfg, "task_rate_hz")
  task_rate_hz = double(cfg.task_rate_hz);
else
  task_rate_hz = double(config.SystemConfig.TASK_RATE_HZ);
end
end

function y = clamp_scalar(x, limit)
lim = abs(limit);
if lim <= 0
  y = 0.0;
elseif x > lim
  y = lim;
elseif x < -lim
  y = -lim;
else
  y = x;
end
end
