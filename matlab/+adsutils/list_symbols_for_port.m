function Tsymbols = list_symbols_for_port(amsNetId, port, varargin)
if nargin < 1
    amsNetId = "";
end
if nargin < 2
    error("port is required.");
end
if ~isnumeric(port) || ~isscalar(port)
    error("port must be a numeric scalar.");
end
if ~isfinite(double(port)) || double(port) < 1 || double(port) > 65535 || mod(double(port), 1) ~= 0
    error("port must be an integer in range [1, 65535].");
end

p = inputParser;
p.addParameter("ads_assembly", "TwinCAT.Ads", @(x) ischar(x) || isstring(x));
p.addParameter("top_level_only", true, @(x) islogical(x) || isnumeric(x));
p.addParameter("force_reload", true, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});
cfg = p.Results;

amsNetId = string(amsNetId);
port = int32(port);

try
    adsutils.load_ads_assembly(cfg.ads_assembly);
catch e
    Tsymbols = failed_table(amsNetId, port, "symbol_loader_failed", "Assembly load failed: " + string(e.message));
    return;
end

client = [];
cleanupObj = []; %#ok<NASGU>
try
    client = adsutils.create_ads_client();
    adsutils.connect_ads_client(client, char(amsNetId), port);
    cleanupObj = onCleanup(@()adsutils.safe_disconnect(client)); %#ok<NASGU>
catch e
    if ~isempty(client)
        adsutils.safe_disconnect(client);
    end
    Tsymbols = failed_table(amsNetId, port, "symbol_loader_failed", "Connect failed: " + string(e.message));
    return;
end

[Tsymbols, status, errorMessage] = adsutils.list_symbols_core( ...
    client, ...
    "top_level_only", logical(cfg.top_level_only), ...
    "force_reload", logical(cfg.force_reload), ...
    "ams_net_id", amsNetId, ...
    "port", port);

if status ~= "ok"
    Tsymbols = failed_table(amsNetId, port, "symbol_loader_failed", errorMessage);
end
end

function T = failed_table(amsNetId, port, status, errorMessage)
T = table( ...
    amsNetId, ...
    port, ...
    string(""), ...
    string(""), ...
    int32(0), ...
    string(status), ...
    string(errorMessage), ...
    'VariableNames', {'AmsNetId', 'Port', 'Name', 'Type', 'SizeBytes', 'Status', 'ErrorMessage'});
end
