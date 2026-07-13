function capture = archive_logger(logger_bin, destination)
% archive_logger  Preserve and re-parse one runner-confirmed logger binary.

arguments
  logger_bin (1, 1) struct
  destination {mustBeTextScalar}
end
required = ["file_path", "record_count", "raw", "table"];
if ~all(isfield(logger_bin, required))
  error("experiment:exp0n:invalidLoggerArchive", ...
    "logger_bin must contain file_path, record_count, raw, and table.");
end
source = string(logger_bin.file_path);
destination = string(destination);
if strlength(source) == 0 || ~isfile(source)
  error("experiment:exp0n:missingLoggerArchiveSource", ...
    "Runner-confirmed logger is missing: %s", source);
end
if strlength(destination) == 0 || isfile(destination)
  error("experiment:exp0n:invalidLoggerArchiveDestination", ...
    "Logger archive destination must be nonempty and unused: %s", destination);
end
parent = fileparts(destination);
if strlength(parent) > 0 && ~isfolder(parent)
  mkdir(parent);
end

[copied, message] = copyfile(source, destination);
if ~copied
  error("experiment:exp0n:loggerArchiveCopyFailed", ...
    "Failed to archive runner-confirmed logger: %s", string(message));
end
try
  archived = experiment.read_logger_bin(destination);
catch cause
  delete_if_present(destination);
  rethrow(cause);
end
if double(archived.record_count) ~= double(logger_bin.record_count) || ...
    ~isequaln(archived.raw, logger_bin.raw) || ...
    ~isequaln(archived.table, logger_bin.table)
  delete_if_present(destination);
  error("experiment:exp0n:loggerArchiveVerificationFailed", ...
    "Archived logger differs from the completed run payload.");
end
capture = struct("path", destination, ...
  "record_count", double(archived.record_count));
end

function delete_if_present(file_path)
if isfile(file_path)
  delete(file_path);
end
end
