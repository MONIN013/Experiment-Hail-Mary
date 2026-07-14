%% ADS port/symbol discovery demo
%
%  参照: docs/architecture/MatlabSpec.md §7.2

tool_file = mfilename("fullpath");
matlab_root = fileparts(fileparts(tool_file));
addpath(matlab_root, fullfile(matlab_root, "experiment"));
clear tool_file matlab_root;

env = config.EnvironmentConfig.current();
ams_net_id = env.ams_net_id;
% The active runtime contract is 351/852/853.  Port 851 belongs to an
% optional discovery probe and is included only when the caller requests it.
if ~exist("optional_probe_ports", "var")
  optional_probe_ports = zeros(1, 0);
end
validateattributes(optional_probe_ports, "numeric", ...
  ["vector", "integer", "positive", "finite"], ...
  mfilename, "optional_probe_ports");
ports = unique([double(optional_probe_ports(:).'), ...
  env.control_port, env.seq_port, env.module_port], "stable");
connect_timeout_ms = 1000;

fprintf("[%s] Starting ADS discovery\n", string(datetime("now")));
fprintf("  AmsNetId=%s, ports=[%s], timeout=%d ms\n", ...
  ams_net_id, strjoin(string(ports), ", "), connect_timeout_ms);
drawnow;

tic;
[t_ports, t_symbols] = twincat_ads.SymbolBrowser.discover_ports_and_symbols( ...
  ams_net_id, ...
  ports, ...
  "connect_timeout_ms", connect_timeout_ms, ...
  "top_level_only", false, ...
  "force_reload", true);
fprintf("[%s] Discovery finished in %.3f sec\n", string(datetime("now")), toc);
drawnow;

disp("=== Tports ===");
disp(t_ports);
disp("=== Tports summary by Status ===");
status_list = unique(t_ports.Status);
for i = 1:numel(status_list)
  s = status_list(i);
  c = sum(t_ports.Status == s);
  fprintf("  %s: %d\n", s, c);
end

% Auto-generated TwinCAT symbols are filtered out.
% Top-level names starting with '_' or matching known system namespaces are excluded.
autogen_prefixes = ["_", "TwinCAT_SystemInfoVarList", "AlarmManager"];

disp("=== Tsymbols (user-defined only) ===");
for k = 1:numel(ports)
  p = int32(ports(k));
  t_port = t_symbols(t_symbols.Port == p, :);
  top_names = extractBefore(t_port.Name + ".", ".");
  mask = ~startsWith(top_names, autogen_prefixes);
  t_user = t_port(mask, :);
  bad_count = sum(t_user.Status ~= "ok");
  fprintf("\n--- Port %d : %d user rows (of %d total, non-ok=%d) ---\n", ...
    p, height(t_user), height(t_port), bad_count);
  if any(t_user.Status ~= "ok")
    disp(t_user(t_user.Status ~= "ok", {'Name', 'Status', 'ErrorMessage'}));
  end
  disp(t_user);
end

if isempty(t_symbols)
  disp("=== Tsymbols empty: port diagnostics ===");
  disp(t_ports(:, {'Port', 'Status', 'ErrorMessage'}));
end
