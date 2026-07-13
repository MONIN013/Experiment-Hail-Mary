function [cleanup, monitor] = start_external_heartbeat(env, period_s, ads_assembly, hooks)
%START_EXTERNAL_HEARTBEAT Start and supervise an ADS heartbeat helper.
%
% The helper owns the external heartbeat writer. It signals readiness only
% after the ADS connection and variable handle are available. The returned
% monitor raises if the helper exits while the experiment is running.

if nargin < 2 || isempty(period_s)
  period_s = 0.03;
end
if nargin < 3
  ads_assembly = "";
end
if nargin < 4 || isempty(hooks)
  hooks = struct();
end
if ~ispc
  error("experiment:heartbeat:unsupportedPlatform", ...
    "External heartbeat helper is supported on Windows only.");
end
if ~(isnumeric(period_s) && isscalar(period_s) && isfinite(double(period_s)) && period_s > 0)
  error("experiment:heartbeat:invalidPeriod", "Heartbeat period must be a finite positive scalar.");
end

period_ms = max(1, round(double(period_s) * 1000));
flag_path = [tempname, '.flag'];
ready_path = [tempname, '.ready'];
error_path = [tempname, '.error'];
process = [];

fid = fopen(flag_path, "w");
if fid < 0
  error("experiment:heartbeat:flagCreateFailed", ...
    "Failed to create heartbeat flag file: %s", flag_path);
end
fprintf(fid, "run\n");
fclose(fid);

try
  [assembly_ref, assembly_is_path] = resolve_ads_assembly(ads_assembly);
  owner_pid = feature("getpid");
  script = build_powershell_script( ...
    assembly_ref, assembly_is_path, env, flag_path, ready_path, error_path, ...
    period_ms, owner_pid);
  encoded = encode_powershell(script);

  psi = System.Diagnostics.ProcessStartInfo();
  psi.FileName = "powershell.exe";
  psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand " + encoded;
  psi.UseShellExecute = false;
  psi.CreateNoWindow = true;
  psi.RedirectStandardError = true;
  psi.WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden;

  start_process = get_hook(hooks, "start_process", ...
    @(start_info, ~, ~) System.Diagnostics.Process.Start(start_info));
  pause_fn = get_hook(hooks, "pause", @pause);
  startup_timeout_s = get_hook(hooks, "startup_timeout_s", 3.0);
  process = start_process(psi, ready_path, error_path);
  if isempty(process)
    error("experiment:heartbeat:startFailed", "External heartbeat process did not start.");
  end

  monitor = @() assert_helper_running(process, error_path);
  t0 = tic;
  while toc(t0) < double(startup_timeout_s)
    if isfile(ready_path)
      monitor();
      cleanup = onCleanup(@() stop_helper(process, flag_path, ready_path, error_path));
      return;
    end
    monitor();
    pause_fn(0.01);
  end
  error("experiment:heartbeat:startupTimeout", ...
    "External heartbeat helper did not report readiness within %.3f s.", ...
    double(startup_timeout_s));
catch e
  stop_helper(process, flag_path, ready_path, error_path);
  rethrow(e);
end
end

function [assembly_ref, is_path] = resolve_ads_assembly(ads_assembly)
candidates = twincat_ads.assembly_candidates( ...
  ads_assembly, "experiment:heartbeat:adsAssemblyMissing");
assembly_ref = candidates(1);
is_path = isfile(assembly_ref);
end

function script = build_powershell_script( ...
    assembly_ref, assembly_is_path, env, flag_path, ready_path, ...
    error_path, period_ms, owner_pid)
if assembly_is_path
  load_assembly_line = "  [void][Reflection.Assembly]::LoadFrom('" + escape_ps(assembly_ref) + "')";
else
  load_assembly_line = "  [void][Reflection.Assembly]::Load('" + escape_ps(assembly_ref) + "')";
end
lines = [
  "$ErrorActionPreference='Stop'"
  "$client=$null"
  "$h=$null"
  "$owner=$null"
  "try {"
  load_assembly_line
  "  $owner = [Diagnostics.Process]::GetProcessById(" + ...
    string(round(owner_pid)) + ")"
  "  $client = New-Object TwinCAT.Ads.TcAdsClient"
  "  $client.Connect('" + escape_ps(env.ams_net_id) + "', " + string(round(env.control_port)) + ")"
  "  $h = $client.CreateVariableHandle('GVL_MODE.hostHeartbeatCounter')"
  "  Set-Content -LiteralPath '" + escape_ps(ready_path) + "' -Value 'ready' -NoNewline -Encoding UTF8"
  "  $counter = [uint32]$client.ReadAny($h, [UInt32])"
  "  while ((Test-Path -LiteralPath '" + escape_ps(flag_path) + ...
    "') -and (-not $owner.HasExited)) {"
  "    $counter = [uint32](($counter + 1) % [math]::Pow(2,32))"
  "    $client.WriteAny($h, $counter)"
  "    Start-Sleep -Milliseconds " + string(period_ms)
  "  }"
  "} catch {"
  "  Set-Content -LiteralPath '" + escape_ps(error_path) + "' -Value $_.Exception.ToString() -Encoding UTF8"
  "  exit 1"
  "} finally {"
  "  if ($null -ne $h -and $null -ne $client) { try { $client.DeleteVariableHandle($h) } catch {} }"
  "  if ($null -ne $client) { $client.Dispose() }"
  "  if ($null -ne $owner) { $owner.Dispose() }"
  "}"
  ];
script = strjoin(lines, newline);
end

function value = get_hook(hooks, field_name, default_value)
value = default_value;
if isstruct(hooks) && isfield(hooks, field_name) && ~isempty(hooks.(field_name))
  value = hooks.(field_name);
end
end

function assert_helper_running(process, error_path)
try
  exited = logical(process.HasExited);
catch e
  error("experiment:heartbeat:monitorFailed", ...
    "Failed to inspect external heartbeat helper: %s", string(e.message));
end
if ~exited
  return;
end

detail = "no diagnostic output";
if isfile(error_path)
  detail = strtrim(string(fileread(error_path)));
else
  try
    detail = strtrim(string(process.StandardError.ReadToEnd()));
  catch
  end
end
error("experiment:heartbeat:helperExited", ...
  "External heartbeat helper exited unexpectedly: %s", detail);
end

function out = escape_ps(value)
out = strrep(char(string(value)), "'", "''");
end

function encoded = encode_powershell(script)
bytes = unicode2native(char(script), "UTF-16LE");
encoded = matlab.net.base64encode(bytes);
end

function stop_helper(process, flag_path, ready_path, error_path)
delete_if_exists(flag_path);
try
  if ~isempty(process) && ~logical(process.HasExited)
    process.WaitForExit(int32(3000));
  end
  if ~isempty(process) && ~logical(process.HasExited)
    process.Kill();
  end
catch
end
delete_if_exists(ready_path);
delete_if_exists(error_path);
end

function delete_if_exists(file_path)
if isfile(file_path)
  delete(file_path);
end
end
