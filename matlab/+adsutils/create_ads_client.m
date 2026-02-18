function client = create_ads_client()
try
    client = TwinCAT.Ads.AdsClient();
catch
    client = TwinCAT.Ads.TcAdsClient();
end
end
