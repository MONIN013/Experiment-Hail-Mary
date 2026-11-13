function out = higs_linear_check(plant, controller, Smax, do_plot)
% higs_linear_check  Gate a sampled linear reference using identified data.
% The finite-frequency sensitivity test is not a measured Nyquist proof.
if nargin < 4, do_plot = false; end
Ts = controller.sample_time_s;
if ~isa(plant.Pd, "frd") || ~isequal(size(plant.Pd), [1, 1]) || ...
    ~isequal(size(plant.Pdn), [1, 1]) || isa(plant.Pdn, "frd")
  error("experiment:higs:invalidPlant", "Pd must be SISO FRD and Pdn must be a SISO parametric model.");
end
if abs(plant.Ts-Ts) > 1e-12 || abs(plant.Pd.Ts-Ts) > 1e-12 || abs(plant.Pdn.Ts-Ts) > 1e-12
  error("experiment:higs:plantSampleTime", "Plant, FRD and nominal sample periods must match the controller.");
end
PdHz = chgFreqUnit(plant.Pd, "Hz");
f = PdHz.Frequency(:);
if any(~isfinite(f)) || any(f < 0) || any(diff(f) <= 0)
  error("experiment:higs:invalidFrequency", "FRD frequencies must be finite, nonnegative and increasing.");
end
positive = f > 0;
f = f(positive);
response = PdHz.ResponseData(:,:,positive);
% exp01 converts velocity to position with Ts*z/(z-1); DC is singular.
% Exclude only DC, never discard invalid positive-frequency observations.
if isempty(f) || any(~isfinite(response(:)))
  error("experiment:higs:invalidPositiveFrf", "Positive-frequency FRD must be nonempty and finite.");
end
if f(1) > 1 || f(end) < 500 || f(end) > (1/(2*Ts))*(1+1e-12)
  error("experiment:higs:insufficientFrequencyBand", ...
    "Measured FRD must cover 1-500 Hz and remain at or below Nyquist.");
end
Pd = frd(response, f, Ts, "FrequencyUnit", "Hz");
% Preserve each SOS realization; a high-order TF is ill-conditioned near z=1.
Kd = ss([], [], [], 1, Ts);
for k = 1:size(controller.sos, 1)
  row = controller.sos(k,:);
  section = ss(tf(row(1:3), row(4:6), Ts, "Variable", "z^-1"));
  Kd = section * Kd;
end
Pdn = ss(plant.Pdn);
if ~isstable(feedback(Pdn * Kd, 1))
  error("experiment:higs:unstableLinearReference", ...
    "The identified nominal closed loop is not stable with this linear reference.");
end
out = experiment.exp02.stability_check(Pd, Pdn, Kd, Smax, "Plot", do_plot);
measured = out.sensitivity.ResponseData;
if ~out.ok || any(~isfinite(measured(:)))
  error("experiment:higs:linearReferenceGateFailed", ...
    "Measured linear sensitivity is invalid or exceeds its specified limit.");
end
out.Kd = Kd;
out.dc_excluded = any(~positive);
out.frequency_band_hz = [f(1), f(end)];
end
