function out = run_virtualmotor(varargin)
cfg = experiment.RunConfig.fromVarargin(varargin{:});

plc_transport = twincat_ads.AdsTransport("ads_assembly", cfg.ads_assembly);
vm_transport = twincat_ads.AdsTransport("ads_assembly", cfg.ads_assembly);
cleanup_obj = onCleanup(@()cleanup_transports(plc_transport, vm_transport)); %#ok<NASGU>

plc_transport.connect(cfg.ams_net_id, cfg.ams_port);
vm_transport.connect(cfg.ams_net_id, cfg.vm_ams_port);

service = experiment.VirtualMotorService(plc_transport, vm_transport);
out = service.run(cfg);
end

function cleanup_transports(plc_transport, vm_transport)
try
  vm_transport.disconnect();
catch
end
try
  plc_transport.disconnect();
catch
end
end
