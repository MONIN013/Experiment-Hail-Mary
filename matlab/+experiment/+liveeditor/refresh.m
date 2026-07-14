function report = refresh(file_path, options)
%REFRESH Transactionally refresh one rich .m Live Script in this process.
% Call this function for only one target per MATLAB process. The caller owns
% process isolation because the headless Live Editor is an internal service.
arguments
  file_path {mustBeTextScalar}
  options.backup_root {mustBeTextScalar} = ""
  options.keep_probe (1, 1) logical = false
  options.probe_executor (1, 1) function_handle = ...
    @experiment.liveeditor.structure_probe
  options.target_executor (1, 1) function_handle = ...
    @experiment.liveeditor.execute_and_save
end

file_path = absolute_path(file_path);
before_report = experiment.liveeditor.assert_refreshable(file_path);
before_signature = experiment.liveeditor.structure_signature(file_path);

backup_root = string(options.backup_root);
if backup_root == ""
  backup_root = fullfile(fileparts(file_path), "data", "_backups", ...
    "live_scripts");
end
if ~isfolder(backup_root)
  [created, message] = mkdir(backup_root);
  if ~created
    error("experiment:liveeditor:BackupDirectory", ...
      "Could not create backup directory %s: %s", backup_root, message);
  end
end

backup_path = unique_backup_path(file_path, backup_root);
copy_or_error(file_path, backup_path, "backup");

probe_path = unique_probe_path(file_path);
copy_or_error(file_path, probe_path, "probe");
probe_cleanup = onCleanup(@() delete_probe(probe_path, options.keep_probe));

probe_execution_time = options.probe_executor(probe_path);
% A source/output ID mismatch is repairable only by executeAndSave. The
% structure-only probe must accept that state; the target remains subject to
% strict validation immediately after the real execution below.
probe_report = experiment.liveeditor.assert_refreshable(probe_path);
probe_signature = experiment.liveeditor.structure_signature(probe_path);
experiment.liveeditor.assert_structure_preserved( ...
  before_signature, probe_signature, probe_path);

try
  target_execution_time = options.target_executor(file_path);
  after_report = experiment.liveeditor.assert_valid(file_path);
  after_signature = experiment.liveeditor.structure_signature(file_path);
  experiment.liveeditor.assert_structure_preserved( ...
    before_signature, after_signature, file_path);
catch cause
  restore_backup(backup_path, file_path, cause);
  rethrow(cause);
end

report = struct( ...
  "file_path", file_path, ...
  "backup_path", backup_path, ...
  "probe_path", probe_path, ...
  "probe_execution_time_s", double(probe_execution_time), ...
  "target_execution_time_s", double(target_execution_time), ...
  "before", before_report, ...
  "probe", probe_report, ...
  "after", after_report);
clear probe_cleanup;
end

function path_out = absolute_path(path_in)
path_in = string(path_in);
if ~isfile(path_in)
  error("experiment:liveeditor:MissingFile", ...
    "Rich Live Script does not exist: %s", path_in);
end
[folder, name, extension] = fileparts(path_in);
if folder == ""
  folder = string(pwd);
elseif ~is_absolute(folder)
  folder = fullfile(pwd, folder);
end
path_out = string(fullfile(folder, name + extension));
end

function tf = is_absolute(folder)
folder = char(folder);
tf = ~isempty(regexp(folder, '^[A-Za-z]:[\\/]', "once")) || ...
  startsWith(string(folder), "\\") || startsWith(string(folder), "/");
end

function backup_path = unique_backup_path(file_path, backup_root)
[~, name, extension] = fileparts(file_path);
timestamp = string(datetime("now", "Format", "yyyyMMdd'T'HHmmssSSS"));
backup_path = fullfile(backup_root, name + "_" + timestamp + extension);
suffix = 1;
while isfile(backup_path)
  backup_path = fullfile(backup_root, name + "_" + timestamp + "_" + ...
    compose("%02d", suffix) + extension);
  suffix = suffix + 1;
end
end

function probe_path = unique_probe_path(file_path)
[folder, name, extension] = fileparts(file_path);
timestamp = string(datetime("now", "Format", "yyyyMMdd'T'HHmmssSSS"));
probe_path = fullfile(folder, name + ".liveeditor_probe_" + timestamp + extension);
suffix = 1;
while isfile(probe_path)
  probe_path = fullfile(folder, name + ".liveeditor_probe_" + timestamp + ...
    "_" + compose("%02d", suffix) + extension);
  suffix = suffix + 1;
end
end

function copy_or_error(source, destination, operation)
[copied, message] = copyfile(source, destination, "f");
if ~copied
  error("experiment:liveeditor:CopyFailed", ...
    "Could not create %s copy %s: %s", operation, destination, message);
end
end

function delete_probe(probe_path, keep_probe)
if ~keep_probe && isfile(probe_path)
  delete(probe_path);
end
end

function restore_backup(backup_path, file_path, original_cause)
[restored, message] = copyfile(backup_path, file_path, "f");
if restored
  return;
end

restore_cause = MException("experiment:liveeditor:RestoreFailed", ...
  "Refresh failed and backup restoration also failed for %s: %s", ...
  file_path, message);
restore_cause = addCause(restore_cause, original_cause);
throw(restore_cause);
end
