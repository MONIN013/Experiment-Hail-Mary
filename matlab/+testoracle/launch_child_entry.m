function result = launch_child_entry(entry, expected, context)
% launch_child_entry  Run one auditable entry in a fresh MATLAB process.
if ~isstruct(entry) || ~isscalar(entry) || ...
    ~isstruct(expected) || ~isscalar(expected) || ...
    ~isstruct(context) || ~isscalar(context)
  error("testoracle:child:invalidRequest", ...
    "entry, expected, and context must be scalar structs.");
end
directory = fullfile(string(context.campaign_directory), "child", ...
  safe_name(entry.name));
if ~isfolder(directory), mkdir(directory); end
request_path = fullfile(directory, "request.mat");
result_path = fullfile(directory, "result.mat");
log_path = fullfile(directory, "matlab.log");
if isfile(request_path) || isfile(result_path)
  error("testoracle:child:duplicateRequest", ...
    "Child request/result already exists for %s.", entry.name);
end
request = struct( ...
  "entry", entry, "expected", expected, "context", context, ...
  "result_path", string(result_path), ...
  "manifest_digest", string(context.manifest_digest));
temporary = string(tempname(directory)) + ".mat";
cleanup = onCleanup(@() delete_if_present(temporary));
save(temporary, "request", "-v7.3");
[moved, message] = movefile(temporary, request_path, "f");
if ~moved
  error("testoracle:child:requestPublishFailed", ...
    "Failed to publish request for %s: %s", entry.name, message);
end

escaped_request = replace(string(request_path), "'", "''");
setup_path = fullfile(string(context.matlab_root), "setup_matlab_environment.m");
escaped_setup = replace(setup_path, "'", "''");
matlab_executable = fullfile(matlabroot, "bin", "matlab.exe");
escaped_log = replace(string(log_path), '"', '\"');
arguments = string(sprintf( ...
  '-logfile "%s" -batch "run(''%s''); testoracle.child_entry_worker(''%s'')"', ...
  char(escaped_log), char(escaped_setup), char(escaped_request)));
try
  process = testoracle.run_bounded_process( ...
    matlab_executable, arguments, double(entry.timeout_s), ...
    "label", string(entry.name) + " MATLAB child");
catch exception
  tail = log_tail(log_path, exception.message);
  if exception.identifier == "testoracle:process:timeout"
    error("testoracle:child:timeout", ...
      "%s child timed out after %.3f s: %s", ...
      entry.name, double(entry.timeout_s), tail);
  end
  rethrow(exception);
end
status = process.exit_code;
if status ~= 0 || ~isfile(result_path)
  tail = log_tail(log_path, "");
  error("testoracle:child:executionFailed", ...
    "%s child failed (status=%d, result=%d): %s", ...
    entry.name, status, isfile(result_path), tail);
end
loaded = load(result_path, "result");
if ~isfield(loaded, "result") || ~isstruct(loaded.result) || ...
    ~isscalar(loaded.result)
  error("testoracle:child:invalidResult", ...
    "%s child result MAT has no scalar result.", entry.name);
end
result = loaded.result;
if ~isfield(result, "entry_name") || ...
    string(result.entry_name) ~= string(entry.name) || ...
    ~isfield(result, "manifest_digest") || ...
    string(result.manifest_digest) ~= string(context.manifest_digest)
  error("testoracle:child:provenanceMismatch", ...
    "%s child result provenance does not match the frozen request.", entry.name);
end
if ~isfield(result, "expected_layer_digests") || ...
    ~isequaln(result.expected_layer_digests, expected.layer_digests)
  error("testoracle:child:layerProvenanceMismatch", ...
    "%s child result does not echo the frozen layer digests.", entry.name);
end
end

function value = safe_name(value)
value = string(matlab.lang.makeValidName(char(string(value))));
end

function value = log_tail(path, fallback)
value = string(fallback);
if isfile(path)
  text = string(fileread(path));
  lines = splitlines(text);
  lines = lines(strlength(strtrim(lines)) > 0);
  if numel(lines) > 20, lines = lines(end-19:end); end
  value = strjoin(lines, " | ");
end
if strlength(value) > 4000, value = extractAfter(value, strlength(value)-4000); end
end

function delete_if_present(path)
if isfile(path), delete(path); end
end
