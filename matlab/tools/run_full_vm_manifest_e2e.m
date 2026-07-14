function campaign = run_full_vm_manifest_e2e(varargin)
% run_full_vm_manifest_e2e  Test-only four-layer VirtualMotor orchestrator.
%
% The default executor runs each registry entry in a fresh MATLAB process.
% A test may inject another adapter, but it must execute (not skip) the
% entry and return exact/independent/outcome/artifact reports, each with a
% scalar logical pass. Capturing nothing is never a pass.

tool_file = mfilename("fullpath");
matlab_root = fileparts(fileparts(tool_file));
addpath(matlab_root, fullfile(matlab_root, "experiment"));

p = inputParser;
p.addParameter("EntryExecutor", @testoracle.default_entry_executor, ...
  @(x) isa(x, "function_handle"));
p.addParameter("ExpectedLayers", struct([]), @isstruct);
p.addParameter("ManifestDirectory", "", ...
  @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.addParameter("RestoreAndReadFinalState", ...
  @testoracle.restore_and_read_final_state, @(x) isa(x, "function_handle"));
p.addParameter("PrepareEntry", @testoracle.prepare_vm_entry, ...
  @(x) isa(x, "function_handle"));
p.parse(varargin{:});
executor = p.Results.EntryExecutor;

layers = p.Results.ExpectedLayers;
if isempty(layers)
  layers = testoracle.build_default_layers();
end
manifest = testoracle.build_manifest(layers);
campaign_directory = string(p.Results.ManifestDirectory);
if strlength(campaign_directory) == 0
  stamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss_SSS"));
  campaign_directory = fullfile(matlab_root, "experiment", "data", ...
    "full_vm_manifest_runs", stamp);
end
files = testoracle.freeze_manifest(manifest, campaign_directory);
backup = testoracle.backup_default_artifacts(campaign_directory, matlab_root);
ledger_path = fullfile(campaign_directory, "execution_ledger.mat");
ledger = testoracle.new_ledger(manifest);
testoracle.checkpoint_ledger(ledger, ledger_path);

restore = p.Results.RestoreAndReadFinalState;
prepare = p.Results.PrepareEntry;
cleanup_arm = testoracle.CleanupArm();
restore_cleanup = onCleanup(@() restore_if_armed(cleanup_arm, restore));
initial_state = struct();
safety_initialized = false;
context = struct( ...
  "matlab_root", matlab_root, ...
  "campaign_directory", campaign_directory, ...
  "manifest_files", files, ...
  "manifest_digest", manifest.canonical_digest, ...
  "backup", backup, "initial_state", initial_state);

for index = 1:numel(manifest.registry)
  registry_entry = manifest.registry(index);
  expected_entry = manifest.entries(index);
  if ~safety_initialized && double(registry_entry.phase) >= 2
    initial_state = restore();
    context.initial_state = initial_state;
    safety_initialized = true;
  end
  started_at = utc_now();
  preparation = prepare(registry_entry, expected_entry, context);
  entry_context = context;
  entry_context.preparation = preparation;
  result = executor(registry_entry, expected_entry, entry_context);
  validate_executor_result(result, registry_entry.name);
  validate_restart_policy(registry_entry, preparation, result);
  ledger = testoracle.record_entry( ...
    ledger, registry_entry.name, result.layer_reports, ...
    "started_at_utc", started_at, "detail", result.detail);
  testoracle.checkpoint_ledger(ledger, ledger_path);
  if ~ledger.records(index).pass
    error("testoracle:orchestrator:entryFailed", ...
      "%s failed at least one frozen layer.", registry_entry.name);
  end
end

if ~safety_initialized
  error("testoracle:orchestrator:safetyInitializationMissing", ...
    "Registry contained no phase-2 safety boundary.");
end
final_state = restore();
cleanup_arm.Armed = false;
ledger = testoracle.finalize_ledger(ledger, final_state);
testoracle.checkpoint_ledger(ledger, ledger_path);
campaign = struct( ...
  "pass", true, "directory", campaign_directory, ...
  "manifest", files, "ledger_path", string(ledger_path), ...
  "backup", backup, ...
  "initial_state", initial_state, ...
  "entry_count", numel(ledger.records), ...
  "final_state", final_state, "ledger", ledger);
end

function validate_executor_result(result, entry_name)
if ~isstruct(result) || ~isscalar(result) || ...
    ~all(isfield(result, ["layer_reports", "detail"]))
  error("testoracle:orchestrator:invalidAdapterResult", ...
    "EntryExecutor returned no auditable result for %s.", entry_name);
end

reports = result.layer_reports;
layers = ["exact", "independent", "outcome", "artifact"];
if ~isstruct(reports) || ~isscalar(reports) || any(~isfield(reports, layers))
  error("testoracle:orchestrator:invalidAdapterResult", ...
    "EntryExecutor must return all four layer reports for %s.", entry_name);
end
for layer = layers
  value = reports.(char(layer));
  if ~isstruct(value) || ~isscalar(value) || ~isfield(value, "pass") || ...
      ~(islogical(value.pass) && isscalar(value.pass))
    error("testoracle:orchestrator:invalidAdapterResult", ...
      "%s.%s has no scalar pass result.", entry_name, layer);
  end
end
end

function validate_restart_policy(entry, preparation, result)
policy = string(entry.restart_policy);
if ~isstruct(preparation) || ~isfield(preparation, "restart_count")
  error("testoracle:orchestrator:invalidPreparation", ...
    "Preparation proof is missing for %s.", entry.name);
end
switch policy
  case {"before_entry", "campaign_once"}
    if double(preparation.restart_count) ~= 1
      error("testoracle:orchestrator:restartContract", ...
        "%s requires exactly one immediate pre-entry restart.", entry.name);
    end
  case "self"
    if ~isfield(result, "restart_count") || double(result.restart_count) ~= 1
      error("testoracle:orchestrator:restartContract", ...
        "%s must prove its single internal restart.", entry.name);
    end
  case "per_controller_test_then_normal_tool"
    if ~isfield(result, "restart_count") || double(result.restart_count) ~= 7
      error("testoracle:orchestrator:restartContract", ...
        "Controller test E2E must restart immediately before each of seven methods.");
    end
  otherwise
    if double(preparation.restart_count) ~= 0
      error("testoracle:orchestrator:restartContract", ...
        "%s unexpectedly restarted the VM.", entry.name);
    end
end
end

function value = utc_now()
value = string(datetime("now", "TimeZone", "UTC", ...
  "Format", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"));
end

function safe_restore(restore)
try
  restore();
catch cause
  warning("testoracle:orchestrator:restoreFailed", ...
    "Final safety restore failed after an earlier error (%s: %s).", ...
    string(cause.identifier), string(cause.message));
end
end

function restore_if_armed(arm, restore)
if arm.Armed
  safe_restore(restore);
end
end
