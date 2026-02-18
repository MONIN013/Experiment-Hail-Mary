function safe_disconnect(client)
try
    client.Dispose();
catch
    try
        client.Disconnect();
    catch
    end
end
end
