classdef RuntimeSymbols
  properties
    reset
    modeResetReq
    modeResetAckCounter
    hostHeartbeatCounter
    experimentActive
    modeState
    loggerFileReleased
    loggerErrorCode
    tableLen
    idx
    repeatCount
    trialIndex
    modeFlags
    refTable
    ffTable
    distTable
    refValue
    ffValue
    distValue
    log
    controllerParams
    types
    plcRequiredProbes
    modeRequiredProbes
    controllerRequiredProbes
    requiredProbes
  end

  methods (Static)
    function out = from_defaults()
      out = experiment.RuntimeSymbols.base_contract();
      t = out.types;
      out.plcRequiredProbes = {
        out.reset, t.bool;
        out.tableLen, t.u32;
        out.idx, t.u32;
        out.repeatCount, t.u32;
        out.trialIndex, t.u32;
        out.refValue, t.double;
        out.ffValue, t.double;
        out.distValue, t.double
      };
      out.modeRequiredProbes = {
        out.modeResetReq, t.bool;
        out.modeResetAckCounter, t.u32;
        out.hostHeartbeatCounter, t.u32;
        out.experimentActive, t.bool;
        out.modeFlags, t.u16;
        out.modeState, t.i16;
        out.loggerFileReleased, t.bool;
        out.loggerErrorCode, t.u32
      };
      out.requiredProbes = out.plcRequiredProbes;
    end

    function out = from_controller_prefix(prefix)
      out = experiment.RuntimeSymbols.base_contract();
      prefix = experiment.RuntimeSymbols.require_prefix(prefix, "controller_param_symbol_prefix");
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
  end

  methods (Static, Access = private)
    function out = base_contract()
      t = twincat_ads.AdsTransport.net_types();
      out = experiment.RuntimeSymbols();
      out.reset = "GVL_SEQ.resetReq";
      out.modeResetReq = "GVL_MODE.resetReq";
      out.modeResetAckCounter = "GVL_MODE.resetAckCounter";
      out.hostHeartbeatCounter = "GVL_MODE.hostHeartbeatCounter";
      out.experimentActive = "GVL_MODE.experimentActive";
      out.modeState = "GVL_MODE.modeState";
      out.loggerFileReleased = "GVL_MODE.loggerFileReleased";
      out.loggerErrorCode = "GVL_MODE.loggerErrorCode";
      out.tableLen = "GVL_SEQ.tableLen";
      out.idx = "GVL_SEQ.idx";
      out.repeatCount = "GVL_SEQ.repeatCount";
      out.trialIndex = "GVL_SEQ.trialIndex";
      out.modeFlags = "GVL_MODE.modeFlags";
      out.refTable = "GVL_SEQ.refTable";
      out.ffTable = "GVL_SEQ.ffTable";
      out.distTable = "GVL_SEQ.distTable";
      out.refValue = "GVL_SEQ.refValue";
      out.ffValue = "GVL_SEQ.ffValue";
      out.distValue = "GVL_SEQ.distValue";
      out.log = struct();
      out.controllerParams = struct();
      out.types = t;
      out.plcRequiredProbes = cell(0, 2);
      out.modeRequiredProbes = cell(0, 2);
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
