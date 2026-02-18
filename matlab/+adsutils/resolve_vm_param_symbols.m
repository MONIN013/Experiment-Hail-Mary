function symbols = resolve_vm_param_symbols(client, vmParamSymbolPrefix)
if nargin < 2
    vmParamSymbolPrefix = "";
end

suffixFields = {"M", "D", "Kt", "tau_limit", "vel_limit", "task_dt_ns"};
suffixBase = "VirtualMotorParameter.";

prefix = string(vmParamSymbolPrefix);
if strlength(prefix) > 0
    symbols = build_symbol_map(client, prefix, suffixFields, suffixBase);
    return;
end

names = list_symbol_names(client);
if ~isempty(names)
    symbols = resolve_from_symbol_list(client, names, suffixFields, suffixBase);
    return;
end

% Fallback if symbol enumeration is unavailable in this ADS runtime.
symbols = build_symbol_map(client, "", suffixFields, suffixBase);
end

function symbols = resolve_from_symbol_list(client, symbolNames, suffixFields, suffixBase)
prefixCandidates = strings(0, 1);
for k = 1:numel(symbolNames)
    name = string(symbolNames(k));
    if endsWith(name, suffixBase + suffixFields{1})
        prefixCandidates(end + 1, 1) = extractBefore(name, suffixBase + suffixFields{1}); %#ok<AGROW>
    end
end
prefixCandidates = unique(prefixCandidates);

validPrefixes = strings(0, 1);
for p = 1:numel(prefixCandidates)
    pref = prefixCandidates(p);
    isValid = true;
    for f = 1:numel(suffixFields)
        fullName = pref + suffixBase + suffixFields{f};
        if ~any(symbolNames == fullName)
            isValid = false;
            break;
        end
    end
    if isValid
        validPrefixes(end + 1, 1) = pref; %#ok<AGROW>
    end
end

if numel(validPrefixes) ~= 1
    error("Could not uniquely resolve VM parameter symbol prefix. Set vm_param_symbol_prefix explicitly.");
end

symbols = build_symbol_map(client, validPrefixes(1), suffixFields, suffixBase);
end

function symbols = build_symbol_map(client, prefix, suffixFields, suffixBase)
symbols = struct();
for f = 1:numel(suffixFields)
    field = suffixFields{f};
    symbolName = char(prefix + suffixBase + field);
    ensure_symbol_exists(client, symbolName);
    symbols.(field) = symbolName;
end
end

function ensure_symbol_exists(client, symbolName)
handle = [];
try
    handle = client.CreateVariableHandle(symbolName);
catch
    error("ADS symbol not found: %s", symbolName);
end
adsutils.safe_delete_handle(client, handle);
end

function symbolNames = list_symbol_names(client)
symbolNames = strings(0, 1);

% TwinCAT.Ads (newer API)
try
    loader = TwinCAT.TypeSystem.SymbolLoaderFactory.Create(client, TwinCAT.TypeSystem.SymbolLoaderSettings.DefaultDynamic);
    symbolNames = collect_names_from_loader(loader);
    if ~isempty(symbolNames)
        return;
    end
catch
end

% TwinCAT.Ads (older API variants)
try
    loader = TwinCAT.Ads.TypeSystem.SymbolLoaderFactory.Create(client, TwinCAT.Ads.TypeSystem.SymbolLoaderSettings.DefaultDynamic);
    symbolNames = collect_names_from_loader(loader);
    if ~isempty(symbolNames)
        return;
    end
catch
end

try
    loader = TwinCAT.TypeSystem.SymbolLoaderFactory.Create(client, TwinCAT.TypeSystem.SymbolLoaderSettings.Default);
    symbolNames = collect_names_from_loader(loader);
    if ~isempty(symbolNames)
        return;
    end
catch
end

try
    loader = TwinCAT.Ads.TypeSystem.SymbolLoaderFactory.Create(client, TwinCAT.Ads.TypeSystem.SymbolLoaderSettings.Default);
    symbolNames = collect_names_from_loader(loader);
catch
end
end

function symbolNames = collect_names_from_loader(loader)
symbolNames = strings(0, 1);
if isempty(loader)
    return;
end

try
    symbols = loader.Symbols;
catch
    return;
end

try
    n = int32(symbols.Count);
    names = strings(double(n), 1);
    for k = 1:double(n)
        s = symbols.Item(int32(k - 1));
        names(k) = read_symbol_name(s);
    end
    names = names(names ~= "");
    symbolNames = unique(names);
catch
    symbolNames = strings(0, 1);
end
end

function name = read_symbol_name(symbolObj)
name = "";
try
    name = string(symbolObj.InstancePath);
    if strlength(name) > 0
        return;
    end
catch
end

try
    name = string(symbolObj.PathName);
    if strlength(name) > 0
        return;
    end
catch
end

try
    name = string(symbolObj.Name);
catch
    name = "";
end
end
