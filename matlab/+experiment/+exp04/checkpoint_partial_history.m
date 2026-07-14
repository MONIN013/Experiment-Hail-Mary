function history = checkpoint_partial_history( ...
    file_path, history, completed_trials, stop_reason)
% checkpoint_partial_history  Save completed ILC trial data without figures.

file_path = validate_file_path(file_path);
if ~isstruct(history) || ~isscalar(history)
  error("experiment:exp04:invalidCheckpointHistory", ...
    "history must be a scalar struct.");
end
if ~(isnumeric(completed_trials) && isreal(completed_trials) && ...
    isscalar(completed_trials) && isfinite(completed_trials) && ...
    completed_trials >= 0 && fix(completed_trials) == completed_trials)
  error("experiment:exp04:invalidCheckpointTrialCount", ...
    "completed_trials must be a nonnegative integer scalar.");
end
if ~((isstring(stop_reason) && isscalar(stop_reason)) || ...
    (ischar(stop_reason) && isrow(stop_reason)))
  error("experiment:exp04:invalidCheckpointStopReason", ...
    "stop_reason must be a character vector or string scalar.");
end

history = trim_completed_trials(history, double(completed_trials));
history.completedTrials = double(completed_trials);
history.stopReason = string(stop_reason);
history.trialSummary = build_trial_summary(history, double(completed_trials));

parent_dir = fileparts(file_path);
if strlength(parent_dir) == 0
  parent_dir = string(pwd);
end
if ~isfolder(parent_dir)
  mkdir(parent_dir);
end

temporary_path = string(tempname(parent_dir)) + ".mat";
temporary_cleanup = onCleanup(@() delete_if_present(temporary_path));
save(temporary_path, "history");
[moved, message] = movefile(temporary_path, file_path, "f");
if ~moved
  error("experiment:exp04:checkpointWriteFailed", ...
    "Failed to publish partial ILC checkpoint '%s': %s", file_path, message);
end
end

function file_path = validate_file_path(value)
if ~((isstring(value) && isscalar(value)) || ...
    (ischar(value) && isrow(value)))
  error("experiment:exp04:invalidCheckpointPath", ...
    "file_path must be a character vector or string scalar.");
end
file_path = string(value);
if strlength(strtrim(file_path)) == 0
  error("experiment:exp04:invalidCheckpointPath", ...
    "file_path must not be empty.");
end
end

function history = trim_completed_trials(history, completed_trials)
matrix_fields = ["r", "y", "e", "f", "ffApplied", "u"];
vector_fields = ["eNorm", "maxAbsInput", "maxAbsFeedforward", ...
  "maxAbsTotalInput", "maxAbsError", "errorIncreased", "convergencePeak", ...
  "trialLoggerRecordCount"];

for field_name = matrix_fields
  if ~isfield(history, field_name)
    continue;
  end
  values = history.(field_name);
  if ~isnumeric(values) && ~islogical(values)
    error("experiment:exp04:invalidCheckpointHistory", ...
      "history.%s must be numeric or logical.", field_name);
  end
  if size(values, 2) < completed_trials
    error("experiment:exp04:checkpointTrialCountMismatch", ...
      "history.%s contains fewer than %d completed trials.", ...
      field_name, completed_trials);
  end
  history.(field_name) = values(:, 1:completed_trials);
end

for field_name = vector_fields
  if ~isfield(history, field_name)
    continue;
  end
  values = history.(field_name);
  if (~isnumeric(values) && ~islogical(values)) || ~isvector(values)
    error("experiment:exp04:invalidCheckpointHistory", ...
      "history.%s must be a numeric or logical vector.", field_name);
  end
  if numel(values) < completed_trials
    error("experiment:exp04:checkpointTrialCountMismatch", ...
      "history.%s contains fewer than %d completed trials.", ...
      field_name, completed_trials);
  end
  history.(field_name) = reshape(values(1:completed_trials), 1, []);
end

if isfield(history, "trialLoggerPaths")
  values = string(history.trialLoggerPaths);
  if numel(values) < completed_trials
    error("experiment:exp04:checkpointTrialCountMismatch", ...
      "history.trialLoggerPaths contains fewer than %d completed trials.", ...
      completed_trials);
  end
  history.trialLoggerPaths = reshape(values(1:completed_trials), 1, []);
end
end

function summary = build_trial_summary(history, completed_trials)
required_fields = ["eNorm", "maxAbsInput", "errorIncreased", "convergencePeak"];
if completed_trials == 0 || ~all(isfield(history, required_fields))
  summary = table( ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), false(0, 1), zeros(0, 1), false(0, 1), ...
    VariableNames=["trial", "errorNorm", "maxAbsError", ...
      "maxAbsInputA", "maxAbsFeedforwardA", "maxAbsTotalInputA", ...
      "errorIncreased", "convergencePeak", "convergenceSatisfied"]);
  return;
end

max_abs_error = history_value(history, "maxAbsError", completed_trials, NaN);
max_abs_feedforward = history_value( ...
  history, "maxAbsFeedforward", completed_trials, NaN);
max_abs_total_input = history_value( ...
  history, "maxAbsTotalInput", completed_trials, history.maxAbsInput);
summary = table( ...
  (1:completed_trials)', history.eNorm(:), max_abs_error(:), ...
  history.maxAbsInput(:), max_abs_feedforward(:), max_abs_total_input(:), ...
  logical(history.errorIncreased(:)), history.convergencePeak(:), ...
  history.convergencePeak(:) < 1, ...
  VariableNames=["trial", "errorNorm", "maxAbsError", ...
    "maxAbsInputA", "maxAbsFeedforwardA", "maxAbsTotalInputA", ...
    "errorIncreased", "convergencePeak", "convergenceSatisfied"]);
end

function values = history_value(history, field_name, count, fallback)
if isfield(history, field_name)
  values = history.(field_name)(1:count);
elseif isscalar(fallback)
  values = repmat(fallback, 1, count);
else
  values = fallback(1:count);
end
end

function delete_if_present(file_path)
if isfile(file_path)
  delete(file_path);
end
end
