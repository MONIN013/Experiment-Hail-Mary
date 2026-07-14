function report = update_matlab_project(project_file, options)
%UPDATE_MATLAB_PROJECT Synchronize MATLAB Project metadata with the repository.
%   REPORT = UPDATE_MATLAB_PROJECT() adds missing managed source entries,
%   removes stale entries, applies the project classification contract, and
%   limits ProjectPath to the MATLAB root plus experiment entry scripts.
%
%   REPORT = UPDATE_MATLAB_PROJECT(PROJECT_FILE, VerifyOnly=true) validates
%   the saved project without changing it. Project metadata is changed only
%   through the public matlab.project API.

arguments
  project_file (1, 1) string = ""
  options.VerifyOnly (1, 1) logical = false
end

original_path = path;
path_cleanup = onCleanup(@() path(original_path));
tool_file = mfilename("fullpath");
matlab_root = fileparts(fileparts(tool_file));
if strlength(project_file) == 0
  project_file = fullfile(matlab_root, "ExperimentHailMary.prj");
end
project_file = absolute_existing_file(project_file);

[project, opened_here] = open_target_project(project_file);
cleanup = onCleanup(@() close_if_owned(project, opened_here));
% Keep the manual-tool bootstrap contract without pre-populating ProjectPath
% before openProject (which would emit a misleading path ownership warning).
addpath(matlab_root, fullfile(matlab_root, "experiment"));

matlab_root = char(project.RootFolder);
expected = collect_expected_entries(matlab_root);
classification = resolve_classification_contract(project);
changes = empty_change_summary();

if ~options.VerifyOnly
  repository_root = fileparts(matlab_root);
  staged_before = git_staged_paths(repository_root);
  try
    [project, changes] = synchronize_entries(project, expected, changes);
    changes = synchronize_project_path(project, matlab_root, changes);
    changes = clear_execution_files(project, changes);
    changes = synchronize_classifications(project, expected, classification, changes);

    % Force the just-written multi-file metadata to be read again before the
    % result is accepted. Startup and shutdown lists are empty, so reload has
    % no project-defined execution side effects.
    reload(project);
  catch error_info
    restore_newly_staged_sources(repository_root, matlab_root, staged_before);
    rethrow(error_info);
  end
  changes.source_index_entries_restored = restore_newly_staged_sources( ...
    repository_root, matlab_root, staged_before);
end

report = validate_project(project, expected, classification);
report.project_file = project_file;
report.verify_only = options.VerifyOnly;
report.changes = changes;

if options.VerifyOnly
  fprintf("MATLAB Project verification passed: %d entries, %d files.\n", ...
    report.entry_count, report.file_count);
else
  fprintf(['MATLAB Project synchronized: +%d -%d, %d classifications, ' ...
    '%d path changes, %d execution-file removals, %d source index restorations.\n'], ...
    changes.entries_added, changes.entries_removed, ...
    changes.classifications_changed, changes.paths_changed, ...
    changes.execution_files_removed, changes.source_index_entries_restored);
end
end

function project_file = absolute_existing_file(project_file)
project_file = char(project_file);
info = dir(project_file);
if isempty(info) || info(1).isdir
  error("project:update:projectMissing", ...
    "MATLAB Project file does not exist: %s", project_file);
end
project_file = string(fullfile(info(1).folder, info(1).name));
end

function [project, opened_here] = open_target_project(project_file)
try
  loaded = currentProject;
  opened_here = false;
catch error_info
  if error_info.identifier ~= "MATLAB:project:api:NoProjectCurrentlyLoaded"
    rethrow(error_info);
  end
  loaded = [];
  opened_here = true;
end
if opened_here
  project_root = string(fileparts(project_file));
  remove_existing_path_entries([project_root; ...
    string(fullfile(project_root, "experiment"))]);
  project = openProject(project_file);
  return;
end

expected_root = string(fileparts(project_file));
if path_key(loaded.RootFolder) ~= path_key(expected_root)
  error("project:update:differentProjectLoaded", ...
    "Close the currently loaded project before updating %s.", project_file);
end
project = loaded;
end

function remove_existing_path_entries(folders)
current_entries = split(string(path), pathsep);
current_keys = path_key(current_entries);
for idx = 1:numel(folders)
  if any(current_keys == path_key(folders(idx)))
    rmpath(folders(idx));
  end
end
end

function close_if_owned(project, opened_here)
if opened_here && isvalid(project)
  close(project);
end
end

function entries = collect_expected_entries(matlab_root)
entries = table(strings(0, 1), false(0, 1), strings(0, 1), ...
  'VariableNames', {'Path', 'IsFolder', 'Classification'});

managed_folders = [ ...
  "+config"
  "+experiment"
  "+testoracle"
  "+twincat_ads"
  "+virtualMotor"
  "experiment"
  "resources"
  "tests"
  "tools"
];

for idx = 1:numel(managed_folders)
  folder = fullfile(matlab_root, managed_folders(idx));
  if ~isfolder(folder)
    error("project:update:managedFolderMissing", ...
      "Managed MATLAB folder is missing: %s", folder);
  end
  entries = append_entry(entries, folder, true, "");

  listing = dir(fullfile(folder, "**", "*"));
  for item_idx = 1:numel(listing)
    item = listing(item_idx);
    if item.name == "." || item.name == ".."
      continue;
    end
    full_path = fullfile(item.folder, item.name);
    if is_excluded_project_entry(full_path, matlab_root)
      continue;
    end
    if item.isdir
      classification = "";
    else
      classification = expected_classification(full_path, matlab_root);
    end
    entries = append_entry(entries, full_path, item.isdir, classification);
  end
end

root_files = [ ...
  ".gitattributes"
  ".gitignore"
  "README.md"
  "setup_matlab_environment.m"
];
for idx = 1:numel(root_files)
  full_path = fullfile(matlab_root, root_files(idx));
  if ~isfile(full_path)
    error("project:update:rootFileMissing", ...
      "Required MATLAB root file is missing: %s", full_path);
  end
  entries = append_entry(entries, full_path, false, ...
    expected_classification(full_path, matlab_root));
end

[~, unique_idx] = unique(path_key(entries.Path), "stable");
entries = entries(unique_idx, :);
end

function entries = append_entry(entries, full_path, is_folder, classification)
entries(end + 1, :) = {string(full_path), logical(is_folder), string(classification)};
end

function tf = is_excluded_project_entry(full_path, matlab_root)
excluded_roots = [ ...
  string(fullfile(matlab_root, "resources", "project"))
  string(fullfile(matlab_root, "experiment", "data"))
];
key = path_key(full_path);
excluded_files = path_key(fullfile(matlab_root, "+config", ...
  "LocalEnvironmentConfig.m"));
tf = key == excluded_files;
for idx = 1:numel(excluded_roots)
  excluded_key = path_key(excluded_roots(idx));
  tf = tf || key == excluded_key || startsWith(key, excluded_key + filesep);
end
end

function classification = expected_classification(full_path, matlab_root)
relative_path = relative_to_root(full_path, matlab_root);
if relative_path == "setup_matlab_environment.m" || ...
    startsWith(relative_path, "tools" + filesep)
  classification = "convenience";
elseif startsWith(relative_path, "tests" + filesep)
  classification = "test";
else
  classification = "design";
end
end

function relative_path = relative_to_root(full_path, root)
full_path = string(full_path);
root = string(root);
if path_key(full_path) == path_key(root)
  relative_path = ".";
  return;
end
relative_path = extractAfter(full_path, strlength(root) + 1);
relative_path = replace(relative_path, ["/", "\"], filesep);
end

function [project, changes] = synchronize_entries(project, expected, changes)
expected_keys = path_key(expected.Path);
existing = project.Files;
existing_paths = project_file_paths(existing);
existing_keys = path_key(existing_paths);

remove_idx = find(~ismember(existing_keys, expected_keys));
[~, order] = sort(strlength(existing_paths(remove_idx)), "descend");
remove_idx = remove_idx(order);
for idx = remove_idx(:)'
  removeFile(project, existing(idx));
  changes.entries_removed = changes.entries_removed + 1;
end

existing_keys = path_key(project_file_paths(project.Files));
missing_idx = find(~ismember(expected_keys, existing_keys));
[~, order] = sort(strlength(expected.Path(missing_idx)), "ascend");
missing_idx = missing_idx(order);
for idx = missing_idx(:)'
  addFile(project, expected.Path(idx));
  changes.entries_added = changes.entries_added + 1;
end
end

function changes = synchronize_project_path(project, matlab_root, changes)
desired = [string(matlab_root); string(fullfile(matlab_root, "experiment"))];
desired_keys = path_key(desired);

current = project_path_files(project.ProjectPath);
current_keys = path_key(current);
for idx = find(~ismember(current_keys, desired_keys)).'
  removePath(project, current(idx));
  changes.paths_changed = changes.paths_changed + 1;
end

current_keys = path_key(project_path_files(project.ProjectPath));
for idx = find(~ismember(desired_keys, current_keys)).'
  addPath(project, desired(idx));
  changes.paths_changed = changes.paths_changed + 1;
end
end

function changes = clear_execution_files(project, changes)
startup_files = string(project.StartupFiles(:));
for idx = 1:numel(startup_files)
  removeStartupFile(project, startup_files(idx));
  changes.execution_files_removed = changes.execution_files_removed + 1;
end

shutdown_files = string(project.ShutdownFiles(:));
for idx = 1:numel(shutdown_files)
  removeShutdownFile(project, shutdown_files(idx));
  changes.execution_files_removed = changes.execution_files_removed + 1;
end
end

function changes = synchronize_classifications(project, expected, contract, changes)
files = project.Files;
paths = project_file_paths(files);
keys = path_key(paths);

for idx = 1:height(expected)
  project_idx = find(keys == path_key(expected.Path(idx)), 1);
  if isempty(project_idx)
    error("project:update:fileNotRegistered", ...
      "Project entry was not registered: %s", expected.Path(idx));
  end

  project_file = files(project_idx);
  labels = classification_labels(project_file, contract.category);
  if expected.IsFolder(idx)
    expected_label = "";
  else
    expected_label = contract.(expected.Classification(idx));
  end
  current_labels = label_names(labels);
  if numel(current_labels) == double(strlength(expected_label) > 0) && ...
      (isempty(current_labels) || current_labels == expected_label)
    continue;
  end

  for label_idx = 1:numel(labels)
    removeLabel(project_file, labels(label_idx));
  end
  if strlength(expected_label) > 0
    addLabel(project_file, contract.category, expected_label);
  end
  changes.classifications_changed = changes.classifications_changed + 1;
end
end

function report = validate_project(project, expected, contract)
project_files = project.Files;
actual_paths = project_file_paths(project_files);
actual_keys = path_key(actual_paths);
expected_keys = path_key(expected.Path);

missing = expected.Path(~ismember(expected_keys, actual_keys));
extra = actual_paths(~ismember(actual_keys, expected_keys));
if ~isempty(missing) || ~isempty(extra)
  error("project:update:entryMismatch", ...
    "Project entry mismatch.%s%s", ...
    format_path_list(" Missing: ", missing), ...
    format_path_list(" Extra: ", extra));
end

for idx = 1:numel(actual_paths)
  if ~isfile(actual_paths(idx)) && ~isfolder(actual_paths(idx))
    error("project:update:missingEntry", ...
      "Registered project entry does not exist: %s", actual_paths(idx));
  end
end

desired_paths = [string(project.RootFolder); ...
  string(fullfile(project.RootFolder, "experiment"))];
actual_project_paths = project_path_files(project.ProjectPath);
if ~isequal(sort(path_key(actual_project_paths)), sort(path_key(desired_paths)))
  error("project:update:pathMismatch", ...
    "ProjectPath must contain only the MATLAB root and experiment folder.");
end
if ~isempty(project.StartupFiles) || ~isempty(project.ShutdownFiles)
  error("project:update:executionFilesPresent", ...
    "Project startup and shutdown file lists must be empty.");
end

classification_counts = struct("design", 0, "test", 0, "convenience", 0);
for idx = 1:height(expected)
  project_idx = find(actual_keys == expected_keys(idx), 1);
  project_file = project_files(project_idx);
  labels = label_names(classification_labels(project_file, contract.category));
  if expected.IsFolder(idx)
    expected_label = "";
  else
    expected_label = contract.(expected.Classification(idx));
    field = char(expected.Classification(idx));
    classification_counts.(field) = classification_counts.(field) + 1;
  end
  if strlength(expected_label) == 0
    matches = isempty(labels);
  else
    matches = isscalar(labels) && labels == expected_label;
  end
  if ~matches
    error("project:update:classificationMismatch", ...
      "Unexpected classification for project entry: %s", expected.Path(idx));
  end
end

report = struct( ...
  "valid", true, ...
  "entry_count", height(expected), ...
  "file_count", nnz(~expected.IsFolder), ...
  "folder_count", nnz(expected.IsFolder), ...
  "classification_counts", classification_counts, ...
  "classification_names", contract, ...
  "project_paths", relative_project_paths(actual_project_paths, project.RootFolder), ...
  "startup_file_count", numel(project.StartupFiles), ...
  "shutdown_file_count", numel(project.ShutdownFiles));
end

function contract = resolve_classification_contract(project)
categories = project.Categories;
category_names = strings(1, numel(categories));
for idx = 1:numel(categories)
  category_names(idx) = string(categories(idx).Name);
end
category_name = resolve_alias(category_names, ["分類", "Classification"], ...
  "classification category");
category = categories(find(category_names == category_name, 1));

definitions = category.LabelDefinitions;
definition_names = strings(1, numel(definitions));
for idx = 1:numel(definitions)
  definition_names(idx) = string(definitions(idx).Name);
end
contract = struct( ...
  "category", category_name, ...
  "design", resolve_alias(definition_names, ["設計", "Design"], "Design label"), ...
  "test", resolve_alias(definition_names, ["テスト", "Test"], "Test label"), ...
  "convenience", resolve_alias(definition_names, ["簡易", "Convenience"], ...
    "Convenience label"));
end

function value = resolve_alias(available, aliases, description)
for idx = 1:numel(aliases)
  match = find(strcmpi(available, aliases(idx)), 1);
  if ~isempty(match)
    value = available(match);
    return;
  end
end
error("project:update:classificationUnavailable", ...
  "MATLAB Project does not define the required %s.", description);
end

function labels = classification_labels(project_file, category_name)
all_labels = project_file.Labels;
keep = false(size(all_labels));
for idx = 1:numel(all_labels)
  keep(idx) = string(all_labels(idx).CategoryName) == category_name;
end
labels = all_labels(keep);
end

function names = label_names(labels)
names = strings(1, numel(labels));
for idx = 1:numel(labels)
  names(idx) = string(labels(idx).Name);
end
end

function paths = project_file_paths(files)
paths = strings(numel(files), 1);
for idx = 1:numel(files)
  paths(idx) = string(files(idx).Path);
end
end

function paths = project_path_files(path_folders)
paths = strings(numel(path_folders), 1);
for idx = 1:numel(path_folders)
  paths(idx) = string(path_folders(idx).File);
end
end

function relative = relative_project_paths(paths, root)
relative = strings(size(paths));
for idx = 1:numel(paths)
  relative(idx) = relative_to_root(paths(idx), root);
end
relative = sort(relative);
end

function key = path_key(value)
key = replace(string(value), ["/", "\"], filesep);
if ispc
  key = lower(key);
end
end

function paths = git_staged_paths(repository_root)
command = sprintf('git -C "%s" -c core.quotepath=false diff --cached --name-only --', ...
  escape_command_argument(repository_root));
[status, output] = system(command);
if status ~= 0
  error("project:update:gitIndexReadFailed", ...
    "Could not read the Git index before updating MATLAB Project metadata.");
end
paths = strip(splitlines(string(output)));
paths(paths == "") = [];
end

function count = restore_newly_staged_sources(repository_root, matlab_root, staged_before)
staged_after = git_staged_paths(repository_root);
newly_staged = setdiff(staged_after, staged_before, "stable");
project_relative = replace(relative_to_root(matlab_root, repository_root), "\", "/");
in_project = startsWith(newly_staged, project_relative + "/");
newly_staged = newly_staged(in_project & ...
  ~is_project_metadata_git_path(newly_staged, project_relative));

for idx = 1:numel(newly_staged)
  command = sprintf('git -C "%s" restore --staged -- "%s"', ...
    escape_command_argument(repository_root), ...
    escape_command_argument(newly_staged(idx)));
  [status, ~] = system(command);
  if status ~= 0
    error("project:update:gitIndexRestoreFailed", ...
      "Could not restore the Git index state for %s.", newly_staged(idx));
  end
end
count = numel(newly_staged);
end

function tf = is_project_metadata_git_path(paths, project_relative)
metadata_prefix = project_relative + "/resources/project/";
metadata_files = project_relative + [ ...
  "/.gitattributes"
  "/.gitignore"
  "/ExperimentHailMary.prj"
];
tf = startsWith(paths, metadata_prefix) | ismember(paths, metadata_files);
end

function value = escape_command_argument(value)
value = strrep(char(string(value)), '"', '\"');
end

function text = format_path_list(prefix, paths)
if isempty(paths)
  text = "";
  return;
end
limit = min(numel(paths), 5);
text = string(prefix) + strjoin(paths(1:limit), ", ");
if numel(paths) > limit
  text = text + sprintf(" (and %d more)", numel(paths) - limit);
end
end

function changes = empty_change_summary()
changes = struct( ...
  "entries_added", 0, ...
  "entries_removed", 0, ...
  "classifications_changed", 0, ...
  "paths_changed", 0, ...
  "execution_files_removed", 0, ...
  "source_index_entries_restored", 0);
end
