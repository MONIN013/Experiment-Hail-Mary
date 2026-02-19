%% ADS port/symbol discovery demo
baseDir = fileparts(fileparts(mfilename("fullpath")));
restoredefaultpath;
addpath(genpath(baseDir));

amsNetId = "192.168.10.3.1.1";
ports = [851 351];
connectTimeoutMs = 1000;
adsAssembly = "TwinCAT.Ads";
adsAssemblyCandidate = "C:\Program Files (x86)\Beckhoff\TwinCAT\Functions\TE14xx-ToolsForMatlabAndSimulink\TE140x\NET\TwinCAT.Ads.dll";
if isfile(adsAssemblyCandidate)
    adsAssembly = adsAssemblyCandidate;
end

fprintf("[%s] Starting ADS discovery\n", string(datetime("now")));
fprintf("  AmsNetId=%s, ports=[%s], timeout=%d ms\n", amsNetId, strjoin(string(ports), ", "), connectTimeoutMs);
fprintf("  Assembly=%s\n", adsAssembly);
drawnow;

tic;
[Tports, Tsymbols] = ehm.adapters.twincat.TwinCATSymbolCatalog.discoverPortsAndSymbols( ...
    amsNetId, ...
    ports, ...
    "ads_assembly", adsAssembly, ...
    "connect_timeout_ms", connectTimeoutMs, ...
    "top_level_only", false, ...
    "force_reload", true);
fprintf("[%s] Discovery finished in %.3f sec\n", string(datetime("now")), toc);
drawnow;

disp("=== Tports ===");
disp(Tports);
disp("=== Tports summary by Status ===");
statusList = unique(Tports.Status);
for i = 1:numel(statusList)
    s = statusList(i);
    c = sum(Tports.Status == s);
    fprintf("  %s: %d\n", s, c);
end

disp("=== Tsymbols (all) ===");
for k = 1:numel(ports)
    p = int32(ports(k));
    Tp = Tsymbols(Tsymbols.Port == p, :);
    badCount = sum(Tp.Status ~= "ok");
    fprintf("\n--- Port %d : %d rows (non-ok=%d) ---\n", p, height(Tp), badCount);
    if any(Tp.Status ~= "ok")
        disp(Tp(Tp.Status ~= "ok", {'Name', 'Status', 'ErrorMessage'}));
    end
    disp(Tp);
end

if isempty(Tsymbols)
    disp("=== Tsymbols empty: port diagnostics ===");
    disp(Tports(:, {'Port', 'Status', 'ErrorMessage'}));
end
