function Tports = list_ports(amsNetId, ports, varargin)
if nargin < 1
    amsNetId = "";
end
if nargin < 2 || isempty(ports)
    ports = [851 351];
end

p = inputParser;
p.addParameter("ads_assembly", "TwinCAT.Ads", @(x) ischar(x) || isstring(x));
p.addParameter("connect_timeout_ms", 500, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.parse(varargin{:});
cfg = p.Results;

amsNetId = string(amsNetId);
ports = double(ports(:));
if any(~isfinite(ports)) || any(ports < 1) || any(ports > 65535) || any(mod(ports, 1) ~= 0)
    error("ports must contain integer values in range [1, 65535].");
end
portList = int32(unique(ports, "stable"));
if isempty(portList)
    error("ports must not be empty.");
end

n = numel(portList);
connectable = false(n, 1);
status = repmat("connect_failed", n, 1);
errorMessage = repmat("", n, 1);

assemblyOk = true;
assemblyErr = "";
try
    adsutils.load_ads_assembly(cfg.ads_assembly);
catch e
    assemblyOk = false;
    assemblyErr = string(e.message);
end

if ~assemblyOk
    status(:) = "assembly_failed";
    errorMessage(:) = assemblyErr;
    Tports = table( ...
        repmat(amsNetId, n, 1), ...
        portList, ...
        connectable, ...
        status, ...
        errorMessage, ...
        'VariableNames', {'AmsNetId', 'Port', 'Connectable', 'Status', 'ErrorMessage'});
    return;
end

for k = 1:n
    c = [];
    try
        c = adsutils.create_ads_client();
        try_set_connect_timeout(c, cfg.connect_timeout_ms);
        adsutils.connect_ads_client(c, char(amsNetId), portList(k));
        % Connect alone may succeed even when target ADS port is absent.
        % ReadState forces an actual ADS request and validates the route/port.
        c.ReadState();
        connectable(k) = true;
        status(k) = "ok";
        errorMessage(k) = "";
    catch e
        connectable(k) = false;
        status(k) = "connect_failed";
        errorMessage(k) = string(e.message);
    end
    if ~isempty(c)
        adsutils.safe_disconnect(c);
    end
end

Tports = table( ...
    repmat(amsNetId, n, 1), ...
    portList, ...
    connectable, ...
    status, ...
    errorMessage, ...
    'VariableNames', {'AmsNetId', 'Port', 'Connectable', 'Status', 'ErrorMessage'});
end

function try_set_connect_timeout(client, timeoutMs)
try
    client.Timeout = int32(timeoutMs);
catch
end
end
