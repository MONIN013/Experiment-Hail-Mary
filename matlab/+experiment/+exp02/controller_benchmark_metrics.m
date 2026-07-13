function row = controller_benchmark_metrics(entry, signals, varargin)
% controller_benchmark_metrics  Summarize one measured controller run.

p = inputParser;
p.addParameter("SettlingToleranceFraction", 0.02, ...
  @(x) isnumeric(x) && isreal(x) && isscalar(x) && isfinite(x) && x > 0);
p.parse(varargin{:});

entry = validate_entry(entry);
signals = validate_signals(signals);
t = signals.time_s(:);
r = signals.ref_value(:);
y = signals.position_act(:);
e = signals.error(:);
u = signals.control_input(:);
current_cmd = signals.current_cmd(:);

reference_scale = max(abs(r), [], "omitnan");
settling_tolerance = max(1e-9, ...
  double(p.Results.SettlingToleranceFraction) * reference_scale);
outside = find(abs(e) > settling_tolerance, 1, "last");
if isempty(outside)
  settling_time_s = 0;
elseif outside == numel(e)
  settling_time_s = NaN;
else
  settling_time_s = t(outside + 1) - t(1);
end

reference_max = max(r, [], "omitnan");
reference_min = min(r, [], "omitnan");
overshoot_rad = max([0; y - reference_max; reference_min - y]);

row = table( ...
  string(entry.name), string(entry.family), ...
  norm(e), sqrt(mean(e.^2)), max(abs(e), [], "omitnan"), ...
  trapz(t, abs(e)), double(overshoot_rad), double(settling_time_s), ...
  max(abs(u), [], "omitnan"), max(abs(current_cmd), [], "omitnan"), ...
  double(entry.design.max_sensitivity), ...
  double(entry.design.controller_gain_200_hz), ...
  double(entry.design.sos_section_count), logical(entry.design.gate_ok), ...
  VariableNames=["controller", "family", "trackingErrorL2", ...
    "trackingErrorRms", "trackingErrorPeak", "IAE", "overshootRad", ...
    "settlingTimeS", "maxControlInputA", "maxCurrentCmdA", ...
    "sensitivityPeak", "controllerGain200Hz", "sosSections", "gatePassed"]);
end

function entry = validate_entry(entry)
required = ["name", "family", "Kd", "controller_cfg", "design"];
if ~isstruct(entry) || ~isscalar(entry) || ~all(isfield(entry, required))
  error("experiment:exp02:invalidControllerBenchmarkEntry", ...
    "entry must be one scalar controller_catalog entry.");
end
design_fields = ["max_sensitivity", "controller_gain_200_hz", ...
  "sos_section_count", "gate_ok"];
if ~isstruct(entry.design) || ~isscalar(entry.design) || ...
    ~all(isfield(entry.design, design_fields))
  error("experiment:exp02:invalidControllerBenchmarkEntry", ...
    "entry.design is missing benchmark gate fields.");
end
end

function signals = validate_signals(signals)
required = ["time_s", "ref_value", "position_act", "error", ...
  "control_input", "current_cmd"];
if ~isstruct(signals) || ~isscalar(signals) || ~all(isfield(signals, required))
  error("experiment:exp02:invalidControllerBenchmarkSignals", ...
    "signals must contain %s.", strjoin(required, ", "));
end
counts = zeros(size(required));
for k = 1:numel(required)
  value = signals.(required(k));
  if ~(isnumeric(value) && isreal(value) && isvector(value) && ...
      all(isfinite(double(value(:)))))
    error("experiment:exp02:invalidControllerBenchmarkSignals", ...
      "signals.%s must be a finite real vector.", required(k));
  end
  counts(k) = numel(value);
end
if counts(1) < 2 || any(counts ~= counts(1))
  error("experiment:exp02:invalidControllerBenchmarkSignals", ...
    "All benchmark signals must have the same length of at least two samples.");
end
t = double(signals.time_s(:));
if any(diff(t) <= 0)
  error("experiment:exp02:invalidControllerBenchmarkSignals", ...
    "signals.time_s must be strictly increasing.");
end
end
