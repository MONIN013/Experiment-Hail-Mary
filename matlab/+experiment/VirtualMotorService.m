classdef VirtualMotorService < handle
  properties (Access = private)
    plc_transport
    vm_transport
    control_transport
  end

  methods
    function obj = VirtualMotorService(plc_transport, vm_transport, control_transport)
      if ~isa(plc_transport, "twincat_ads.IAdsTransport")
        error("experiment:service:invalidDependency", ...
          "plc_transport must implement twincat_ads.IAdsTransport.");
      end
      if ~isa(vm_transport, "twincat_ads.IAdsTransport")
        error("experiment:service:invalidDependency", ...
          "vm_transport must implement twincat_ads.IAdsTransport.");
      end
      if nargin < 3 || isempty(control_transport)
        control_transport = plc_transport;
      end
      if ~isa(control_transport, "twincat_ads.IAdsTransport")
        error("experiment:service:invalidDependency", ...
          "control_transport must implement twincat_ads.IAdsTransport.");
      end
      obj.plc_transport = plc_transport;
      obj.vm_transport = vm_transport;
      obj.control_transport = control_transport;
    end

    function out = run(obj, cfg)
      cfg = experiment.ExperimentConfig.from_varargin(cfg);
      conn = experiment.ConnectionManager.from_transports( ...
        obj.plc_transport, obj.control_transport, obj.vm_transport);
      out = experiment.ExperimentRunner.run(conn, cfg);
    end
  end
end
