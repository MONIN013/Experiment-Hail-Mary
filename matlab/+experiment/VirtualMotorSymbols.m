classdef VirtualMotorSymbols
  properties
    start
    reset
    current_in
    position_out
    velocity_out
    cmd_profile
    cmd_len
    cmd_idx
    log
    vm_params
    types
    required_probes
  end

  methods (Static)
    function out = from_defaults()
      out = experiment.VirtualMotorSymbols.base_contract();
      out.required_probes = {
        out.start, out.types.bool;
        out.reset, out.types.bool;
        out.current_in, out.types.double;
        out.position_out, out.types.double;
        out.velocity_out, out.types.double;
        out.cmd_len, out.types.u32;
        out.cmd_idx, out.types.u32
      };
    end

    function out = from_prefix(prefix)
      out = experiment.VirtualMotorSymbols.base_contract();
      prefix = char(string(prefix));
      if isempty(strtrim(prefix))
        error("experiment:symbol:invalidPrefix", "vm_param_symbol_prefix is required.");
      end

      out.vm_params = struct( ...
        "m", string(prefix) + "M", ...
        "d", string(prefix) + "D", ...
        "kt", string(prefix) + "Kt", ...
        "tau_limit", string(prefix) + "tau_limit", ...
        "vel_limit", string(prefix) + "vel_limit", ...
        "task_dt_ns", string(prefix) + "task_dt_ns");
      out.required_probes = {
        out.vm_params.m, out.types.double;
        out.vm_params.d, out.types.double;
        out.vm_params.kt, out.types.double;
        out.vm_params.tau_limit, out.types.double;
        out.vm_params.vel_limit, out.types.double;
        out.vm_params.task_dt_ns, out.types.u64
      };
    end
  end

  methods (Static, Access = private)
    function out = base_contract()
      t = twincat_ads.AdsTransport.net_types();
      out = experiment.VirtualMotorSymbols();
      out.start = "GVL_VM.experiment_start";
      out.reset = "GVL_VM.reset_req";
      out.current_in = "GVL_VM.current_in";
      out.position_out = "GVL_VM.position_out";
      out.velocity_out = "GVL_VM.velocity_out";
      out.cmd_profile = "GVL_VM.cmd_profile";
      out.cmd_len = "GVL_VM.cmd_len";
      out.cmd_idx = "GVL_VM.cmd_idx";
      out.log = struct( ...
        "wr_idx", "GVL_VM_LOG.wr_idx", ...
        "rd_idx", "GVL_VM_LOG.rd_idx", ...
        "overflow", "GVL_VM_LOG.overflow", ...
        "log_seq", "GVL_VM_LOG.log_seq", ...
        "log_i", "GVL_VM_LOG.log_i", ...
        "log_x", "GVL_VM_LOG.log_x", ...
        "log_t", "GVL_VM_LOG.log_t", ...
        "log_cmd_idx", "GVL_VM_LOG.log_cmd_idx", ...
        "log_cmd_value", "GVL_VM_LOG.log_cmd_value");
      out.vm_params = struct( ...
        "m", "", ...
        "d", "", ...
        "kt", "", ...
        "tau_limit", "", ...
        "vel_limit", "", ...
        "task_dt_ns", "");
      out.types = t;
      out.required_probes = cell(0, 2);
    end
  end
end
