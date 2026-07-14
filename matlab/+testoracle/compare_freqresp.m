function report = compare_freqresp(actual, expected, varargin)
% compare_freqresp  Compare complex frequency samples in dB and degrees.
p = inputParser;
p.addParameter("magnitude_tolerance_db", 0.25, @valid_limit);
p.addParameter("phase_tolerance_deg", 2, @valid_limit);
p.addParameter("magnitude_p95_tolerance_db", Inf, @valid_extended_limit);
p.addParameter("phase_p95_tolerance_deg", Inf, @valid_extended_limit);
p.parse(varargin{:});
actual = double(actual(:));
expected = double(expected(:));
same_shape = isequal(size(actual), size(expected));
if same_shape && ~isempty(actual) && ...
    all(isfinite(real(actual))) && all(isfinite(imag(actual))) && ...
    all(isfinite(real(expected))) && all(isfinite(imag(expected)))
  paired_zero = abs(actual) == 0 & abs(expected) == 0;
  unpaired_zero = xor(abs(actual) == 0, abs(expected) == 0);
  ratio = ones(size(actual));
  nonzero = ~paired_zero & ~unpaired_zero;
  ratio(nonzero) = actual(nonzero)./expected(nonzero);
  ratio(unpaired_zero) = Inf;
  magnitude_error_db = 20*log10(abs(ratio));
  phase_error_deg = mod(rad2deg(angle(ratio))+180, 360)-180;
  phase_error_deg(unpaired_zero) = Inf;
  magnitude_max = max(abs(magnitude_error_db));
  phase_max = max(abs(phase_error_deg));
  magnitude_p95 = percentile(abs(magnitude_error_db), 95);
  phase_p95 = percentile(abs(phase_error_deg), 95);
else
  magnitude_error_db = Inf(size(actual));
  phase_error_deg = Inf(size(actual));
  magnitude_max = Inf;
  phase_max = Inf;
  magnitude_p95 = Inf;
  phase_p95 = Inf;
end
report = struct( ...
  "pass", logical(same_shape && ...
    magnitude_max <= p.Results.magnitude_tolerance_db && ...
    phase_max <= p.Results.phase_tolerance_deg && ...
    magnitude_p95 <= p.Results.magnitude_p95_tolerance_db && ...
    phase_p95 <= p.Results.phase_p95_tolerance_deg), ...
  "same_shape", same_shape, ...
  "magnitude_error_db", magnitude_error_db, ...
  "phase_error_deg", phase_error_deg, ...
  "magnitude_max_error_db", magnitude_max, ...
  "phase_max_error_deg", phase_max, ...
  "magnitude_p95_error_db", magnitude_p95, ...
  "phase_p95_error_deg", phase_p95, ...
  "magnitude_tolerance_db", p.Results.magnitude_tolerance_db, ...
  "phase_tolerance_deg", p.Results.phase_tolerance_deg, ...
  "magnitude_p95_tolerance_db", p.Results.magnitude_p95_tolerance_db, ...
  "phase_p95_tolerance_deg", p.Results.phase_p95_tolerance_deg);
end

function tf = valid_extended_limit(value)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
  ~isnan(value) && value >= 0;
end

function value = percentile(values, percent)
values = sort(double(values(:)));
if isempty(values), value = Inf; return; end
position = 1 + (numel(values)-1)*double(percent)/100;
lower_index = floor(position);
upper_index = ceil(position);
if lower_index == upper_index
  value = values(lower_index);
else
  weight = position-lower_index;
  value = values(lower_index)*(1-weight) + values(upper_index)*weight;
end
end

function tf = valid_limit(value)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
  isfinite(value) && value >= 0;
end
