classdef RunConfig
  properties
    ams_net_id = ""
    ams_port = 851
    control_ams_port = []
    module_ams_port = 351
    vm_param_symbol_prefix = ""
    controller_param_symbol_prefix = ""

    ref_profile = zeros(0, 1)
    ff_profile = zeros(0, 1)
    dist_profile = zeros(0, 1)
    hold_seconds = 0.0
    wait_for_done = true
    done_timeout_s = 30.0
    reset_timeout_s = 5.0
    table_max_n = uint32(100000)

    m = 0.01
    d = 0.1
    kt = 1.0
    tau_limit = 5.0
    vel_limit = 100.0
    task_rate_hz = 1000
    task_dt_ns = uint64(1000000)

    pid_b0 = 0.0
    pid_b1 = 0.0
    pid_b2 = 0.0
    pid_a1 = 0.0
    pid_a2 = 0.0
    lead_b0 = 1.0
    lead_b1 = 0.0
    lead_b2 = 0.0
    lead_a1 = 0.0
    lead_a2 = 0.0
    notch_b0 = 1.0
    notch_b1 = 0.0
    notch_b2 = 0.0
    notch_a1 = 0.0
    notch_a2 = 0.0
    reso_b0 = 1.0
    reso_b1 = 0.0
    reso_b2 = 0.0
    reso_a1 = 0.0
    reso_a2 = 0.0
    enable_pid = true
    enable_lead = false
    enable_notch = false
    enable_reso = false

    log_n = 200000
    log_stream_enable = true
    log_poll_period_s = 0.05
    log_chunk_n = 8192
    log_host_max_n = inf
    log_warn_on_overflow = true
    log_stream_require_success = true
    log_require_complete = true
    log_require_waveform_exact = true

    waveform_diag_max_shift_samples = 1
    waveform_diag_abs_tol = 1e-12
    waveform_diag_preview_n = 8

    ads_assembly = ""
    save_path = ""
  end

  methods (Static)
    function out = from_varargin(varargin)
      p = inputParser;
      p.addParameter("ams_net_id", "", @(x) ischar(x) || isstring(x));
      p.addParameter("ams_port", 851, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("control_ams_port", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
      p.addParameter("module_ams_port", 351, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("vm_param_symbol_prefix", "", @(x) ischar(x) || isstring(x));
      p.addParameter("controller_param_symbol_prefix", "", @(x) ischar(x) || isstring(x));
      p.addParameter("ref_profile", [], @(x) isnumeric(x));
      p.addParameter("ff_profile", [], @(x) isnumeric(x));
      p.addParameter("dist_profile", [], @(x) isnumeric(x));
      p.addParameter("hold_seconds", 0.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
      p.addParameter("wait_for_done", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("done_timeout_s", 30.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("reset_timeout_s", 5.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("table_max_n", 100000, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("m", 0.01, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("d", 0.1, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("kt", 1.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("tau_limit", 5.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
      p.addParameter("vel_limit", 100.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
      p.addParameter("task_rate_hz", 1000, @(x) isnumeric(x) && isscalar(x) && x > 0);

      p.addParameter("pid_b0", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("pid_b1", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("pid_b2", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("pid_a1", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("pid_a2", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("lead_b0", 1.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("lead_b1", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("lead_b2", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("lead_a1", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("lead_a2", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("notch_b0", 1.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("notch_b1", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("notch_b2", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("notch_a1", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("notch_a2", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("reso_b0", 1.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("reso_b1", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("reso_b2", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("reso_a1", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("reso_a2", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("enable_pid", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("enable_lead", false, @(x) islogical(x) || isnumeric(x));
      p.addParameter("enable_notch", false, @(x) islogical(x) || isnumeric(x));
      p.addParameter("enable_reso", false, @(x) islogical(x) || isnumeric(x));

      p.addParameter("log_n", 200000, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("log_stream_enable", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("log_poll_period_s", 0.05, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("log_chunk_n", 8192, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("log_host_max_n", inf, @(x) isnumeric(x) && isscalar(x) && (isinf(x) || x > 0));
      p.addParameter("log_warn_on_overflow", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("log_stream_require_success", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("log_require_complete", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("log_require_waveform_exact", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("waveform_diag_max_shift_samples", 1, @(x) isnumeric(x) && isscalar(x) && x >= 0);
      p.addParameter("waveform_diag_abs_tol", 1e-12, @(x) isnumeric(x) && isscalar(x) && x >= 0);
      p.addParameter("waveform_diag_preview_n", 8, @(x) isnumeric(x) && isscalar(x) && x >= 0);
      p.addParameter("ads_assembly", "", @(x) ischar(x) || isstring(x));
      p.addParameter("save_path", "", @(x) ischar(x) || isstring(x));
      p.parse(varargin{:});
      out = experiment.RunConfig.from_struct(p.Results);
    end

    function out = from_struct(s)
      out = experiment.RunConfig();
      f = fieldnames(s);
      for k = 1:numel(f)
        key = f{k};
        if isprop(out, key)
          out.(key) = s.(key);
        end
      end
      out = out.normalize();
      out.validate();
    end
  end

  methods
    function out = normalize(obj)
      out = obj;
      out.ams_net_id = char(string(out.ams_net_id));
      out.ads_assembly = char(string(out.ads_assembly));
      out.ams_port = double(out.ams_port);
      out.module_ams_port = double(out.module_ams_port);
      out.vm_param_symbol_prefix = char(string(out.vm_param_symbol_prefix));
      out.controller_param_symbol_prefix = char(string(out.controller_param_symbol_prefix));
      if isempty(out.control_ams_port)
        if out.ams_port == 853
          out.control_ams_port = 852;
        else
          out.control_ams_port = out.ams_port;
        end
      else
        out.control_ams_port = double(out.control_ams_port);
      end
      out.ref_profile = double(out.ref_profile(:));
      out.ff_profile = double(out.ff_profile(:));
      out.dist_profile = double(out.dist_profile(:));
      n_ref = numel(out.ref_profile);
      if isempty(out.ff_profile) && n_ref > 0
        out.ff_profile = zeros(n_ref, 1);
      end
      if isempty(out.dist_profile) && n_ref > 0
        out.dist_profile = zeros(n_ref, 1);
      end
      out.wait_for_done = logical(out.wait_for_done);
      out.table_max_n = uint32(out.table_max_n);
      out.task_dt_ns = uint64(round(1e9 / out.task_rate_hz));
      out.log_stream_enable = logical(out.log_stream_enable);
      out.log_chunk_n = double(out.log_chunk_n);
      out.log_poll_period_s = double(out.log_poll_period_s);
      out.log_host_max_n = double(out.log_host_max_n);
      out.log_warn_on_overflow = logical(out.log_warn_on_overflow);
      out.log_stream_require_success = logical(out.log_stream_require_success);
      out.log_require_complete = logical(out.log_require_complete);
      out.log_require_waveform_exact = logical(out.log_require_waveform_exact);
      out.enable_pid = logical(out.enable_pid);
      out.enable_lead = logical(out.enable_lead);
      out.enable_notch = logical(out.enable_notch);
      out.enable_reso = logical(out.enable_reso);
      out.waveform_diag_max_shift_samples = double(floor(out.waveform_diag_max_shift_samples));
      out.waveform_diag_abs_tol = double(out.waveform_diag_abs_tol);
      out.waveform_diag_preview_n = double(floor(out.waveform_diag_preview_n));
      if strlength(string(out.save_path)) == 0
        stamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
        out.save_path = char(fullfile("results", "ads_validation", "experiment_sequencer_controllercore_" + stamp + ".mat"));
      else
        out.save_path = char(string(out.save_path));
      end
    end

    function validate(obj)
      if isempty(strtrim(obj.ams_net_id))
        error("experiment:config:invalid", "ams_net_id is required.");
      end
      if isempty(strtrim(obj.vm_param_symbol_prefix))
        error("experiment:config:invalid", "vm_param_symbol_prefix is required.");
      end
      if isempty(strtrim(obj.controller_param_symbol_prefix))
        error("experiment:config:invalid", "controller_param_symbol_prefix is required.");
      end
      if isempty(obj.ref_profile)
        error("experiment:config:invalid", "ref_profile is required and must not be empty.");
      end
      n_ref = numel(obj.ref_profile);
      if numel(obj.ff_profile) ~= n_ref
        error("experiment:config:invalid", "ff_profile length must match ref_profile length.");
      end
      if numel(obj.dist_profile) ~= n_ref
        error("experiment:config:invalid", "dist_profile length must match ref_profile length.");
      end
      if n_ref > double(obj.table_max_n)
        error("experiment:config:invalid", "ref_profile length (%d) exceeds table_max_n (%d).", n_ref, double(obj.table_max_n));
      end
      if ~(isnumeric(obj.log_poll_period_s) && isscalar(obj.log_poll_period_s) && obj.log_poll_period_s > 0)
        error("experiment:config:invalid", "log_poll_period_s must be > 0.");
      end
      if ~(isnumeric(obj.log_chunk_n) && isscalar(obj.log_chunk_n) && obj.log_chunk_n > 0)
        error("experiment:config:invalid", "log_chunk_n must be > 0.");
      end
      if ~(isnumeric(obj.log_host_max_n) && isscalar(obj.log_host_max_n) && (isinf(obj.log_host_max_n) || obj.log_host_max_n > 0))
        error("experiment:config:invalid", "log_host_max_n must be positive or inf.");
      end
    end

    function s = to_struct(obj)
      s = struct();
      p = properties(obj);
      for k = 1:numel(p)
        s.(p{k}) = obj.(p{k});
      end
    end
  end
end
