classdef VirtualMotorSymbols
  properties
    start
    reset
    currentIn
    positionOut
    velocityOut
    cmdProfile
    cmdLen
    cmdIdx
    log
    vmParams
    types
    requiredProbes
  end

  methods (Static)
    function out = fromDefaults()
      out = ehm.contracts.VirtualMotorSymbols.baseContract();
      out.requiredProbes = {
        out.start, out.types.bool;
        out.reset, out.types.bool;
        out.currentIn, out.types.double;
        out.positionOut, out.types.double;
        out.velocityOut, out.types.double;
        out.cmdLen, out.types.u32;
        out.cmdIdx, out.types.u32
      };
    end

    function out = fromPrefix(prefix)
      out = ehm.contracts.VirtualMotorSymbols.baseContract();
      prefix = char(string(prefix));
      if isempty(strtrim(prefix))
        error("ehm:symbol:invalidPrefix", "vm_param_symbol_prefix is required.");
      end

      out.vmParams = struct( ...
        "M", string(prefix) + "M", ...
        "D", string(prefix) + "D", ...
        "Kt", string(prefix) + "Kt", ...
        "tau_limit", string(prefix) + "tau_limit", ...
        "vel_limit", string(prefix) + "vel_limit", ...
        "task_dt_ns", string(prefix) + "task_dt_ns");
      out.requiredProbes = {
        out.vmParams.M, out.types.double;
        out.vmParams.D, out.types.double;
        out.vmParams.Kt, out.types.double;
        out.vmParams.tau_limit, out.types.double;
        out.vmParams.vel_limit, out.types.double;
        out.vmParams.task_dt_ns, out.types.u64
      };
    end
  end

  methods (Static, Access = private)
    function out = baseContract()
      t = ehm.adapters.twincat.TwinCATAdsTransport.netTypes();
      out = ehm.contracts.VirtualMotorSymbols();
      out.start = "GVL_VM.experiment_start";
      out.reset = "GVL_VM.reset_req";
      out.currentIn = "GVL_VM.current_in";
      out.positionOut = "GVL_VM.position_out";
      out.velocityOut = "GVL_VM.velocity_out";
      out.cmdProfile = "GVL_VM.cmd_profile";
      out.cmdLen = "GVL_VM.cmd_len";
      out.cmdIdx = "GVL_VM.cmd_idx";
      out.log = struct( ...
        "wrIdx", "GVL_VM_LOG.wr_idx", ...
        "overflow", "GVL_VM_LOG.overflow", ...
        "logSeq", "GVL_VM_LOG.log_seq", ...
        "logI", "GVL_VM_LOG.log_i", ...
        "logX", "GVL_VM_LOG.log_x", ...
        "logT", "GVL_VM_LOG.log_t");
      out.vmParams = struct( ...
        "M", "", ...
        "D", "", ...
        "Kt", "", ...
        "tau_limit", "", ...
        "vel_limit", "", ...
        "task_dt_ns", "");
      out.types = t;
      out.requiredProbes = cell(0, 2);
    end
  end
end
