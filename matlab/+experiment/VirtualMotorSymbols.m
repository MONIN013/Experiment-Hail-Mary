classdef VirtualMotorSymbols
  properties
    reset
    experiment_active
    table_len
    idx
    mode_flags
    ref_table
    ff_table
    dist_table
    ref_value
    ff_value
    control_input
    target_torque
    position_act_log
    log
    vm_params
    controller_params
    types
    plc_required_probes
    vm_required_probes
    controller_required_probes
    required_probes
  end

  methods (Static)
    function out = from_defaults()
      out = experiment.VirtualMotorSymbols.base_contract();
      t = out.types;
      out.plc_required_probes = {
        out.reset, t.bool;
        out.experiment_active, t.bool;
        out.table_len, t.u32;
        out.idx, t.u32;
        out.ref_value, t.double;
        out.ff_value, t.double;
        out.control_input, t.double;
        out.target_torque, t.double;
        out.position_act_log, t.double;
        out.log.wr_idx, t.u32;
        out.log.rd_idx, t.u32;
        out.log.overflow, t.bool
      };
      out.required_probes = out.plc_required_probes;
    end

    function out = from_vm_prefix(prefix)
      out = experiment.VirtualMotorSymbols.base_contract();
      prefix = experiment.VirtualMotorSymbols.require_prefix(prefix, "vm_param_symbol_prefix");
      out.vm_params = struct( ...
        "m", string(prefix) + "M", ...
        "d", string(prefix) + "D", ...
        "kt", string(prefix) + "Kt", ...
        "tau_limit", string(prefix) + "tau_limit", ...
        "vel_limit", string(prefix) + "vel_limit", ...
        "task_dt_ns", string(prefix) + "task_dt_ns");
      t = out.types;
      out.vm_required_probes = {
        out.vm_params.m, t.double;
        out.vm_params.d, t.double;
        out.vm_params.kt, t.double;
        out.vm_params.tau_limit, t.double;
        out.vm_params.vel_limit, t.double;
        out.vm_params.task_dt_ns, t.u64
      };
      out.required_probes = out.vm_required_probes;
    end

    function out = from_controller_prefix(prefix)
      out = experiment.VirtualMotorSymbols.base_contract();
      prefix = experiment.VirtualMotorSymbols.require_prefix(prefix, "controller_param_symbol_prefix");
      % GUI-generated ControllerCore in this repo currently uses grouped parameter structs.
      out.controller_params = struct( ...
        "pid_b0", string(prefix) + "PIDParams.notch_b0", ...
        "pid_b1", string(prefix) + "PIDParams.notch_b1", ...
        "pid_b2", string(prefix) + "PIDParams.notch_b2", ...
        "pid_a1", string(prefix) + "PIDParams.notch_a1", ...
        "pid_a2", string(prefix) + "PIDParams.notch_a2", ...
        "lead_b0", string(prefix) + "LeadParams.notch_b0", ...
        "lead_b1", string(prefix) + "LeadParams.notch_b1", ...
        "lead_b2", string(prefix) + "LeadParams.notch_b2", ...
        "lead_a1", string(prefix) + "LeadParams.notch_a1", ...
        "lead_a2", string(prefix) + "LeadParams.notch_a2", ...
        "notch_b0", string(prefix) + "NotchParams.notch_b0", ...
        "notch_b1", string(prefix) + "NotchParams.notch_b1", ...
        "notch_b2", string(prefix) + "NotchParams.notch_b2", ...
        "notch_a1", string(prefix) + "NotchParams.notch_a1", ...
        "notch_a2", string(prefix) + "NotchParams.notch_a2", ...
        "reso_b0", string(prefix) + "ResoParams.notch_b0", ...
        "reso_b1", string(prefix) + "ResoParams.notch_b1", ...
        "reso_b2", string(prefix) + "ResoParams.notch_b2", ...
        "reso_a1", string(prefix) + "ResoParams.notch_a1", ...
        "reso_a2", string(prefix) + "ResoParams.notch_a2", ...
        "enable_pid", string(prefix) + "EnableParams.enable_pid", ...
        "enable_lead", string(prefix) + "EnableParams.enable_lead", ...
        "enable_notch", string(prefix) + "EnableParams.enable_notch", ...
        "enable_reso", string(prefix) + "EnableParams.enable_reso");
      t = out.types;
      out.controller_required_probes = {
        out.controller_params.pid_b0, t.double;
        out.controller_params.lead_b0, t.double;
        out.controller_params.notch_b0, t.double;
        out.controller_params.enable_pid, t.bool
      };
      out.required_probes = out.controller_required_probes;
    end

    function out = from_prefix(prefix)
      out = experiment.VirtualMotorSymbols.from_vm_prefix(prefix);
    end
  end

  methods (Static, Access = private)
    function out = base_contract()
      t = twincat_ads.AdsTransport.net_types();
      out = experiment.VirtualMotorSymbols();
      out.reset = "GVL_EXP.reset_req";
      out.experiment_active = "GVL_EXP.experiment_active";
      out.table_len = "GVL_EXP.table_len";
      out.idx = "GVL_EXP.idx";
      out.mode_flags = "GVL_EXP.mode_flags";
      out.ref_table = "GVL_EXP.ref_table";
      out.ff_table = "GVL_EXP.ff_table";
      out.dist_table = "GVL_EXP.dist_table";
      out.ref_value = "GVL_EXP.ref_value";
      out.ff_value = "GVL_EXP.ff_value";
      out.control_input = "GVL_EXP.control_input";
      out.target_torque = "GVL_EXP.target_torque";
      out.position_act_log = "GVL_EXP.position_act_log";
      out.log = struct( ...
        "wr_idx", "GVL_EXP_LOG.wr_idx", ...
        "rd_idx", "GVL_EXP_LOG.rd_idx", ...
        "overflow", "GVL_EXP_LOG.overflow", ...
        "log_seq", "GVL_EXP_LOG.log_seq", ...
        "log_ref_value", "GVL_EXP_LOG.log_ref_value", ...
        "log_ff_value", "GVL_EXP_LOG.log_ff_value", ...
        "log_dist_value", "GVL_EXP_LOG.log_dist_value", ...
        "log_control_input", "GVL_EXP_LOG.log_control_input", ...
        "log_target_torque", "GVL_EXP_LOG.log_target_torque", ...
        "log_position_act", "GVL_EXP_LOG.log_position_act", ...
        "log_t", "GVL_EXP_LOG.log_t", ...
        "log_idx", "GVL_EXP_LOG.log_idx", ...
        "log_n", "GVL_EXP_LOG.LOG_N");
      out.vm_params = struct();
      out.controller_params = struct();
      out.types = t;
      out.plc_required_probes = cell(0, 2);
      out.vm_required_probes = cell(0, 2);
      out.controller_required_probes = cell(0, 2);
      out.required_probes = cell(0, 2);
    end

    function p = require_prefix(prefix, label)
      p = char(string(prefix));
      if isempty(strtrim(p))
        error("experiment:symbol:invalidPrefix", "%s is required.", label);
      end
    end
  end
end
