function child_entry_worker(request_path)
% child_entry_worker  Fresh-process execution side of the VM campaign.
arguments
  request_path {mustBeTextScalar}
end
loaded = load(request_path, "request");
if ~isfield(loaded, "request") || ~isstruct(loaded.request) || ...
    ~isscalar(loaded.request)
  error("testoracle:child:invalidRequest", ...
    "Request MAT does not contain a scalar request.");
end
request = loaded.request;
required = ["entry", "expected", "context", "result_path", "manifest_digest"];
if any(~isfield(request, required)) || ...
    string(request.context.manifest_digest) ~= string(request.manifest_digest)
  error("testoracle:child:invalidRequest", ...
    "Request is incomplete or has a manifest provenance mismatch.");
end

entry = request.entry;
expected = request.expected;
context = request.context;
[entry, expected] = authenticate_frozen_request( ...
  entry, expected, context, request.manifest_digest);
started_at = utc_now();
capture = execute_entry(entry, expected, context);
layer_reports = testoracle.build_layer_reports( ...
  entry, expected, capture, context);
result = struct( ...
  "entry_name", string(entry.name), ...
  "manifest_digest", string(request.manifest_digest), ...
  "expected_layer_digests", expected.layer_digests, ...
  "started_at_utc", started_at, "finished_at_utc", utc_now(), ...
  "layer_reports", layer_reports, ...
  "detail", capture.detail, ...
  "restart_count", double(capture.restart_count), ...
  "logger_captures", capture.logger_proof);
publish_result(result, request.result_path);
end

function [entry, expected] = authenticate_frozen_request( ...
    entry, expected, context, requested_digest)
if ~isfield(context, "manifest_files") || ...
    ~isfield(context.manifest_files, "mat")
  error("testoracle:child:manifestMissing", ...
    "Child request has no frozen manifest path.");
end
manifest = testoracle.load_manifest(context.manifest_files.mat);
if string(manifest.canonical_digest) ~= string(requested_digest)
  error("testoracle:child:manifestDigestMismatch", ...
    "Child request digest does not authenticate the frozen manifest.");
end
match = find(string({manifest.entries.name}) == string(entry.name));
registry_match = find(string({manifest.registry.name}) == string(entry.name));
if numel(match) ~= 1 || numel(registry_match) ~= 1
  error("testoracle:child:manifestEntryMismatch", ...
    "Frozen manifest has no unique entry %s.", entry.name);
end
frozen = manifest.entries(match);
layers = ["exact", "independent", "outcome", "artifact"];
for layer = layers
  digest = testoracle.canonical_digest(expected.(char(layer)));
  frozen_digest = string(frozen.layer_digests.(char(layer)));
  if digest ~= frozen_digest || ...
      string(expected.layer_digests.(char(layer))) ~= frozen_digest
    error("testoracle:child:layerDigestMismatch", ...
      "%s.%s does not match the frozen manifest.", entry.name, layer);
  end
end
entry = manifest.registry(registry_match);
expected = frozen;
end

function capture = execute_entry(entry, expected, context)
matlab_root = string(context.matlab_root);
tools_root = fullfile(matlab_root, "tools");
data_root = fullfile(matlab_root, "experiment", "data");
addpath(tools_root);
path = fullfile(matlab_root, entry.relative_path);
name = string(entry.name);
capture = empty_capture(name);

switch name
  case "tools.run_exp01_exp04_preflight"
    run(path);
    capture.tool_result = require_variable( ...
      "run_verify_xar_result", run_verify_xar_result);
  case "tools.run_ads_discovery_demo"
    run(path);
    capture.tool_result = struct( ...
      "ports", require_variable("t_ports", t_ports), ...
      "symbols", require_variable("t_symbols", t_symbols));
  case "tools.run_verify_xar"
    run(path);
    capture.tool_result = require_variable( ...
      "run_verify_xar_result", run_verify_xar_result);
  case "tools.run_verify_virtual_motor"
    run(path);
    capture.tool_result = require_variable( ...
      "run_verify_virtual_motor_result", ...
      run_verify_virtual_motor_result);
  case "tools.run_ads_transport_e2e"
    run(path);
    capture.tool_result = require_variable( ...
      "run_ads_transport_e2e_result", ...
      run_ads_transport_e2e_result);
  case "tools.run_configure_virtual_motor"
    run(path);
    capture.tool_result = require_variable( ...
      "run_configure_virtual_motor_result", ...
      run_configure_virtual_motor_result);
  case "tools.run_virtual_motor_prediction_e2e"
    run(path);
    value = require_variable("run_virtual_motor_prediction_e2e_result", ...
      run_virtual_motor_prediction_e2e_result);
    capture.tool_result = value;
    capture.logger = value.logger_bin;
    capture.command_tables = command_tables(value.run.cmd);
    capture.logger_proof = testoracle.capture_logger_artifact( ...
      value.logger_bin, name, context, "run");
    capture.restart_proof = testoracle.validate_restart_proof(value.restart);
    capture.restart_count = capture.restart_proof.restart_count;
    capture.controller_readback = read_controller(expected.exact.config);
    capture.parameter_readbacks = read_vm_parameters(expected.exact.config);
    capture.vm_status = read_vm_status(expected.exact.config);
  case {"experiment.exp01", "experiment.exp02", "experiment.exp03"}
    experiment_name = extractAfter(name, "experiment.");
    file_name = live_file(experiment_name);
    backup_root = fullfile(context.campaign_directory, "live_script_backups");
    [capture.live_report, capture.live_evidence] = refresh_live_capture( ...
      fullfile(matlab_root, "experiment", file_name), backup_root);
    runner_path = fullfile(data_root, experiment_name + "_runner.mat");
    [capture.logger, capture.command_tables] = logger_from_runner(runner_path);
    capture.logger_proof = testoracle.capture_logger_artifact( ...
      capture.logger, name, context, "run");
    capture.artifact_source = load_experiment_artifact( ...
      experiment_name, data_root);
    capture.controller_readback = read_controller(expected.exact.config);
    capture.parameter_readbacks = read_vm_parameters(expected.exact.config);
    capture.vm_status = read_vm_status(expected.exact.config);
  case "experiment.exp04"
    before = list_run_directories(data_root);
    backup_root = fullfile(context.campaign_directory, "live_script_backups");
    [capture.live_report, capture.live_evidence] = refresh_live_capture( ...
      fullfile(matlab_root, "experiment", "exp04_ILC.m"), backup_root);
    run_directory = require_new_run_directory(data_root, before);
    result_path = fullfile(run_directory, "ilc_result.mat");
    result_file = load(result_path);
    capture.artifact_source = result_file;
    paths = exp04_logger_paths(result_file, run_directory);
    capture.logger = cell(1, numel(paths));
    logger_proof = cell(1, numel(paths));
    capture.command_tables = exp04_command_tables(result_file);
    for trial = 1:numel(paths)
      parsed = experiment.read_logger_bin(paths(trial));
      capture.logger{trial} = parsed;
      logger_proof{trial} = testoracle.capture_logger_artifact( ...
        parsed, name, context, sprintf("trial%02d", trial));
    end
    capture.logger_proof = [logger_proof{:}];
    capture.controller_readback = read_controller(expected.exact.config);
    capture.parameter_readbacks = read_vm_parameters(expected.exact.config);
    capture.vm_status = read_vm_status(expected.exact.config);
  case "tools.run_position_command_demo"
    run(path);
    value = require_variable("collect_out", collect_out);
    capture.tool_result = struct("run", out, "signals", signals, ...
      "metrics", signal_metrics, "cfg", cfg);
    capture.logger = value.logger_bin;
    capture.command_tables = command_tables(cfg);
    capture.logger_proof = testoracle.capture_logger_artifact( ...
      value.logger_bin, name, context, "run");
    capture.controller_readback = read_controller(expected.exact.config);
    capture.parameter_readbacks = read_vm_parameters(expected.exact.config);
    capture.vm_status = read_vm_status(expected.exact.config);
  case "tools.run_si_demo"
    run(path);
    value = require_variable("si_out", si_out);
    capture.tool_result = value;
    capture.logger = value.logger_bin;
    capture.command_tables = command_tables(cfg);
    capture.logger_proof = testoracle.capture_logger_artifact( ...
      value.logger_bin, name, context, "run");
    capture.controller_readback = read_controller(expected.exact.config);
    capture.parameter_readbacks = read_vm_parameters(expected.exact.config);
    capture.vm_status = read_vm_status(expected.exact.config);
  case "tools.run_controller_benchmark"
    capture = run_controller_test_e2e(entry, expected, context, path);
  case "tools.run_check_logger_bin"
    [capture.logger_proof, capture.tool_result] = ...
      check_campaign_loggers(context, path);
  otherwise
    error("testoracle:child:unknownEntry", ...
      "No concrete child execution is defined for %s.", name);
end
capture.detail = capture_detail(name, capture.logger_proof);
end

function capture = run_controller_test_e2e(entry, expected, context, script_path)
capture = empty_capture(entry.name);
controllers = expected.exact.controllers;
count = numel(controllers);
capture.logger = cell(1, count);
logger_proof = cell(1, count);
controller_readback = cell(1, count);
parameter_reports = cell(1, count);
parameter_readbacks = cell(1, count);
vm_status = cell(1, count);
capture.command_tables = cell(1, count);
capture.test_metrics = cell(1, count);
plant = virtualMotor.PlantConfig.from_struct(expected.exact.plant);
for index = 1:count
  cfg = experiment.ExperimentConfig.from_struct(controllers(index).config);
  virtualMotor.restart_runtime(cfg.env);
  conn = experiment.ConnectionManager.create(cfg);
  cleanup = onCleanup(@() conn.session.close());
  configuration = virtualMotor.configure(conn, plant, ...
    "taskDtNs", cfg.env.task_dt_ns(), ...
    "timeout_s", cfg.reset_timeout_s, "validateSymbols", true);
  parameter_reports{index} = testoracle.compare_parameter_readback( ...
    configuration.requested, configuration.readback, ...
    "eps_factor", expected.outcome.gate.common.parameter_double_eps_factor);
  parameter_readbacks{index} = configuration.readback;
  clear cleanup
  collected = experiment.exp0n.run_and_collect(cfg);
  experiment.exp0n.assert_run_contract(collected.run);
  capture.logger{index} = collected.logger_bin;
  logger_proof{index} = testoracle.capture_logger_artifact( ...
    collected.logger_bin, entry.name, context, sprintf("test%02d", index));
  controller_readback{index} = read_controller(controllers(index).config);
  parameter_readbacks{index} = read_vm_parameters(controllers(index).config);
  vm_status{index} = read_vm_status(controllers(index).config);
  capture.command_tables{index} = command_tables(cfg);
  signals = experiment.exp02.signals_from_logger_bin( ...
    collected.logger_bin, ...
    "expected_sample_count", controllers(index).prediction.sample_count);
  capture.test_metrics{index} = signals;
end
capture.logger_proof = [logger_proof{:}];
capture.controller_readback = [controller_readback{:}];
capture.parameter_reports = [parameter_reports{:}];
capture.parameter_readbacks = [parameter_readbacks{:}];
capture.vm_status = [vm_status{:}];
capture.restart_count = count;
benchmark_root = fullfile(string(context.matlab_root), ...
  "experiment", "data", "controller_benchmark_runs");
before = list_named_run_directories(benchmark_root);
run(script_path);
in_memory = require_variable("benchmark", benchmark);
if ~isfield(in_memory, "summary_path") || ...
    strlength(string(in_memory.summary_path)) == 0 || ...
    ~isfile(in_memory.summary_path)
  error("testoracle:child:normalBenchmarkSummaryMissing", ...
    "Normal controller benchmark did not save its summary MAT.");
end
after = list_named_run_directories(benchmark_root);
created = setdiff(after, before, "stable");
[summary_directory, ~, ~] = fileparts(string(in_memory.summary_path));
if numel(created) ~= 1 || ...
    ~paths_equal(summary_directory, fullfile(benchmark_root, created))
  error("testoracle:child:normalBenchmarkRunProvenance", ...
    "Normal benchmark summary is not in one newly created run directory.");
end
saved = load(in_memory.summary_path, "benchmark");
if ~isfield(saved, "benchmark") || ...
    ~isstruct(saved.benchmark) || ~isscalar(saved.benchmark)
  error("testoracle:child:normalBenchmarkSummaryInvalid", ...
    "Saved normal benchmark summary has no scalar benchmark value.");
end
capture.tool_result = saved.benchmark;
capture.artifact_source = saved;
capture.benchmark_provenance = struct( ...
  "pass", true, "summary_loaded", true, ...
  "directory_was_created", true, ...
  "run_directory", summary_directory, ...
  "summary_path", string(in_memory.summary_path));
normal_proof = cell(1, count);
for index = 1:count
  run_info = capture.tool_result.runs(index);
  if ~isfield(run_info, "logger_archive_path") || ...
      strlength(string(run_info.logger_archive_path)) == 0
    error("testoracle:child:normalBenchmarkLoggerMissing", ...
      "Normal controller benchmark run %d has no archived logger.", index);
  end
  parsed = experiment.read_logger_bin(run_info.logger_archive_path);
  normal_proof{index} = testoracle.capture_logger_artifact( ...
    parsed, entry.name, context, sprintf("normal%02d", index));
end
capture.logger_proof = [capture.logger_proof, normal_proof{:}];
capture.detail = "seven restarted controller tests plus normal benchmark captured";
end

function value = read_controller(config_value)
cfg = experiment.ExperimentConfig.from_struct(config_value);
conn = experiment.ConnectionManager.create(cfg);
cleanup = onCleanup(@() conn.session.close());
value = testoracle.read_controller_readback(conn, cfg);
end

function value = read_vm_status(config_value)
cfg = experiment.ExperimentConfig.from_struct(config_value);
conn = experiment.ConnectionManager.create(cfg);
cleanup = onCleanup(@() conn.session.close());
t = twincat_ads.AdsTransport.net_types();
prefix = "VirtualMotorCore_Obj1 (Module1).Outputs.";
value = struct( ...
  "motor_status", conn.module.read_scalar(prefix + "motor.statusWord", t.u16), ...
  "load_status", conn.module.read_scalar(prefix + "load.statusWord", t.u16));
end

function value = read_vm_parameters(config_value)
cfg = experiment.ExperimentConfig.from_struct(config_value);
conn = experiment.ConnectionManager.create(cfg);
cleanup = onCleanup(@() conn.session.close());
value = virtualMotor.readParams(conn);
end

function [report, evidence] = refresh_live_capture(file_path, backup_root)
before_report = experiment.liveeditor.inspect(file_path);
before_file_sha256 = testoracle.file_sha256(file_path);
before = dir(file_path);
started_at = utc_now();
report = refresh_live_script(file_path, "backup_root", backup_root);
after = dir(file_path);
after_file_sha256 = testoracle.file_sha256(file_path);
evidence = testoracle.live_freshness_evidence( ...
  before_file_sha256, before_report, after_file_sha256, report.after, ...
  "before_datenum", before.datenum, "after_datenum", after.datenum, ...
  "source_exists", isfile(file_path), ...
  "backup_exists", isfile(report.backup_path));
evidence.started_at_utc = started_at;
evidence.finished_at_utc = utc_now();
end

function [logger, tables] = logger_from_runner(path)
if ~isfile(path)
  error("testoracle:child:runnerMissing", "Runner MAT is missing: %s.", path);
end
value = load(path, "logger", "cmd");
if ~isfield(value, "logger") || ~isfield(value.logger, "file_path") || ...
    ~isfield(value, "cmd")
  error("testoracle:child:runnerLoggerMissing", ...
    "Runner MAT has no confirmed logger path: %s.", path);
end
logger = experiment.read_logger_bin(value.logger.file_path);
tables = command_tables(value.cmd);
end

function source = load_experiment_artifact(name, data_root)
switch string(name)
  case "exp01"
    source = struct( ...
      "chirp", load(fullfile(data_root, "chirp_result.mat")), ...
      "plant", load(fullfile(data_root, "plant.mat")));
  case "exp02"
    source = load(fullfile(data_root, "feedback_result.mat"));
  case "exp03"
    source = load(fullfile(data_root, "feedforward_result.mat"));
  otherwise
    error("testoracle:child:unknownArtifact", "%s", name);
end
end

function paths = exp04_logger_paths(result_file, run_directory)
paths = strings(0, 1);
if isfield(result_file, "history") && ...
    isfield(result_file.history, "trialLoggerPaths")
  paths = string(result_file.history.trialLoggerPaths(:));
end
if isempty(paths)
  files = dir(fullfile(run_directory, "trial*_logger.bin"));
  [~, order] = sort(string({files.name}));
  files = files(order);
  paths = string(fullfile({files.folder}, {files.name}));
end
if numel(paths) ~= 10 || any(~isfile(paths))
  error("testoracle:child:exp04LoggerCheckpointMissing", ...
    "exp04 must checkpoint ten full logger bins before the child exits.");
end
end

function tables = exp04_command_tables(result_file)
if ~isfield(result_file, "history") || ...
    ~all(isfield(result_file.history, ["r", "f"]))
  error("testoracle:child:exp04CommandHistoryMissing", ...
    "exp04 result must contain reference/feedforward history.");
end
history = result_file.history;
count = size(history.f, 2);
tables = cell(1, count);
for trial = 1:count
  tables{trial} = struct( ...
    "ref_profile", history.r(:, trial), ...
    "ff_profile", history.f(:, trial), ...
    "dist_profile", zeros(size(history.f, 1), 1));
end
end

function value = command_tables(source)
if isa(source, "experiment.ExperimentConfig")
  value = struct("ref_profile", source.ref_profile(:), ...
    "ff_profile", source.ff_profile(:), ...
    "dist_profile", source.dist_profile(:));
elseif isstruct(source) && ...
    all(isfield(source, ["ref_profile", "ff_profile", "dist_profile"]))
  value = struct("ref_profile", source.ref_profile(:), ...
    "ff_profile", source.ff_profile(:), ...
    "dist_profile", source.dist_profile(:));
else
  error("testoracle:child:commandTablesMissing", ...
    "Captured run has no command-table proof.");
end
end

function names = list_run_directories(data_root)
base = fullfile(data_root, "exp04_runs");
if ~isfolder(base), names = strings(0, 1); return; end
items = dir(base);
items = items([items.isdir] & ~ismember({items.name}, {'.', '..'}));
names = string({items.name});
end

function names = list_named_run_directories(base)
if ~isfolder(base), names = strings(0, 1); return; end
items = dir(base);
items = items([items.isdir] & ~ismember({items.name}, {'.', '..'}));
names = string({items.name});
end

function same = paths_equal(first, second)
first = replace(string(first), "/", "\");
second = replace(string(second), "/", "\");
same = strcmpi(first, second);
end

function path = require_new_run_directory(data_root, before)
base = fullfile(data_root, "exp04_runs");
after = list_run_directories(data_root);
created = setdiff(after, before, "stable");
if numel(created) ~= 1
  error("testoracle:child:exp04RunDirectory", ...
    "Expected exactly one new exp04 run directory, observed %d.", numel(created));
end
path = fullfile(base, created);
end

function [proof, report] = check_campaign_loggers(context, checker_path)
expected = expected_campaign_logger_paths(context.campaign_directory);
files = dir(fullfile(context.campaign_directory, "loggers", "**", "*.bin"));
actual = string(fullfile({files.folder}, {files.name})).';
if ~isequal(sort(lower(actual)), sort(lower(expected)))
  missing = setdiff(lower(expected), lower(actual));
  unexpected = setdiff(lower(actual), lower(expected));
  error("testoracle:logger:campaignSetMismatch", ...
    "Campaign logger set mismatch (expected=%d actual=%d missing=%s unexpected=%s).", ...
    numel(expected), numel(actual), strjoin(missing, ", "), ...
    strjoin(unexpected, ", "));
end
proof = repmat(struct("path", "", "record_count", 0, "digest", ""), ...
  numel(expected), 1);
checks = repmat(struct("path", "", "record_count", 0, ...
  "duration_s", 0, "control_input_abs_max", 0), numel(expected), 1);
for index = 1:numel(expected)
  target_file = expected(index);
  render_plots = false; %#ok<NASGU>
  run(checker_path);
  checked = require_variable("out", out);
  if string(checked.file_path) ~= target_file || ...
      double(checked.record_count) <= 0
    error("testoracle:logger:checkerPathMismatch", ...
      "Logger checker did not return the requested nonempty file %s.", target_file);
  end
  proof(index) = struct( ...
    "path", target_file, "record_count", double(checked.record_count), ...
    "digest", testoracle.canonical_digest(checked.raw));
  checks(index) = struct( ...
    "path", target_file, "record_count", double(checked.record_count), ...
    "duration_s", double(checked.summary.duration_s), ...
    "control_input_abs_max", ...
      double(checked.summary.control_input_abs_max));
  clear out target_file render_plots
end
report = struct("pass", true, "expected_count", numel(expected), ...
  "checked_count", numel(checks), "checks", checks);
end

function paths = expected_campaign_logger_paths(campaign_directory)
root = fullfile(string(campaign_directory), "loggers");
entries = [ ...
  "tools.run_virtual_motor_prediction_e2e", "experiment.exp01", ...
  "experiment.exp02", "experiment.exp03", "tools.run_position_command_demo", ...
  "tools.run_si_demo"];
paths = strings(30, 1);
next = 1;
for entry = entries
  paths(next) = fullfile(root, safe_name(entry), "run.bin");
  next = next + 1;
end
for trial = 1:10
  paths(next) = fullfile(root, safe_name("experiment.exp04"), ...
    sprintf("trial%02d.bin", trial));
  next = next + 1;
end
for prefix = ["test", "normal"]
  for controller = 1:7
    paths(next) = fullfile(root, safe_name("tools.run_controller_benchmark"), ...
      sprintf("%s%02d.bin", prefix, controller));
    next = next + 1;
  end
end
if next ~= numel(paths) + 1
  error("testoracle:logger:internalExpectedCount", ...
    "Expected campaign logger list is incomplete.");
end
end

function value = require_variable(name, value)
if isempty(value)
  error("testoracle:child:uncapturedOutput", ...
    "Required child output %s is empty.", name);
end
end

function detail = capture_detail(name, proof)
detail = string(name) + " captured and verified from child process";
if isempty(proof), return; end
items = strings(numel(proof), 1);
for index = 1:numel(proof)
  item = proof(index);
  if isfield(item, "source_path"), source = string(item.source_path);
  else, source = string(item.path);
  end
  if isfield(item, "campaign_path"), destination = string(item.campaign_path);
  else, destination = string(item.path);
  end
  if isfield(item, "raw_digest"), digest = string(item.raw_digest);
  else, digest = string(item.digest);
  end
  items(index) = sprintf("%s -> %s count=%d raw=%s", ...
    source, destination, double(item.record_count), digest);
end
detail = detail + ": " + strjoin(items, " | ");
end

function name = live_file(experiment_name)
switch string(experiment_name)
  case "exp01", name = "exp01_SysId.m";
  case "exp02", name = "exp02_FeedBack.m";
  case "exp03", name = "exp03_FeedForward.m";
  otherwise, error("testoracle:child:unknownLiveFile", "%s", experiment_name);
end
end

function capture = empty_capture(name)
capture = struct( ...
  "name", string(name), "tool_result", struct(), ...
  "logger", [], "logger_proof", struct([]), ...
  "artifact_source", [], "controller_readback", struct([]), ...
  "parameter_reports", struct([]), "parameter_readbacks", struct([]), ...
  "test_metrics", {{}}, ...
  "command_tables", [], ...
  "vm_status", struct([]), ...
  "benchmark_provenance", struct(), ...
  "live_report", struct(), "restart_proof", struct(), ...
  "restart_count", 0, "detail", "");
capture.live_evidence = struct();
end

function publish_result(result, result_path)
directory = fileparts(result_path);
temporary = string(tempname(directory)) + ".mat";
cleanup = onCleanup(@() delete_if_present(temporary));
save(temporary, "result", "-v7.3");
[moved, message] = movefile(temporary, result_path, "f");
if ~moved
  error("testoracle:child:resultPublishFailed", ...
    "Failed to publish child result: %s", message);
end
end

function value = utc_now()
value = string(datetime("now", "TimeZone", "UTC", ...
  "Format", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"));
end

function delete_if_present(path)
if isfile(path), delete(path); end
end

function value = safe_name(value)
value = string(matlab.lang.makeValidName(char(string(value))));
end
