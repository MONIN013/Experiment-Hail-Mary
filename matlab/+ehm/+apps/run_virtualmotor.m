function out = run_virtualmotor(varargin)
cfg = ehm.config.RunConfig.fromVarargin(varargin{:});

plcTransport = ehm.adapters.twincat.TwinCATAdsTransport("ads_assembly", cfg.ads_assembly);
vmTransport = ehm.adapters.twincat.TwinCATAdsTransport("ads_assembly", cfg.ads_assembly);
cleanupObj = onCleanup(@()cleanupTransports(plcTransport, vmTransport)); %#ok<NASGU>

plcTransport.connect(cfg.ams_net_id, cfg.ams_port);
vmTransport.connect(cfg.ams_net_id, cfg.vm_ams_port);

catalog = ehm.adapters.twincat.TwinCATSymbolCatalog();
service = ehm.services.VirtualMotorService(plcTransport, vmTransport, catalog);
out = service.run(cfg);
end

function cleanupTransports(plcTransport, vmTransport)
try
  vmTransport.disconnect();
catch
end
try
  plcTransport.disconnect();
catch
end
end
