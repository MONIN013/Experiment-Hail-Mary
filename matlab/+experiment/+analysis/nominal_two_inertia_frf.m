function frf_nominal = nominal_two_inertia_frf(plant_cfg, omega_rad_s, varargin)
% nominal_two_inertia_frf  Analysis-only two-inertia plant FRF.
parser = inputParser;
parser.addParameter("Ts", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
parser.addParameter("sample_delay", 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
parser.addParameter("rated_current_A", 1.6, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
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
torque_per_amp = plant.motor.ratedTorque / double(args.rated_current_A);
frf_nominal = torque_per_amp .* c ./ den;

sample_delay = double(args.sample_delay);
if sample_delay > 0
  if isempty(args.Ts)
    error("experiment:analysis:invalidConfig", ...
      "Ts is required when sample_delay is nonzero.");
  end
  frf_nominal = frf_nominal .* exp(-s * args.Ts * sample_delay);
end
end
