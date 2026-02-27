%% ADS port/symbol discovery demo
base_dir = fileparts(mfilename("fullpath"));
restoredefaultpath;
addpath(genpath(base_dir));

ams_net_id = "192.168.10.3.1.1";
ports = [851 852 853 351];
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

disp("=== Tsymbols (all) ===");
for k = 1:numel(ports)
  p = int32(ports(k));
  t_port = t_symbols(t_symbols.Port == p, :);
  bad_count = sum(t_port.Status ~= "ok");
  fprintf("\n--- Port %d : %d rows (non-ok=%d) ---\n", p, height(t_port), bad_count);
  if any(t_port.Status ~= "ok")
    disp(t_port(t_port.Status ~= "ok", {'Name', 'Status', 'ErrorMessage'}));
  end
  disp(t_port);
end

if isempty(t_symbols)
  disp("=== Tsymbols empty: port diagnostics ===");
  disp(t_ports(:, {'Port', 'Status', 'ErrorMessage'}));
end
