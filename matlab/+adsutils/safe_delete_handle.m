function safe_delete_handle(client, handle)
try
    client.DeleteVariableHandle(handle);
catch
end
end
