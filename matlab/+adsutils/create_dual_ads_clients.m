function clients = create_dual_ads_clients(amsNetId, plcAmsPort, vmAmsPort)
clients = struct("plc", [], "vm", []);

try
    clients.plc = adsutils.create_ads_client();
    adsutils.connect_ads_client(clients.plc, amsNetId, plcAmsPort);

    clients.vm = adsutils.create_ads_client();
    adsutils.connect_ads_client(clients.vm, amsNetId, vmAmsPort);
catch err
    if ~isempty(clients.vm)
        adsutils.safe_disconnect(clients.vm);
    end
    if ~isempty(clients.plc)
        adsutils.safe_disconnect(clients.plc);
    end
    rethrow(err);
end
end
