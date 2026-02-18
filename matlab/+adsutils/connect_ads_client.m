function connect_ads_client(client, amsNetId, amsPort)
amsNetId = char(string(amsNetId));

if isempty(strtrim(amsNetId))
    error("amsNetId must be explicitly specified for modern ADS connection.");
end

try
    client.Connect(amsNetId, int32(amsPort));
catch e
    error("Failed to connect ADS client (amsNetId='%s', port=%d): %s", amsNetId, int32(amsPort), e.message);
end
end