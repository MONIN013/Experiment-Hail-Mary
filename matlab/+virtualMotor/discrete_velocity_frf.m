function response = discrete_velocity_frf(plant_cfg, omega_rad_s, varargin)
% discrete_velocity_frf  Exact linear FRF of VirtualMotorCore Euler updates.
%
% The state transition mirrors IntegratePlant: velocities are updated from
% the old state, then positions use the new velocities (semi-implicit Euler).

arguments
  plant_cfg virtualMotor.PlantConfig
  omega_rad_s {mustBeNumeric, mustBeReal, mustBeNonnegative, mustBeFinite}
end
arguments (Repeating)
  varargin
end

p = inputParser;
p.addParameter("Ts", 1/8000, @is_positive_scalar);
p.addParameter("sample_delay", 0, @is_nonnegative_scalar);
p.addParameter("rated_current_A", 1.6, @is_positive_scalar);
p.addParameter("axis", "load", @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.parse(varargin{:});
opts = p.Results;

plant = plant_cfg.to_struct();
dt = double(opts.Ts);
jm = plant.motor.inertia;
jl = plant.load.inertia;
bm = plant.motor.damping;
bl = plant.load.damping;
ks = plant.coupling.stiffness;
ds = plant.coupling.damping;
torque_per_amp = plant.motor.ratedTorque / double(opts.rated_current_A);

motor_velocity_row = [ ...
  -dt*ks/jm, ...
  1 - dt*(ds + bm)/jm, ...
  dt*ks/jm, ...
  dt*ds/jm];
load_velocity_row = [ ...
  dt*ks/jl, ...
  dt*ds/jl, ...
  -dt*ks/jl, ...
  1 - dt*(ds + bl)/jl];
A = [ ...
  [1, 0, 0, 0] + dt*motor_velocity_row; ...
  motor_velocity_row; ...
  [0, 0, 1, 0] + dt*load_velocity_row; ...
  load_velocity_row];
B = [dt^2*torque_per_amp/jm; dt*torque_per_amp/jm; 0; 0];

axis_name = lower(string(opts.axis));
switch axis_name
  case "motor"
    selector = [0, 1, 0, 0];
  case "load"
    selector = [0, 0, 0, 1];
  otherwise
    error("virtualMotor:plant:invalidAxis", "axis must be 'motor' or 'load'.");
end
% Logger observes the state after the current Euler update.
C = selector * A;
D = selector * B;
system = ss(A, B, C, D, dt);

omega = double(omega_rad_s(:));
response_column = squeeze(freqresp(system, omega));
response_column = response_column(:);
at_dc = omega == 0;
response_column(at_dc) = torque_per_amp / (bm + bl);
response_column = response_column .* exp( ...
  -1i * omega * dt * double(opts.sample_delay));
response = reshape(response_column, size(omega_rad_s));
end

function tf = is_positive_scalar(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && double(value) > 0;
end

function tf = is_nonnegative_scalar(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && double(value) >= 0;
end
