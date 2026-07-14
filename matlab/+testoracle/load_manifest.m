function manifest = load_manifest(path_value)
% load_manifest  Load and authenticate an immutable manifest MAT-file.
path_value = string(path_value);
if isfolder(path_value), path_value = fullfile(path_value, "manifest.mat"); end
if ~isfile(path_value)
  error("testoracle:manifest:notFound", "Manifest does not exist: %s", path_value);
end
loaded = load(char(path_value), "manifest");
if ~isfield(loaded, "manifest") || ~isstruct(loaded.manifest)
  error("testoracle:manifest:invalid", "MAT-file does not contain manifest.");
end
manifest = loaded.manifest;
if ~isfield(manifest, "canonical_digest")
  error("testoracle:manifest:invalid", "Manifest digest is missing.");
end
payload = rmfield(manifest, "canonical_digest");
actual = testoracle.canonical_digest(payload);
if actual ~= string(manifest.canonical_digest)
  error("testoracle:manifest:digestMismatch", ...
    "Frozen manifest authentication failed.");
end
end
