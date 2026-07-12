function out = stability_check(Pd, Pdn, Kd, Smax, varargin)
% stability_check  measured/nominal loop の Nyquist と感度上限を一元確認する。

  p = inputParser;
  p.addParameter("Plot", true, @(x) islogical(x) && isscalar(x));
  p.addParameter("error_id", "experiment:exp02:sensitivityLimitExceeded", ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
  p.parse(varargin{:});
  if ~(isnumeric(Smax) && isreal(Smax) && isscalar(Smax) && isfinite(Smax) && Smax > 0)
    error("experiment:exp02:invalidStabilityConfig", "Smax must be a finite positive scalar.");
  end

  measured_loop = Pd * Kd;
  nominal_loop = Pdn * Kd;
  sensitivity = feedback(1, measured_loop);
  sensitivity_response = response_data(sensitivity);
  sensitivity_mag = squeeze(abs(sensitivity_response));
  finite_mag = sensitivity_mag(isfinite(sensitivity_mag));
  if isempty(finite_mag)
    error("experiment:exp02:invalidStabilityResult", ...
      "Measured sensitivity contains no finite response values.");
  end
  max_sensitivity = max(finite_mag);
  limit_exceeded = max_sensitivity > Smax;
  if limit_exceeded
    warning(char(string(p.Results.error_id)), ...
      "Measured sensitivity peak %.6g exceeds Smax=%.6g.", max_sensitivity, Smax);
  end

  if logical(p.Results.Plot)
    plot_stability(nominal_loop, measured_loop, sensitivity, Pd, Smax);
  end
  out = struct( ...
    "ok", ~limit_exceeded, ...
    "limit_exceeded", limit_exceeded, ...
    "measured_loop", measured_loop, ...
    "nominal_loop", nominal_loop, ...
    "sensitivity", sensitivity, ...
    "max_sensitivity", double(max_sensitivity), ...
    "Smax", double(Smax));
end

function response = response_data(system)
if isa(system, "frd")
  response = system.ResponseData;
else
  response = freqresp(system, default_frequency(system));
end
end

function frequency = default_frequency(system)
if isprop(system, "Ts") && system.Ts > 0
  upper = pi / system.Ts;
else
  upper = 2 * pi * 4000;
end
frequency = logspace(log10(2*pi), log10(upper), 2000);
end

function plot_stability(nominal_loop, measured_loop, sensitivity, Pd, Smax)
nop = nyquistoptions("cstprefs");
nop.ShowFullContour = "off";
nop.XLim = [-1.5 1];
nop.YLim = [-1.5 1];
nop.Grid = "off";
figure;
nyquist(nominal_loop, measured_loop, nop); hold on;
theta = 0:0.01:2*pi;
plot(cos(theta)/Smax - 1, sin(theta)/Smax, "k--"); hold off;
drawnow;
axes_handles = findall(gcf, "Type", "Axes");
for k = 1:numel(axes_handles)
  pbaspect(axes_handles(k), [1 1 1]);
end
legend("nominal", "frd");
title("Nyquist plot");

bop = bodeoptions("cstprefs");
bop.FreqUnits = "Hz";
bop.PhaseWrapping = "on";
bop.XLimMode = "manual";
bop.XLim = {[1, nyquist_hz(Pd)]};
bop.Grid = "off";
figure;
bodemag(sensitivity, bop); hold on;
frequency_hz = frequency_in_hz(Pd);
limit = frd(Smax * ones(numel(frequency_hz), 1), frequency_hz, "FrequencyUnit", "Hz");
bodemag(limit, bop, "k--"); hold off;
legend("frd", "Smax");
title("Sensitivity function");
end

function value = nyquist_hz(system)
if isprop(system, "Ts") && system.Ts > 0
  value = 1 / (2 * system.Ts);
else
  value = 4000;
end
end

function frequency_hz = frequency_in_hz(system)
if isa(system, "frd")
  frequency_hz = system.Frequency(:);
  if isprop(system, "FrequencyUnit") && ~strcmpi(string(system.FrequencyUnit), "Hz")
    frequency_hz = frequency_hz / (2*pi);
  end
else
  frequency_hz = logspace(0, log10(nyquist_hz(system)), 500)';
end
end
