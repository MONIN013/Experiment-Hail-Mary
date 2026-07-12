function mode = torsional_mode(plant_cfg)
% torsional_mode  Return the complex torsional mode of the two-inertia VM.

% The eigenvalue calculation uses the same continuous mechanical equations
% as VirtualMotorCore. It includes motor/load damping instead of relying on
% an undamped stiffness-only approximation.

arguments
  plant_cfg virtualMotor.PlantConfig
end

plant = plant_cfg.to_struct();
jm = plant.motor.inertia;
jl = plant.load.inertia;
bm = plant.motor.damping;
bl = plant.load.damping;
ks = plant.coupling.stiffness;
ds = plant.coupling.damping;

A = [ ...
  0, 1, 0, 0; ...
  -ks/jm, -(ds + bm)/jm, ks/jm, ds/jm; ...
  0, 0, 0, 1; ...
  ks/jl, ds/jl, -ks/jl, -(ds + bl)/jl];
poles = eig(A);
complex_poles = poles(imag(poles) > 0);
if numel(complex_poles) ~= 1
  error("virtualMotor:plant:torsionalMode", ...
    "Expected exactly one underdamped torsional pole pair, found %d.", ...
    2 * numel(complex_poles));
end

pole = complex_poles(1);
natural_rad_s = abs(pole);
mode = struct( ...
  "pole", pole, ...
  "natural_frequency_hz", natural_rad_s / (2*pi), ...
  "damped_frequency_hz", abs(imag(pole)) / (2*pi), ...
  "damping_ratio", -real(pole) / natural_rad_s);
end
