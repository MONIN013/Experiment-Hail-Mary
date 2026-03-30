classdef VirtualMotorSymbols
  properties
    reset
    modeResetReq
    modeResetAckCounter
    hostHeartbeatCounter
    experimentActive
    experimentState
    loggerFileReleased
    loggerErrorCode
    tableLen
    idx
    repeatCount
    trialIndex
    modeFlags
    modeFlagsCandidates
    experimentStateCandidates
    refTable
    ffTable
    distTable
    refValue
    ffValue
    distValue
    log
    vmParams
    controllerParams
    types
    plcRequiredProbes
    vmRequiredProbes
    controllerRequiredProbes
    requiredProbes
  end

  methods (Static)
    function out = from_defaults()
      out = experiment.VirtualMotorSymbols.base_contract();
      t = out.types;
      out.plcRequiredProbes = {
        out.reset, t.bool;
        out.experimentActive, t.bool;
        out.tableLen, t.u32;
        out.idx, t.u32;
        out.repeatCount, t.u32;
        out.trialIndex, t.u32;
      out.refValue, t.double;
      out.ffValue, t.double;
      out.distValue, t.double
      };
      out.requiredProbes = out.plcRequiredProbes;
    end

    function out = from_vm_prefix(prefix)
      out = experiment.VirtualMotorSymbols.base_contract();
      prefix = experiment.VirtualMotorSymbols.require_prefix(prefix, "vm_param_symbol_prefix");
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
      out.vmRequiredProbes = {
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
      out.requiredProbes = out.vmRequiredProbes;
    end

    function out = from_controller_prefix(prefix)
      out = experiment.VirtualMotorSymbols.base_contract();
      prefix = experiment.VirtualMotorSymbols.require_prefix(prefix, "controller_param_symbol_prefix");
      % GUI-generated ControllerCore in this repo currently uses grouped parameter structs.
      % Each struct uses its own field-name prefix (pidBx, leadBx, notchBx, resoBx).
      out.controllerParams = struct( ...
        "pidB0", string(prefix) + "PIDParams.pidB0", ...
        "pidB1", string(prefix) + "PIDParams.pidB1", ...
        "pidB2", string(prefix) + "PIDParams.pidB2", ...
        "pidA1", string(prefix) + "PIDParams.pidA1", ...
        "pidA2", string(prefix) + "PIDParams.pidA2", ...
        "leadB0", string(prefix) + "LeadParams.leadB0", ...
        "leadB1", string(prefix) + "LeadParams.leadB1", ...
        "leadB2", string(prefix) + "LeadParams.leadB2", ...
        "leadA1", string(prefix) + "LeadParams.leadA1", ...
        "leadA2", string(prefix) + "LeadParams.leadA2", ...
        "notchB0", string(prefix) + "NotchParams.notchB0", ...
        "notchB1", string(prefix) + "NotchParams.notchB1", ...
        "notchB2", string(prefix) + "NotchParams.notchB2", ...
        "notchA1", string(prefix) + "NotchParams.notchA1", ...
        "notchA2", string(prefix) + "NotchParams.notchA2", ...
        "resoB0", string(prefix) + "ResoParams.resoB0", ...
        "resoB1", string(prefix) + "ResoParams.resoB1", ...
        "resoB2", string(prefix) + "ResoParams.resoB2", ...
        "resoA1", string(prefix) + "ResoParams.resoA1", ...
        "resoA2", string(prefix) + "ResoParams.resoA2", ...
        "enablePid", string(prefix) + "EnableParams.enablePid", ...
        "enableLead", string(prefix) + "EnableParams.enableLead", ...
        "enableNotch", string(prefix) + "EnableParams.enableNotch", ...
        "enableReso", string(prefix) + "EnableParams.enableReso");
      t = out.types;
      out.controllerRequiredProbes = {
        out.controllerParams.pidB0, t.double;
        out.controllerParams.leadB0, t.double;
        out.controllerParams.notchB0, t.double;
        out.controllerParams.enablePid, t.bool
      };
      out.requiredProbes = out.controllerRequiredProbes;
    end

    function out = from_prefix(prefix)
      out = experiment.VirtualMotorSymbols.from_vm_prefix(prefix);
    end
  end

  methods (Static, Access = private)
    function out = base_contract()
      t = twincat_ads.AdsTransport.net_types();
      out = experiment.VirtualMotorSymbols();
      out.reset = "GVL_SEQ.resetReq";
      out.modeResetReq = "GVL_MODE.resetReq";
      out.modeResetAckCounter = "GVL_MODE.resetAckCounter";
      out.hostHeartbeatCounter = "GVL_MODE.hostHeartbeatCounter";
      out.experimentActive = "GVL_SEQ.experimentActive";
      out.experimentState = "GVL_MODE.experimentState";
      out.loggerFileReleased = "GVL_MODE.loggerFileReleased";
      out.loggerErrorCode = "GVL_MODE.loggerErrorCode";
      out.tableLen = "GVL_SEQ.tableLen";
      out.idx = "GVL_SEQ.idx";
      out.repeatCount = "GVL_SEQ.repeatCount";
      out.trialIndex = "GVL_SEQ.trialIndex";
      out.modeFlags = "GVL_MODE.modeFlags";
      out.modeFlagsCandidates = ["GVL_MODE.modeFlags"];
      out.experimentStateCandidates = ["GVL_MODE.experimentState"];
      out.refTable = "GVL_SEQ.refTable";
      out.ffTable = "GVL_SEQ.ffTable";
      out.distTable = "GVL_SEQ.distTable";
      out.refValue = "GVL_SEQ.refValue";
      out.ffValue = "GVL_SEQ.ffValue";
      out.distValue = "GVL_SEQ.distValue";
      out.log = struct();
      out.vmParams = struct();
      out.controllerParams = struct();
      out.types = t;
      out.plcRequiredProbes = cell(0, 2);
      out.vmRequiredProbes = cell(0, 2);
      out.controllerRequiredProbes = cell(0, 2);
      out.requiredProbes = cell(0, 2);
    end

    function p = require_prefix(prefix, label)
      p = char(string(prefix));
      if isempty(strtrim(p))
        error("experiment:symbol:invalidPrefix", "%s is required.", label);
      end
    end
  end
end


