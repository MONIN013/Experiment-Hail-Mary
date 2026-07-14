function digest = file_sha256(file_path)
%FILE_SHA256 Compute SHA-256 over the exact bytes stored in a file.
arguments
  file_path {mustBeTextScalar}
end

file_path = string(file_path);
[fid, message] = fopen(file_path, "rb");
if fid < 0
  error("testoracle:live:fileOpenFailed", ...
    "Could not open %s for SHA-256: %s", file_path, message);
end
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, "*uint8");

engine = java.security.MessageDigest.getInstance("SHA-256");
if ~isempty(bytes)
  engine.update(bytes);
end
hash_bytes = typecast(engine.digest(), "uint8");
digest = lower(join(string(dec2hex(hash_bytes, 2)), ""));
end
