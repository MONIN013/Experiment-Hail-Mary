function out = run_virtualmotor(varargin)
cfg = experiment.RunConfig.from_varargin(varargin{:});

plc_transport = twincat_ads.AdsTransport("ads_assembly", cfg.ads_assembly);
module_transport = twincat_ads.AdsTransport("ads_assembly", cfg.ads_assembly);
cleanup_obj = onCleanup(@()cleanup_transports(plc_transport, module_transport)); %#ok<NASGU>

plc_transport.connect(cfg.ams_net_id, cfg.ams_port);
module_transport.connect(cfg.ams_net_id, cfg.module_ams_port);

service = experiment.VirtualMotorService(plc_transport, module_transport);
out = service.run(cfg);
end

function cleanup_transports(plc_transport, module_transport)
try
  module_transport.disconnect();
catch
end
try
  plc_transport.disconnect();
catch
end
end
