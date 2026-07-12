function [signals, metrics] = signals_from_logger_bin(logger_bin, varargin)
% signals_from_logger_bin  Extract feedback signals and basic metrics.
p = inputParser;
p.addParameter("expected_sample_count", [], ...
  @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && floor(x) == x));
p.parse(varargin{:});

if ~isstruct(logger_bin) || ~isfield(logger_bin, "raw") || ~isstruct(logger_bin.raw)
  error("experiment:exp02:invalidLogger", "logger_bin.raw is required.");
end
raw = logger_bin.raw;
required = ["t_s", "ref_value", "load_position", "error", "control_input", "current_cmd"];
missing_fields = required(~isfield(raw, required));
if ~isempty(missing_fields)
  error("experiment:exp02:invalidLogger", ...
    "logger raw is missing field(s): %s.", strjoin(missing_fields, ", "));
end
t_log = raw.t_s(:);
if ~isempty(t_log)
  t_log = t_log - t_log(1);
end

signals = struct( ...
  "time_s", t_log, ...
  "ref_value", raw.ref_value(:), ...
  "position_act", raw.load_position(:), ...
  "error", raw.error(:), ...
  "control_input", raw.control_input(:), ...
  "current_cmd", raw.current_cmd(:));

counts = structfun(@numel, signals);
if any(counts ~= counts(1))
  error("experiment:exp02:loggerLengthMismatch", ...
    "Logger feedback signal lengths must match; got [%s].", strjoin(string(counts), ", "));
end
expected_count = p.Results.expected_sample_count;
if ~isempty(expected_count) && counts(1) ~= expected_count
  error("experiment:exp02:loggerLengthMismatch", ...
    "Expected %d logger samples, got %d.", expected_count, counts(1));
end
all_values = [signals.time_s; signals.ref_value; signals.position_act; ...
  signals.error; signals.control_input; signals.current_cmd];
if any(~isfinite(double(all_values)))
  error("experiment:exp02:nonfiniteLoggerSignal", ...
    "Logger feedback signals must be finite.");
end

metrics = struct( ...
  "tracking_error_l2", norm(signals.error), ...
  "max_abs_error", max(abs(signals.error), [], "omitnan"), ...
  "max_abs_control_input", max(abs(signals.control_input), [], "omitnan"));
end
