function out = independent_lsim(cfg, plant_cfg, varargin)
% independent_lsim  Independent linear discrete model with fixed VM delays.
%
% The system is assembled from a two-inertia state-space plant, the exact
% discrete SOS controller, and explicit logger/controller/driver/VM delays.
% lsim and freqresp are then used independently of predict_logger.
p = inputParser;
p.addParameter("frequency_hz", zeros(0, 1), ...
  @(x) isnumeric(x) && isreal(x) && all(isfinite(x(:))) && all(x(:) >= 0));
p.addParameter("rated_current_A", 1.6, @is_positive_scalar);
p.parse(varargin{:});

cfg = experiment.ExperimentConfig.from_varargin(cfg);
plant_cfg = virtualMotor.PlantConfig.from_struct(plant_cfg);
Ts = 1 / double(cfg.env.task_rate_hz);
[plant, matrices] = linear_plant(plant_cfg, Ts, double(p.Results.rated_current_A));
controller = sos_system(cfg.controller, Ts);
z = tf("z", Ts);
delay = 1 / z;
loop = minreal(plant * controller * delay^4, 1e-10);
denominator = 1 + loop;
system = minreal([ ...
  plant * controller * delay^5 / denominator, ...
  plant * delay^5 / denominator, ...
  plant * delay^4 / denominator], 1e-10);
system.InputName = {'ref_profile'; 'ff_profile'; 'dist_profile'};
system.OutputName = {'load_position'};

reference = repmat(double(cfg.ref_profile(:)), double(cfg.repeat_count), 1);
feedforward = repmat(double(cfg.ff_profile(:)), double(cfg.repeat_count), 1);
disturbance = repmat(double(cfg.dist_profile(:)), double(cfg.repeat_count), 1);
time_s = (0:numel(reference) - 1)' * Ts;
load_position = lsim(system, [reference, feedforward, disturbance], time_s);
frequency_hz = double(p.Results.frequency_hz(:));
if isempty(frequency_hz)
  response = zeros(1, 3, 0);
else
  response = freqresp(system, 2*pi*frequency_hz);
end

out = struct( ...
  "method", "independent discrete state-space lsim/freqresp", ...
  "system", system, ...
  "state_matrices", matrices, ...
  "time_s", time_s, ...
  "inputs", struct("ref_profile", reference, ...
    "ff_profile", feedforward, "dist_profile", disturbance), ...
  "load_position", load_position(:), ...
  "frequency_hz", frequency_hz, ...
  "frequency_response", response, ...
  "sample_delay_contract", struct( ...
    "sequencer_to_logger", 1, "error_observation", 1, ...
    "controller_to_current", 1, "current_to_plant", 2));
end

function [system, matrices] = linear_plant(plant_cfg, Ts, rated_current_A)
p = plant_cfg.to_struct();
jm = p.motor.inertia; jl = p.load.inertia;
bm = p.motor.damping; bl = p.load.damping;
ks = p.coupling.stiffness; ds = p.coupling.damping;
torque_per_amp = p.motor.ratedTorque / rated_current_A;
motor_velocity = [ ...
  -Ts*ks/jm, 1-Ts*(ds+bm)/jm, Ts*ks/jm, Ts*ds/jm];
load_velocity = [ ...
  Ts*ks/jl, Ts*ds/jl, -Ts*ks/jl, 1-Ts*(ds+bl)/jl];
A = [ ...
  [1, 0, 0, 0] + Ts*motor_velocity; motor_velocity; ...
  [0, 0, 1, 0] + Ts*load_velocity; load_velocity];
B = [Ts^2*torque_per_amp/jm; Ts*torque_per_amp/jm; 0; 0];
C = [0, 0, 1, 0] * A;
D = [0, 0, 1, 0] * B;
system = ss(A, B, C, D, Ts);
matrices = struct("A", A, "B", B, "C", C, "D", D);
end

function system = sos_system(controller, Ts)
controller = experiment.ControllerConfig.from_struct(controller);
if isempty(controller.sos)
  system = tf(1, 1, Ts);
  return;
end
system = tf(1, 1, Ts);
for row = 1:size(controller.sos, 1)
  system = system * tf(controller.sos(row, 1:3), ...
    controller.sos(row, 4:6), Ts);
end
system = minreal(system, 1e-12);
end

function tf_value = is_positive_scalar(value)
tf_value = isnumeric(value) && isscalar(value) && isfinite(value) && value > 0;
end
