function out = run_virtualmotor(varargin)
cfg = experiment.RunConfig.from_varargin(varargin{:});

plc_transport = twincat_ads.AdsTransport("ads_assembly", cfg.ads_assembly);
module_transport = twincat_ads.AdsTransport("ads_assembly", cfg.ads_assembly);
if cfg.control_ams_port == cfg.ams_port
  control_transport = plc_transport;
else
  control_transport = twincat_ads.AdsTransport("ads_assembly", cfg.ads_assembly);
end
cleanup_obj = onCleanup(@()cleanup_transports(plc_transport, module_transport, control_transport)); %#ok<NASGU>

plc_transport.connect(cfg.ams_net_id, cfg.ams_port);
module_transport.connect(cfg.ams_net_id, cfg.module_ams_port);
if control_transport ~= plc_transport
  control_transport.connect(cfg.ams_net_id, cfg.control_ams_port);
end

service = experiment.VirtualMotorService(plc_transport, module_transport, control_transport);
out = service.run(cfg);
end

function cleanup_transports(plc_transport, module_transport, control_transport)
if control_transport ~= plc_transport
  try
    control_transport.disconnect();
  catch
  end
end
try
  module_transport.disconnect();
catch
end
try
  plc_transport.disconnect();
catch
end
end
