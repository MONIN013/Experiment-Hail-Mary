function write_scalar(client, symbolName, value, netTypeName)
handle = client.CreateVariableHandle(symbolName);
cleanupObj = onCleanup(@()adsutils.safe_delete_handle(client, handle)); %#ok<NASGU>
netValue = adsutils.to_net_scalar(value, netTypeName);

client.WriteAny(handle, netValue);
end