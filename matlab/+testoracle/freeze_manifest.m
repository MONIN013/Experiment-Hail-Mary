function files = freeze_manifest(manifest, directory)
% freeze_manifest  Persist a manifest once; overwriting is forbidden.
verify_manifest(manifest);
directory = string(directory);
if strlength(directory) == 0
  error("testoracle:manifest:invalidDirectory", "Manifest directory is required.");
end
if ~isfolder(directory), mkdir(directory); end
mat_path = fullfile(directory, "manifest.mat");
json_path = fullfile(directory, "manifest.json");
if isfile(mat_path) || isfile(json_path)
  error("testoracle:manifest:alreadyFrozen", ...
    "Frozen manifest files already exist in %s.", directory);
end

nonce = string(char(java.util.UUID.randomUUID()));
mat_temp = mat_path + "." + nonce + ".tmp";
json_temp = json_path + "." + nonce + ".tmp";
cleanup = onCleanup(@() delete_temporary(mat_temp, json_temp));
save(char(mat_temp), "manifest", "-v7.3");
envelope = manifest_envelope(manifest);
write_text(json_temp, jsonencode(envelope, "PrettyPrint", true));
if ~movefile(mat_temp, mat_path) || ~movefile(json_temp, json_path)
  error("testoracle:manifest:persistFailed", ...
    "Could not atomically publish the frozen manifest.");
end
loaded = testoracle.load_manifest(mat_path);
if loaded.canonical_digest ~= manifest.canonical_digest
  error("testoracle:manifest:persistFailed", ...
    "Manifest digest changed during persistence.");
end
files = struct("mat", string(mat_path), "json", string(json_path), ...
  "canonical_digest", string(manifest.canonical_digest));
end

function verify_manifest(manifest)
required = ["format", "version", "entries", "registry", "canonical_digest"];
if ~isstruct(manifest) || ~isscalar(manifest) || any(~isfield(manifest, required))
  error("testoracle:manifest:invalid", "Manifest is incomplete.");
end
payload = rmfield(manifest, "canonical_digest");
actual = testoracle.canonical_digest(payload);
if actual ~= string(manifest.canonical_digest)
  error("testoracle:manifest:digestMismatch", ...
    "Manifest content does not match its canonical digest.");
end
end

function envelope = manifest_envelope(manifest)
entries = repmat(struct("name", "", "layer_digests", struct()), ...
  numel(manifest.entries), 1);
for index = 1:numel(entries)
  entries(index).name = manifest.entries(index).name;
  entries(index).layer_digests = manifest.entries(index).layer_digests;
end
envelope = struct( ...
  "format", manifest.format, "version", manifest.version, ...
  "campaign_id", manifest.campaign_id, ...
  "created_at_utc", manifest.created_at_utc, ...
  "frozen_before_execution", true, ...
  "canonical_digest", manifest.canonical_digest, ...
  "entries", entries);
end

function write_text(path_value, value)
fid = fopen(path_value, "wt", "n", "UTF-8");
if fid < 0
  error("testoracle:manifest:persistFailed", "Cannot write %s.", path_value);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s\n", value);
end

function delete_temporary(varargin)
for index = 1:nargin
  if isfile(varargin{index}), delete(varargin{index}); end
end
end
