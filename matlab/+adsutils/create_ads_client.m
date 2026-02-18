function client = create_ads_client()
try
    client = TwinCAT.Ads.TcAdsClient();
catch e
    error("Failed to create TwinCAT.Ads.TcAdsClient. Ensure TwinCAT ADS .NET API is available. Details: %s", e.message);
end
end
