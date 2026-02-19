classdef TwinCATSymbolCatalog < ehm.interfaces.ISymbolCatalog
  methods
    function symbols = resolveVirtualMotorSymbols(~, prefix)
      if nargin < 2 || strlength(string(prefix)) == 0
        symbols = ehm.contracts.VirtualMotorSymbols.fromDefaults();
        return;
      end
      symbols = ehm.contracts.VirtualMotorSymbols.fromPrefix(prefix);
    end

    function validateRequiredSymbols(~, transport, symbols)
      if ~isa(transport, "ehm.interfaces.IAdsTransport")
        error("ehm:symbol:invalidTransport", "transport must implement ehm.interfaces.IAdsTransport.");
      end
      probes = symbols.requiredProbes;
      missing = strings(0, 1);
      for k = 1:size(probes, 1)
        symbol = string(probes{k, 1});
        netType = string(probes{k, 2});
        try
          transport.readScalar(symbol, netType);
        catch
          missing(end + 1, 1) = symbol; %#ok<AGROW>
        end
      end
      if ~isempty(missing)
        error("ehm:symbol:notFound", ...
          "Required ADS symbols not found: %s", strjoin(missing, ", "));
      end
    end
  end

  methods (Static)
    function [names, types, sizes] = collectSymbolsForTest(symbols, topLevelOnly)
      if nargin < 2
        topLevelOnly = true;
      end
      [names, types, sizes] = collectFromLoaderSymbols(symbols, logical(topLevelOnly), inf, inf);
    end

    function [Tports, Tsymbols] = discoverPortsAndSymbols(amsNetId, ports, varargin)
      Tports = ehm.adapters.twincat.TwinCATSymbolCatalog.listPorts(amsNetId, ports, varargin{:});
      rows = cell(height(Tports), 1);
      for k = 1:height(Tports)
        if Tports.Status(k) == "ok"
          rows{k} = ehm.adapters.twincat.TwinCATSymbolCatalog.listSymbolsForPort( ...
            amsNetId, Tports.Port(k), varargin{:});
        else
          rows{k} = emptySymbolsTable();
        end
      end
      Tsymbols = vertcat(rows{:});
      if isempty(Tsymbols) || ~all(ismember({'AmsNetId','Port','Name','Type','SizeBytes','Status','ErrorMessage'}, Tsymbols.Properties.VariableNames))
        Tsymbols = emptySymbolsTable();
      end
    end

    function Tports = listPorts(amsNetId, ports, varargin)
      p = inputParser;
      p.KeepUnmatched = true;
      p.addParameter("ads_assembly", "TwinCAT.Ads", @(x) ischar(x) || isstring(x));
      p.addParameter("connect_timeout_ms", 1000, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.parse(varargin{:});
      cfg = p.Results;

      amsNetId = string(amsNetId);
      portList = int32(ports(:));
      n = numel(portList);

      status = repmat("connect_failed", n, 1);
      errors = repmat("", n, 1);
      try
        ensureAdsAssemblyLoaded(cfg.ads_assembly);
      catch e
        status(:) = "assembly_failed";
        errors(:) = string(e.message);
        Tports = table( ...
          repmat(amsNetId, n, 1), ...
          portList, ...
          status, ...
          errors, ...
          'VariableNames', {'AmsNetId', 'Port', 'Status', 'ErrorMessage'});
        return;
      end

      for k = 1:n
        client = [];
        try
          client = TwinCAT.Ads.TcAdsClient();
          trySetClientTimeout(client, cfg.connect_timeout_ms);
          client.Connect(char(amsNetId), portList(k));
          % Force an ADS request to validate route/port reachability.
          client.ReadState();
          status(k) = "ok";
        catch e
          status(k) = "connect_failed";
          errors(k) = string(e.message);
        end
        safeDisposeClient(client);
      end

      Tports = table( ...
        repmat(amsNetId, n, 1), ...
        portList, ...
        status, ...
        errors, ...
        'VariableNames', {'AmsNetId', 'Port', 'Status', 'ErrorMessage'});
    end

    function Tsymbols = listSymbolsForPort(amsNetId, port, varargin)
      p = inputParser;
      p.addParameter("ads_assembly", "TwinCAT.Ads", @(x) ischar(x) || isstring(x));
      p.addParameter("top_level_only", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("force_reload", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("connect_timeout_ms", 1000, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("traversal_timeout_ms", 5000, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("traversal_max_nodes", 50000, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.parse(varargin{:});
      cfg = p.Results;

      t = ehm.adapters.twincat.TwinCATAdsTransport("ads_assembly", cfg.ads_assembly);
      amsNetId = string(amsNetId);
      port = int32(port);

      try
        t.connect(char(amsNetId), port);
        c = t.readClient();
        trySetClientTimeout(c, cfg.connect_timeout_ms);
        loader = TwinCAT.Ads.TypeSystem.SymbolLoaderFactory.Create(c, TwinCAT.Ads.SymbolLoaderSettings.DefaultDynamic);
        symbols = loader.Symbols;
      catch e
        Tsymbols = failedTable(amsNetId, port, "symbol_loader_failed", string(e.message));
        t.disconnect();
        return;
      end

      [names, types, sizes] = collectFromLoaderSymbols( ...
        symbols, ...
        logical(cfg.top_level_only), ...
        double(cfg.traversal_timeout_ms), ...
        double(cfg.traversal_max_nodes));
      symbols = [];
      loader = [];
      t.disconnect();

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
    end
  end
end

function [names, types, sizes] = collectFromLoaderSymbols(symbols, topLevelOnly, traversalTimeoutMs, traversalMaxNodes)
names = strings(0, 1);
types = strings(0, 1);
sizes = int32(zeros(0, 1));
if isempty(symbols)
  return;
end

if nargin < 3 || ~isfinite(traversalTimeoutMs) || traversalTimeoutMs <= 0
  traversalTimeoutMs = inf;
end
if nargin < 4 || ~isfinite(traversalMaxNodes) || traversalMaxNodes <= 0
  traversalMaxNodes = inf;
end

queue = collectSymbolsFromCollection(symbols);
if isempty(queue)
  return;
end

visited = containers.Map("KeyType", "char", "ValueType", "logical");
startTick = tic;
processedCount = 0;
while ~isempty(queue)
  if processedCount >= traversalMaxNodes
    break;
  end
  if toc(startTick) * 1000 > traversalTimeoutMs
    break;
  end

  symbol = queue{1};
  queue(1) = [];
  processedCount = processedCount + 1;

  if isempty(symbol)
    continue;
  end

  key = symbolIdentityKey(symbol);
  if isKey(visited, key)
    continue;
  end
  visited(key) = true;

  try
    name = extractName(symbol);
    type = extractType(symbol);
    sizeBytes = extractSize(symbol);
  catch
    continue;
  end
  if strlength(name) == 0
    continue;
  end
  names(end + 1, 1) = name; %#ok<AGROW>
  types(end + 1, 1) = type; %#ok<AGROW>
  sizes(end + 1, 1) = sizeBytes; %#ok<AGROW>

  if topLevelOnly
    continue;
  end
  if isArraySymbol(name, type)
    continue;
  end

  childCollection = getChildrenCollection(symbol);
  if isempty(childCollection)
    continue;
  end
  children = collectSymbolsFromCollection(childCollection);
  if isempty(children)
    continue;
  end
  queue = [children; queue]; %#ok<AGROW>
end

keep = names ~= "";
if topLevelOnly
  keep = keep & ~contains(names, ".");
end
names = names(keep);
types = types(keep);
sizes = sizes(keep);

if ~isempty(names)
  [~, ia] = unique(names, "stable");
  ia = ia(:);
  names = names(ia);
  types = types(ia);
  sizes = sizes(ia);
end
names = names(:);
types = types(:);
sizes = sizes(:);
end

function tf = isArraySymbol(name, type)
tf = contains(name, "[");
if tf
  return;
end
typeText = upper(strtrim(char(string(type))));
tf = startsWith(typeText, "ARRAY ");
end

function key = symbolIdentityKey(symbol)
key = "";
try
  id = System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(symbol);
  key = "dotnet#" + string(int64(id));
catch
end
if strlength(key) > 0
  key = char(key);
  return;
end

name = extractName(symbol);
if strlength(name) > 0
  key = char("name#" + name);
  return;
end

key = char("fallback#" + string(class(symbol)));
end

function children = collectSymbolsFromCollection(collection)
children = cell(0, 1);
if isempty(collection)
  return;
end
try
  n = double(collection.Count);
catch
  return;
end
if n <= 0
  return;
end
children = cell(n, 1);
count = 0;
for k = 1:n
  try
    symbol = collection.Item(int32(k - 1));
  catch
    continue;
  end
  if isempty(symbol)
    continue;
  end
  count = count + 1;
  children{count, 1} = symbol;
end
children = children(1:count);
end

function collection = getChildrenCollection(symbol)
collection = [];
try
  collection = symbol.SubSymbols;
catch
end
if ~isempty(collection)
  return;
end
try
  collection = symbol.Members;
catch
  collection = [];
end
end

function name = extractName(symbol)
name = safeStringValue(symbol, "InstancePath");
if strlength(name) > 0
  return;
end
name = safeStringValue(symbol, "InstanceName");
if strlength(name) > 0
  return;
end
name = safeStringValue(symbol, "PathName");
if strlength(name) > 0
  return;
end
name = safeStringValue(symbol, "Name");
end

function type = extractType(symbol)
type = safeStringValue(symbol, "TypeName");
if strlength(type) > 0
  return;
end
type = safeStringValue(symbol, "DataTypeName");
if strlength(type) > 0
  return;
end
try
  dataType = symbol.DataType;
  type = safeStringValue(dataType, "Name");
catch
  type = "";
end
end

function sizeBytes = extractSize(symbol)
sizeBytes = safeInt32Value(symbol, "Size");
end

function T = failedTable(amsNetId, port, status, errorMessage)
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

function T = emptySymbolsTable()
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

function out = safeStringValue(obj, propName)
out = "";
propName = char(string(propName));
try
  v = obj.(propName);
catch
  return;
end
if isempty(v)
  out = "";
  return;
end
try
  c = char(v);
  out = string(c);
  return;
catch
end
try
  s = string(v);
  if isscalar(s)
    out = s;
  elseif isempty(s)
    out = "";
  else
    out = join(s, " ");
  end
catch
  out = "";
end
end

function out = safeInt32Value(obj, propName)
out = int32(0);
propName = char(string(propName));
try
  v = obj.(propName);
  if isempty(v)
    return;
  end
  out = int32(v);
catch
  out = int32(0);
end
end

function ensureAdsAssemblyLoaded(adsAssembly)
assemblyName = char(string(adsAssembly));
if exist(assemblyName, "file") == 2
  NET.addAssembly(assemblyName);
  return;
end
NET.addAssembly(assemblyName);
end

function trySetClientTimeout(client, timeoutMs)
if isempty(client)
  return;
end
try
  client.Timeout = int32(timeoutMs);
catch
end
end

function safeDisposeClient(client)
if isempty(client)
  return;
end
try
  client.Dispose();
catch
end
end
