function [Tsymbols, status, errorMessage] = list_symbols_core(client, varargin)
p = inputParser;
p.addParameter("top_level_only", true, @(x) islogical(x) || isnumeric(x));
p.addParameter("force_reload", true, @(x) islogical(x) || isnumeric(x));
p.addParameter("ams_net_id", "", @(x) ischar(x) || isstring(x));
p.addParameter("port", int32(0), @(x) isnumeric(x) && isscalar(x));
p.parse(varargin{:});
cfg = p.Results;

topLevelOnly = logical(cfg.top_level_only);
amsNetId = string(cfg.ams_net_id);
port = int32(cfg.port);

try
    loader = TwinCAT.TypeSystem.SymbolLoaderFactory.Create(client, TwinCAT.TypeSystem.SymbolLoaderSettings.DefaultDynamic);
    [names, types, sizes] = collect_from_loader(loader);
catch e
    status = "symbol_loader_failed";
    errorMessage = "TwinCAT.TypeSystem.SymbolLoaderFactory: " + string(e.message);
    Tsymbols = empty_symbols_table();
    return;
end

if topLevelOnly
    keep = ~contains(names, ".");
    names = names(keep);
    types = types(keep);
    sizes = sizes(keep);
end

if ~isempty(names)
    [~, ia] = unique(names, "stable");
    names = names(ia);
    types = types(ia);
    sizes = sizes(ia);
end

n = numel(names);
Tsymbols = table( ...
    repmat(amsNetId, n, 1), ...
    repmat(port, n, 1), ...
    names, ...
    types, ...
    sizes, ...
    repmat("ok", n, 1), ...
    repmat("", n, 1), ...
    'VariableNames', {'AmsNetId', 'Port', 'Name', 'Type', 'SizeBytes', 'Status', 'ErrorMessage'});

status = "ok";
errorMessage = "";
end

function [names, types, sizes] = collect_from_loader(loader)
names = strings(0, 1);
types = strings(0, 1);
sizes = int32(zeros(0, 1));
if isempty(loader)
    return;
end

symbols = [];
try
    symbols = loader.Symbols;
catch
    return;
end

[names, types, sizes] = collect_from_collection(symbols);
end

function [names, types, sizes] = collect_from_collection(symbols)
names = strings(0, 1);
types = strings(0, 1);
sizes = int32(zeros(0, 1));
if isempty(symbols)
    return;
end

n = 0;
try
    n = double(symbols.Count);
catch
    return;
end

names = strings(n, 1);
types = strings(n, 1);
sizes = int32(zeros(n, 1));
for k = 1:n
    s = symbols.Item(int32(k - 1));
    names(k) = string(s.InstancePath);
    types(k) = string(s.TypeName);
    sizes(k) = int32(s.Size);
end

keep = names ~= "";
names = names(keep);
types = types(keep);
sizes = sizes(keep);
end

function T = empty_symbols_table()
T = table( ...
    strings(0, 1), ...
    int32(zeros(0, 1)), ...
    strings(0, 1), ...
    strings(0, 1), ...
    int32(zeros(0, 1)), ...
    strings(0, 1), ...
    strings(0, 1), ...
    'VariableNames', {'AmsNetId', 'Port', 'Name', 'Type', 'SizeBytes', 'Status', 'ErrorMessage'});
end
