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
        "coefficients", string(prefix) + "SosCoefficients", ...
        "sectionCount", string(prefix) + "SosSectionCount", ...
        "higsEnabled", string(prefix) + "HigsEnabled", ...
        "higsGain", string(prefix) + "HigsGain", ...
        "higsOmegaTs", string(prefix) + "HigsOmegaTs", ...
        "higsPreSectionCount", string(prefix) + "HigsPreSectionCount", ...
        "higsInput", string(prefix) + "Outputs.higsInput", ...
        "higsOutput", string(prefix) + "Outputs.higsOutput", ...
        "higsMode", string(prefix) + "Outputs.higsMode", ...
        "applyRevision", string(prefix) + "SosApplyRevision", ...
        "appliedRevision", string(prefix) + "Outputs.appliedRevision", ...
        "processedRevision", string(prefix) + "Outputs.processedRevision", ...
        "parameterErrorCode", string(prefix) + "Outputs.parameterErrorCode");
      t = out.types;
      out.controllerRequiredProbes = {
        out.controllerParams.coefficients + "[0]", t.double;
        out.controllerParams.sectionCount, t.u32;
        out.controllerParams.higsEnabled, t.bool;
        out.controllerParams.higsGain, t.double;
        out.controllerParams.higsOmegaTs, t.double;
        out.controllerParams.higsPreSectionCount, t.u32;
        out.controllerParams.applyRevision, t.u32;
        out.controllerParams.appliedRevision, t.u32;
        out.controllerParams.processedRevision, t.u32;
        out.controllerParams.parameterErrorCode, t.u32
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
