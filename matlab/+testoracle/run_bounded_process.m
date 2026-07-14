function result = run_bounded_process(executable, arguments, timeout_s, varargin)
% run_bounded_process  Run a child process with a bounded tree lifetime.
p = inputParser;
p.addParameter("label", string(executable), @is_text_scalar);
p.parse(varargin{:});
if ~(is_text_scalar(executable) && is_text_scalar(arguments) && ...
    isnumeric(timeout_s) && isreal(timeout_s) && isscalar(timeout_s) && ...
    isfinite(timeout_s) && timeout_s > 0)
  error("testoracle:process:invalidInput", ...
    "Executable, arguments, and a positive timeout are required.");
end

start_info = System.Diagnostics.ProcessStartInfo();
start_info.FileName = char(string(executable));
start_info.Arguments = char(string(arguments));
start_info.UseShellExecute = false;
start_info.CreateNoWindow = true;
process = System.Diagnostics.Process();
process.StartInfo = start_info;
cleanup = onCleanup(@() dispose_process(process));
clock_start = tic;
try
  started = process.Start();
catch exception
  error("testoracle:process:startFailed", ...
    "%s failed to start: %s", string(p.Results.label), exception.message);
end
if ~started
  error("testoracle:process:startFailed", ...
    "%s failed to start.", string(p.Results.label));
end
pid = double(process.Id);
timeout_ms = min(double(intmax("int32")), ceil(double(timeout_s)*1000));
finished = process.WaitForExit(int32(timeout_ms));
if ~finished
  kill_process_tree(process);
  elapsed_s = toc(clock_start);
  error("testoracle:process:timeout", ...
    "%s exceeded the frozen %.3f s timeout (pid=%d, elapsed=%.3f s).", ...
    string(p.Results.label), double(timeout_s), pid, elapsed_s);
end
process.WaitForExit();
result = struct("exit_code", double(process.ExitCode), ...
  "pid", pid, "elapsed_s", toc(clock_start));
clear cleanup
end

function kill_process_tree(process)
pid = double(process.Id);
if process.HasExited
  return;
end
tree_kill_confirmed = false;
if ispc
  try
    info = System.Diagnostics.ProcessStartInfo();
    info.FileName = "taskkill.exe";
    info.Arguments = sprintf("/PID %d /T /F", pid);
    info.UseShellExecute = false;
    info.CreateNoWindow = true;
    info.RedirectStandardOutput = true;
    info.RedirectStandardError = true;
    killer = System.Diagnostics.Process();
    killer.StartInfo = info;
    killer_cleanup = onCleanup(@() dispose_process(killer));
    if killer.Start()
      killer_finished = killer.WaitForExit(int32(10000));
      if killer_finished
        tree_kill_confirmed = killer.ExitCode == 0;
      else
        try
          killer.Kill();
        catch
        end
      end
    end
    clear killer_cleanup
  catch
    tree_kill_confirmed = false;
  end
end

% Always confirm the direct process as well. This fallback is intentionally
% bounded; failure must never be reported as an ordinary timeout.
for attempt = 1:3
  if process.HasExited
    break;
  end
  try
    process.Kill();
  catch
  end
  try
    process.WaitForExit(int32(1500));
  catch
  end
end
if ~process.HasExited || (ispc && ~tree_kill_confirmed)
  error("testoracle:process:terminationFailed", ...
    "Timed-out process tree could not be confirmed terminated (pid=%d).", pid);
end
end

function dispose_process(process)
try
  if ~isempty(process), process.Dispose(); end
catch
  % Disposal is best-effort during exception unwinding.
end
end

function tf = is_text_scalar(value)
tf = ischar(value) || (isstring(value) && isscalar(value));
end
