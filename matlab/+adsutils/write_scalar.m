function write_scalar(client, symbolName, value, netTypeName)
handle = client.CreateVariableHandle(symbolName);
cleanupObj = onCleanup(@()adsutils.safe_delete_handle(client, handle)); %#ok<NASGU>
netValue = adsutils.to_net_scalar(value, netTypeName);

try
    client.WriteAny(handle, netValue);
catch writeErr
    try
        client.WriteSymbol(symbolName, netValue, false);
    catch
        rethrow(writeErr);
    end
end
end
