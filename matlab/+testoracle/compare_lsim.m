function report = compare_lsim(actual, independent, varargin)
% compare_lsim  Compare all samples index-to-index without fitted shifting.
p = inputParser;
p.addParameter("nrmse_limit", 0.01, @is_nonnegative_scalar);
p.addParameter("max_lag_samples", 8, @is_nonnegative_integer);
p.addParameter("required_lag_samples", 0, @is_integer_scalar);
p.parse(varargin{:});

actual = extract_position(actual);
expected = double(independent.load_position(:));
same_count = numel(actual) == numel(expected);
if same_count && ~isempty(expected)
  error_signal = actual - expected;
  denominator = max(norm(expected - mean(expected)), ...
    sqrt(numel(expected)) * eps(max(1, max(abs(expected)))));
  nrmse = norm(error_signal) / denominator;
  diagnostic_best_lag = find_best_lag( ...
    actual, expected, double(p.Results.max_lag_samples));
  finite = all(isfinite(actual));
else
  nrmse = Inf;
  diagnostic_best_lag = NaN;
  finite = all(isfinite(actual));
end
required_lag = double(p.Results.required_lag_samples);
comparison_lag = 0;
report = struct( ...
  "pass", same_count && finite && nrmse <= p.Results.nrmse_limit && ...
    comparison_lag == required_lag, ...
  "same_count", same_count, "finite", finite, ...
  "nrmse", nrmse, "nrmse_limit", double(p.Results.nrmse_limit), ...
  "comparison_lag_samples", comparison_lag, ...
  "required_lag_samples", required_lag, ...
  "diagnostic_best_lag_samples", diagnostic_best_lag, ...
  "diagnostic_alignment_signal", "diff(load_position)");
end

function value = extract_position(value)
if isstruct(value) && isfield(value, "raw"), value = value.raw; end
if isstruct(value) && isfield(value, "load_position")
  value = value.load_position;
end
if ~(isnumeric(value) && isreal(value) && isvector(value))
  error("testoracle:lsim:invalidActual", ...
    "Actual load_position must be a real numeric vector.");
end
value = double(value(:));
end

function best_lag = find_best_lag(actual, expected, maximum)
% Position offsets and quantized low-frequency drift must not decide a
% one-sample transport contract. First differences expose the dynamic
% alignment while retaining the exact sample grid.
if numel(actual) >= 2 && numel(expected) >= 2
  actual = diff(actual);
  expected = diff(expected);
end
scores = Inf(2*maximum + 1, 1);
lags = (-maximum:maximum)';
for index = 1:numel(lags)
  lag = lags(index);
  if lag < 0
    lhs = actual(1-lag:end);
    rhs = expected(1:end+lag);
  elseif lag > 0
    lhs = actual(1:end-lag);
    rhs = expected(1+lag:end);
  else
    lhs = actual;
    rhs = expected;
  end
  if ~isempty(lhs)
    scores(index) = norm(lhs-rhs)/sqrt(numel(lhs));
  end
end
minimum = min(scores);
tolerance = 16*eps(max(1, abs(minimum)));
candidates = find(scores <= minimum+tolerance);
[~, nearest_zero] = min(abs(lags(candidates)));
best_lag = lags(candidates(nearest_zero));
end

function tf_value = is_nonnegative_scalar(value)
tf_value = isnumeric(value) && isscalar(value) && isfinite(value) && value >= 0;
end
function tf_value = is_nonnegative_integer(value)
tf_value = is_nonnegative_scalar(value) && fix(value) == value;
end
function tf_value = is_integer_scalar(value)
tf_value = isnumeric(value) && isscalar(value) && isfinite(value) && ...
  fix(value) == value;
end
