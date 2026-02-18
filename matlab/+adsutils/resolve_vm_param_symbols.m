function symbols = resolve_vm_param_symbols(client, vmParamSymbolPrefix)
if nargin < 2 || strlength(string(vmParamSymbolPrefix)) == 0
    error("vm_param_symbol_prefix is required and must be explicitly specified.");
end

suffixFields = {"M", "D", "Kt", "tau_limit", "vel_limit", "task_dt_ns"};
suffixBase = "VirtualMotorParameter.";
prefix = string(vmParamSymbolPrefix);

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