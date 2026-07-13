function [sos, sample_time_s] = sos_from_discrete_tf(discrete_tf)
% sos_from_discrete_tf  Decompose a real discrete SISO controller into SOS rows.
try
  [n_outputs, n_inputs] = size(discrete_tf);
  is_discrete = isdt(discrete_tf);
  is_causal = isproper(discrete_tf);
  has_explicit_delay = hasdelay(discrete_tf);
catch
  error("experiment:controller:invalidController", ...
    "Controller must be a discrete real finite SISO dynamic system.");
end
if n_outputs ~= 1 || n_inputs ~= 1
  error("experiment:controller:invalidController", "Controller must be SISO.");
end
if ~is_discrete
  error("experiment:controller:invalidController", "Controller must be discrete-time.");
end
sample_time_s = double(discrete_tf.Ts);
if ~(isreal(sample_time_s) && isscalar(sample_time_s) && ...
    isfinite(sample_time_s) && sample_time_s > 0)
  error("experiment:controller:invalidController", ...
    "Controller must declare a finite positive discrete sample time.");
end
if ~is_causal
  error("experiment:controller:invalidController", "Controller must be proper and causal.");
end
if has_explicit_delay
  error("experiment:controller:invalidController", ...
    "Explicit controller delays are not supported by the SOS parameter contract.");
end

try
  [num, den] = tfdata(discrete_tf, "v");
catch cause
  error("experiment:controller:invalidController", ...
    "Unable to extract discrete controller coefficients: %s", cause.message);
end
if ~(isnumeric(num) && isreal(num) && isvector(num) && all(isfinite(double(num(:)))) && ...
    isnumeric(den) && isreal(den) && isvector(den) && all(isfinite(double(den(:)))))
  error("experiment:controller:invalidController", ...
    "Controller numerator and denominator must be finite and real.");
end
if isempty(den) || all(double(den(:)) == 0)
  error("experiment:controller:invalidController", ...
    "Controller denominator must contain a nonzero coefficient.");
end

try
  [sos, gain] = tf2sos(double(num(:).'), double(den(:).'));
catch cause
  error("experiment:controller:unsupportedController", ...
    "Unable to decompose controller into second-order sections: %s", cause.message);
end
if isempty(sos)
  sos = [double(gain), 0, 0, 1, 0, 0];
else
  if ~(isnumeric(gain) && isreal(gain) && isscalar(gain) && isfinite(double(gain)))
    error("experiment:controller:invalidController", "SOS gain must be finite and real.");
  end
  sos = double(sos);
  sos(1, 1:3) = double(gain) .* sos(1, 1:3);
end

% Centralize a0 normalization, finite checks, and the ten-section limit.
normalized = experiment.ControllerConfig.from_struct(struct( ...
  "sos", sos, "sample_time_s", sample_time_s));
sos = normalized.sos;
end
