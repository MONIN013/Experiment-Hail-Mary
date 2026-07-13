function catalog = controller_catalog(plant, varargin)
% controller_catalog  Build the supported 8 kHz SISO feedback controllers.
%
%   catalog = experiment.exp02.controller_catalog(plant)
%   catalog = experiment.exp02.controller_catalog(plant, "Smax", 2)
%
% plant is the scalar struct returned by experiment.exp0n.load_plant_data.
% Each catalog entry contains the continuous design (K), its discrete form
% (Kd), the ControllerCore SOS payload, and side-effect-free design gates.

p = inputParser;
p.addParameter("Smax", 2, ...
  @(x) isnumeric(x) && isreal(x) && isscalar(x) && isfinite(x) && x > 0);
p.parse(varargin{:});

plant = validate_plant(plant);
Smax = double(p.Results.Smax);
Ts = double(plant.Ts);
d = double(plant.Dn) / double(plant.Jn);
Kt = 1 / double(plant.Jn);
s = tf("s");

names = ["P", "PI", "filtered PD", "filtered PID", ...
  "lead", "lead-lag", "lead + 200 Hz notch"];
families = ["proportional", "integral", "derivative", "pid", ...
  "phase lead", "loop shaping", "resonance suppression"];

for k = numel(names):-1:1
  design = empty_design(Ts, Smax);
  switch names(k)
    case "P"
      design.method = "loop-shaping";
      design.target_crossover_rad_s = 10;
      K = tf(crossover_gain(plant.Pdn, tf(1), design.target_crossover_rad_s));

    case "PI"
      design.method = "repeated-pole PI";
      design.target_pole_rad_s = 4;
      K = experiment.exp02.designpi(d, 0, Kt, design.target_pole_rad_s);

    case "filtered PD"
      design.method = "repeated-pole filtered PD";
      design.target_pole_rad_s = 15;
      K = experiment.exp02.designpd(d, 0, Kt, design.target_pole_rad_s);

    case "filtered PID"
      design.method = "repeated-pole filtered PID";
      design.target_pole_rad_s = 15;
      K = experiment.exp02.designpid(d, 0, Kt, design.target_pole_rad_s);

    case "lead"
      design.method = "phase lead";
      design.target_crossover_rad_s = 15;
      design.phase_lead_deg = 45;
      alpha = (1 - sind(design.phase_lead_deg)) / ...
        (1 + sind(design.phase_lead_deg));
      tau = 1 / (design.target_crossover_rad_s * sqrt(alpha));
      K0 = (tau*s + 1) / (alpha*tau*s + 1);
      K = crossover_gain(plant.Pdn, K0, design.target_crossover_rad_s) * K0;

    case "lead-lag"
      design.method = "lead-lag loop-shaping";
      design.target_crossover_rad_s = 15;
      design.phase_lead_deg = 45;
      design.lag_zero_rad_s = design.target_crossover_rad_s / 4;
      design.lag_pole_rad_s = design.target_crossover_rad_s / 20;
      alpha = (1 - sind(design.phase_lead_deg)) / ...
        (1 + sind(design.phase_lead_deg));
      tau = 1 / (design.target_crossover_rad_s * sqrt(alpha));
      lead0 = (tau*s + 1) / (alpha*tau*s + 1);
      lag0 = (1 + s/design.lag_zero_rad_s) / ...
        (1 + s/design.lag_pole_rad_s);
      K0 = lead0 * lag0;
      K = crossover_gain(plant.Pdn, K0, design.target_crossover_rad_s) * K0;

    case "lead + 200 Hz notch"
      design.method = "phase lead with notch";
      design.target_crossover_rad_s = 15;
      design.phase_lead_deg = 45;
      design.notch_frequency_hz = 200;
      design.notch_zeta_zero = 0.02;
      design.notch_zeta_pole = 0.20;
      alpha = (1 - sind(design.phase_lead_deg)) / ...
        (1 + sind(design.phase_lead_deg));
      tau = 1 / (design.target_crossover_rad_s * sqrt(alpha));
      lead0 = (tau*s + 1) / (alpha*tau*s + 1);
      wn = 2*pi*design.notch_frequency_hz;
      notch = (s^2 + 2*design.notch_zeta_zero*wn*s + wn^2) / ...
        (s^2 + 2*design.notch_zeta_pole*wn*s + wn^2);
      K0 = lead0 * notch;
      K = crossover_gain(plant.Pdn, K0, design.target_crossover_rad_s) * K0;
  end

  Kd = c2d(K, Ts, "tustin");
  controller_cfg = experiment.controller.from_discrete_tf(Kd);
  design = assess_design(plant, Kd, controller_cfg, design);
  catalog(k) = struct( ...
    "name", names(k), ...
    "family", families(k), ...
    "K", K, ...
    "Kd", Kd, ...
    "controller_cfg", controller_cfg, ...
    "design", design);
end
end

function plant = validate_plant(plant)
if ~isstruct(plant) || ~isscalar(plant)
  error("experiment:exp02:invalidControllerCatalogPlant", ...
    "plant must be a scalar struct returned by load_plant_data.");
end
required = ["Pd", "Pdn", "Jn", "Dn", "Ts"];
missing = required(~isfield(plant, required));
if ~isempty(missing)
  error("experiment:exp02:invalidControllerCatalogPlant", ...
    "plant is missing field(s): %s.", strjoin(missing, ", "));
end
if ~(isnumeric(plant.Jn) && isreal(plant.Jn) && isscalar(plant.Jn) && ...
    isfinite(double(plant.Jn)) && double(plant.Jn) > 0)
  error("experiment:exp02:invalidControllerCatalogPlant", ...
    "plant.Jn must be a finite positive scalar.");
end
if ~(isnumeric(plant.Dn) && isreal(plant.Dn) && isscalar(plant.Dn) && ...
    isfinite(double(plant.Dn)) && double(plant.Dn) >= 0)
  error("experiment:exp02:invalidControllerCatalogPlant", ...
    "plant.Dn must be a finite nonnegative scalar.");
end
if ~(isnumeric(plant.Ts) && isreal(plant.Ts) && isscalar(plant.Ts) && ...
    isfinite(double(plant.Ts)) && double(plant.Ts) > 0)
  error("experiment:exp02:invalidControllerCatalogPlant", ...
    "plant.Ts must be a finite positive scalar.");
end
validate_discrete_siso(plant.Pdn, double(plant.Ts), "Pdn");
validate_discrete_siso(plant.Pd, double(plant.Ts), "Pd");
end

function validate_discrete_siso(system, Ts, label)
try
  [ny, nu] = size(system);
  discrete = isdt(system);
  system_ts = double(system.Ts);
catch
  error("experiment:exp02:invalidControllerCatalogPlant", ...
    "plant.%s must be a discrete SISO dynamic system.", label);
end
if ny ~= 1 || nu ~= 1 || ~discrete || ~(isfinite(system_ts) && system_ts > 0)
  error("experiment:exp02:invalidControllerCatalogPlant", ...
    "plant.%s must be a discrete SISO dynamic system.", label);
end
tolerance = max(1e-15, 32*eps(max(Ts, system_ts)));
if abs(system_ts - Ts) > tolerance
  error("experiment:exp02:invalidControllerCatalogPlant", ...
    "plant.%s sample time %.17g does not match plant.Ts %.17g.", ...
    label, system_ts, Ts);
end
end

function gain = crossover_gain(Pdn, controller_shape, crossover_rad_s)
plant_mag = response_magnitude(Pdn, crossover_rad_s);
shape_mag = response_magnitude(controller_shape, crossover_rad_s);
gain = 1 / (plant_mag * shape_mag);
if ~(isfinite(gain) && isreal(gain) && gain > 0)
  error("experiment:exp02:invalidControllerCatalogDesign", ...
    "Unable to obtain a finite positive gain at %.6g rad/s.", crossover_rad_s);
end
end

function magnitude = response_magnitude(system, frequency_rad_s)
response = squeeze(freqresp(system, frequency_rad_s));
magnitude = double(abs(response));
if ~(isscalar(magnitude) && isfinite(magnitude) && magnitude > 0)
  error("experiment:exp02:invalidControllerCatalogDesign", ...
    "Frequency response at %.6g rad/s must be finite and nonzero.", frequency_rad_s);
end
end

function design = empty_design(Ts, Smax)
design = struct( ...
  "method", "", ...
  "sample_time_s", Ts, ...
  "target_crossover_rad_s", NaN, ...
  "target_pole_rad_s", NaN, ...
  "phase_lead_deg", NaN, ...
  "lag_zero_rad_s", NaN, ...
  "lag_pole_rad_s", NaN, ...
  "notch_frequency_hz", NaN, ...
  "notch_zeta_zero", NaN, ...
  "notch_zeta_pole", NaN, ...
  "max_sensitivity_limit", Smax, ...
  "nominal_closed_loop_stable", false, ...
  "max_closed_loop_pole_magnitude", Inf, ...
  "max_sensitivity", Inf, ...
  "real_coefficients_siso", false, ...
  "proper_causal", false, ...
  "no_explicit_delay", false, ...
  "finite_sos", false, ...
  "sos_section_count", 0, ...
  "sos_section_limit", experiment.ControllerConfig.MAX_SOS_SECTIONS, ...
  "controller_gain_200_hz", NaN, ...
  "gate_ok", false, ...
  "gate_reasons", "not assessed");
end

function design = assess_design(plant, Kd, controller_cfg, design)
closed_loop = feedback(plant.Pdn * Kd, 1);
closed_loop_poles = pole(closed_loop);
design.nominal_closed_loop_stable = isstable(closed_loop);
design.max_closed_loop_pole_magnitude = max(abs(closed_loop_poles), [], "omitnan");
design.max_sensitivity = sensitivity_peak(plant.Pd, Kd, plant.Ts);
design.real_coefficients_siso = has_real_siso_coefficients(Kd);
design.proper_causal = isproper(Kd);
design.no_explicit_delay = ~hasdelay(Kd);
design.finite_sos = all(isfinite(controller_cfg.sos), "all");
design.sos_section_count = size(controller_cfg.sos, 1);
design.controller_gain_200_hz = response_magnitude(Kd, 2*pi*200);

reasons = strings(0, 1);
if ~design.nominal_closed_loop_stable
  reasons(end + 1) = "nominal closed loop is unstable";
end
if design.max_sensitivity > design.max_sensitivity_limit
  reasons(end + 1) = sprintf("sensitivity peak %.6g exceeds %.6g", ...
    design.max_sensitivity, design.max_sensitivity_limit);
end
if ~design.real_coefficients_siso
  reasons(end + 1) = "controller is not a real-coefficient SISO system";
end
if ~design.proper_causal
  reasons(end + 1) = "controller is not proper and causal";
end
if ~design.no_explicit_delay
  reasons(end + 1) = "controller contains an explicit delay";
end
if ~design.finite_sos
  reasons(end + 1) = "SOS coefficients are not finite";
end
if design.sos_section_count > design.sos_section_limit
  reasons(end + 1) = "SOS section limit exceeded";
end
design.gate_ok = isempty(reasons);
if design.gate_ok
  design.gate_reasons = "";
else
  design.gate_reasons = strjoin(reasons, "; ");
end
end

function tf_value = has_real_siso_coefficients(system)
if size(system, 1) ~= 1 || size(system, 2) ~= 1
  tf_value = false;
  return;
end
[numerator, denominator] = tfdata(tf(system), "v");
tf_value = isreal(numerator) && isreal(denominator) && ...
  all(isfinite(numerator)) && all(isfinite(denominator));
end

function peak = sensitivity_peak(Pd, Kd, Ts)
sensitivity = feedback(1, Pd * Kd);
if isa(sensitivity, "frd")
  response = sensitivity.ResponseData;
else
  frequency = logspace(log10(2*pi), log10(pi/double(Ts)), 4000);
  response = freqresp(sensitivity, frequency);
end
magnitude = abs(response(:));
magnitude = magnitude(isfinite(magnitude));
if isempty(magnitude)
  error("experiment:exp02:invalidControllerCatalogDesign", ...
    "Measured sensitivity contains no finite response values.");
end
peak = double(max(magnitude));
end
