function capture = capture_logger_artifact(logger, entry_name, context, label)
% capture_logger_artifact  Parse and immediately copy one confirmed logger.
arguments
  logger
  entry_name {mustBeTextScalar}
  context (1, 1) struct
  label {mustBeTextScalar} = "run"
end
if isstruct(logger) && isfield(logger, "file_path")
  source_path = string(logger.file_path);
else
  source_path = string(logger);
  logger = [];
end
if strlength(source_path) == 0 || ~isfile(source_path)
  error("testoracle:logger:missingConfirmedPath", ...
    "%s %s logger path is missing or unreadable: %s.", ...
    entry_name, label, source_path);
end
parsed = experiment.read_logger_bin(source_path);
if isempty(logger)
  logger = parsed;
elseif ~isfield(logger, "raw") || ~isfield(logger, "record_count")
  error("testoracle:logger:invalidCapture", ...
    "%s %s did not return a parsed logger payload.", entry_name, label);
end
provided_digest = testoracle.canonical_digest(logger.raw);
source_digest = testoracle.canonical_digest(parsed.raw);
if double(parsed.record_count) <= 0 || ...
    double(logger.record_count) ~= double(parsed.record_count) || ...
    string(provided_digest) ~= string(source_digest)
  error("testoracle:logger:sourceMismatch", ...
    "%s %s provided/source logger count or raw digest is inconsistent.", ...
    entry_name, label);
end

directory = fullfile(string(context.campaign_directory), "loggers", ...
  safe_name(entry_name));
if ~isfolder(directory), mkdir(directory); end
destination = fullfile(directory, safe_name(label) + ".bin");
if isfile(destination)
  error("testoracle:logger:duplicateCapture", ...
    "Logger capture already exists: %s.", destination);
end
[copied, message] = copyfile(source_path, destination);
if ~copied
  error("testoracle:logger:copyFailed", ...
    "Failed to copy confirmed logger %s: %s", source_path, message);
end
copied_logger = experiment.read_logger_bin(destination);
campaign_digest = testoracle.canonical_digest(copied_logger.raw);
if double(copied_logger.record_count) ~= double(parsed.record_count) || ...
    string(campaign_digest) ~= string(source_digest)
  error("testoracle:logger:copyVerificationFailed", ...
    "Copied logger count or raw digest changed for %s %s.", entry_name, label);
end
capture = struct( ...
  "source_path", source_path, "campaign_path", string(destination), ...
  "record_count", double(copied_logger.record_count), ...
  "raw_digest", campaign_digest, ...
  "provided_raw_digest", provided_digest, ...
  "source_raw_digest", source_digest, ...
  "campaign_raw_digest", campaign_digest, ...
  "checked_immediately", true);
end

function value = safe_name(value)
value = string(matlab.lang.makeValidName(char(string(value))));
end
