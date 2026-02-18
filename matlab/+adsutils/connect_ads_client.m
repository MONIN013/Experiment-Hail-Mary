function connect_ads_client(client, amsNetId, amsPort)
try
    client.Connect(amsNetId, int32(amsPort));
catch
    client.Connect(amsNetId, uint16(amsPort));
end
end
