%% ADS port/symbol discovery demo
baseDir = fileparts(fileparts(mfilename("fullpath")));
restoredefaultpath;
addpath(genpath(baseDir));

amsNetId = "192.168.10.3.1.1";
ports = [851 351];
adsAssembly = "TwinCAT.Ads";
adsAssemblyCandidate = "C:\Program Files (x86)\Beckhoff\TwinCAT\Functions\TE14xx-ToolsForMatlabAndSimulink\TE140x\NET\TwinCAT.Ads.dll";
if isfile(adsAssemblyCandidate)
    adsAssembly = adsAssemblyCandidate;
end

[Tports, Tsymbols] = adsutils.discover_ports_and_symbols( ...
    amsNetId, ...
    ports, ...
    "ads_assembly", adsAssembly, ...
    "top_level_only", false, ...
    "force_reload", true);

disp("=== Tports ===");
disp(Tports);

disp("=== Tsymbols (all) ===");
for k = 1:numel(ports)
    p = int32(ports(k));
    Tp = Tsymbols(Tsymbols.Port == p, :);
    fprintf("\n--- Port %d : %d rows ---\n", p, height(Tp));
    disp(Tp);
end
