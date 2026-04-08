classdef Symbols
  properties
    vmParams
    types
    requiredProbes
  end

  methods (Static)
    function out = from_defaults()
      out = virtualMotor.Symbols.from_prefix(virtualMotor.Symbols.default_prefix());
    end

    function out = from_prefix(prefix)
      out = virtualMotor.Symbols();
      prefix = virtualMotor.Symbols.require_prefix(prefix, "vm_param_symbol_prefix");
      out.types = twincat_ads.AdsTransport.net_types();
      out.vmParams = struct( ...
        "motor", struct( ...
          "inertia", string(prefix) + "motor.inertia", ...
          "damping", string(prefix) + "motor.damping", ...
          "ratedTorque", string(prefix) + "motor.ratedTorque", ...
          "tauLimit", string(prefix) + "motor.tauLimit", ...
          "velLimit", string(prefix) + "motor.velLimit", ...
          "maxPermille", string(prefix) + "motor.maxPermille", ...
          "encoderResolution", string(prefix) + "motor.encoderResolution"), ...
        "load", struct( ...
          "inertia", string(prefix) + "load.inertia", ...
          "damping", string(prefix) + "load.damping", ...
          "ratedTorque", string(prefix) + "load.ratedTorque", ...
          "tauLimit", string(prefix) + "load.tauLimit", ...
          "velLimit", string(prefix) + "load.velLimit", ...
          "encoderResolution", string(prefix) + "load.encoderResolution"), ...
        "coupling", struct( ...
          "stiffness", string(prefix) + "coupling.stiffness", ...
          "damping", string(prefix) + "coupling.damping"), ...
        "taskDtNs", string(prefix) + "taskDtNs");
      t = out.types;
      out.requiredProbes = {
        out.vmParams.motor.inertia, t.double;
        out.vmParams.motor.damping, t.double;
        out.vmParams.motor.ratedTorque, t.double;
        out.vmParams.motor.maxPermille, t.double;
        out.vmParams.motor.tauLimit, t.double;
        out.vmParams.motor.velLimit, t.double;
        out.vmParams.motor.encoderResolution, t.u32;
        out.vmParams.load.inertia, t.double;
        out.vmParams.load.damping, t.double;
        out.vmParams.load.ratedTorque, t.double;
        out.vmParams.load.tauLimit, t.double;
        out.vmParams.load.velLimit, t.double;
        out.vmParams.load.encoderResolution, t.u32;
        out.vmParams.coupling.stiffness, t.double;
        out.vmParams.coupling.damping, t.double;
        out.vmParams.taskDtNs, t.u64
      };
    end
  end

  methods (Static, Access = private)
    function prefix = default_prefix()
      prefix = "VirtualMotorCore_Obj1 (Module1).PlantParameter.";
    end

    function p = require_prefix(prefix, label)
      p = char(string(prefix));
      if isempty(strtrim(p))
        error("virtualMotor:symbol:invalidPrefix", "%s is required.", label);
      end
    end
  end
end
