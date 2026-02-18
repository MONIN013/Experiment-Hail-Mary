function value = read_scalar(client, symbolName, netTypeName)
handle = client.CreateVariableHandle(symbolName);
cleanupObj = onCleanup(@()adsutils.safe_delete_handle(client, handle)); %#ok<NASGU>
typeObj = adsutils.resolve_net_type(netTypeName);

try
    obj = client.ReadAny(handle, typeObj);
catch
    obj = client.ReadAny(handle);
end

value = adsutils.convert_net_object(obj);
end
