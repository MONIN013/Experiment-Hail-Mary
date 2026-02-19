classdef (Abstract) IVirtualMotorGateway < handle
  methods (Abstract)
    out = run(obj, cfg)
  end
end
