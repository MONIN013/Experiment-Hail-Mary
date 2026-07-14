function report = backup_default_artifacts(campaign_directory, matlab_root)
% backup_default_artifacts  Copy only overwrite-prone default MAT outputs.
%
% Timestamped exp04/controller run directories and historical artifacts are
% intentionally untouched. Missing default files are recorded, not created.

arguments
  campaign_directory {mustBeTextScalar}
  matlab_root {mustBeTextScalar}
end
campaign_directory = string(campaign_directory);
matlab_root = string(matlab_root);
data_directory = fullfile(matlab_root, "experiment", "data");
stamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss_SSS"));
backup_directory = fullfile(campaign_directory, "backup", stamp);
if ~isfolder(backup_directory), mkdir(backup_directory); end

names = [ ...
  "chirp_result.mat"
  "plant.mat"
  "feedback_result.mat"
  "feedforward_result.mat"
  "exp01_runner.mat"
  "exp02_runner.mat"
  "exp03_runner.mat"];
records = repmat(struct( ...
  "name", "", "source", "", "destination", "", ...
  "existed", false, "copied", false, "byte_count", 0), numel(names), 1);
for index = 1:numel(names)
  source = fullfile(data_directory, names(index));
  destination = fullfile(backup_directory, names(index));
  existed = isfile(source);
  copied = false;
  byte_count = 0;
  if existed
    [copied, message] = copyfile(source, destination, "f");
    if ~copied
      error("testoracle:backup:copyFailed", ...
        "Failed to back up %s: %s", source, message);
    end
    info = dir(destination);
    byte_count = info.bytes;
  end
  records(index) = struct( ...
    "name", names(index), "source", string(source), ...
    "destination", string(destination), "existed", existed, ...
    "copied", copied, "byte_count", byte_count);
end
report = struct( ...
  "directory", string(backup_directory), "records", records, ...
  "existing_count", nnz([records.existed]), ...
  "copied_count", nnz([records.copied]), ...
  "historical_run_directories_untouched", true);
end
