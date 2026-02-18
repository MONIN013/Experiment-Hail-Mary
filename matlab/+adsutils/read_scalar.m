function value = read_scalar(client, symbolName, netTypeName)
handle = client.CreateVariableHandle(symbolName);
cleanupObj = onCleanup(@()adsutils.safe_delete_handle(client, handle)); %#ok<NASGU>
typeObj = adsutils.resolve_net_type(netTypeName);

obj = client.ReadAny(handle, typeObj);
value = adsutils.convert_net_object(obj);
end