classdef RunConfig
  properties
    ams_net_id = ""
    ams_port = 851
    vm_ams_port = 351
    vm_param_symbol_prefix = ""
    current_in = 0.0
    current_profile = zeros(0, 1)
    hold_seconds = 1.0
    release_to_zero = true
    wait_for_done = true
    done_timeout_s = 30.0
    reset_timeout_s = 5.0
    cmd_max_n = uint32(100000)
    m = 0.01
    d = 0.1
    kt = 1.0
    tau_limit = 5.0
    vel_limit = 100.0
    task_rate_hz = 8000
    task_dt_ns = uint64(125000)
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
      p.addParameter("vm_ams_port", 351, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("vm_param_symbol_prefix", "", @(x) ischar(x) || isstring(x));
      p.addParameter("current_in", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("current_profile", [], @(x) isnumeric(x));
      p.addParameter("hold_seconds", 1.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
      p.addParameter("release_to_zero", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("wait_for_done", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("done_timeout_s", 30.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("reset_timeout_s", 5.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("cmd_max_n", 100000, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("m", 0.01, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("d", 0.1, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("kt", 1.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("tau_limit", 5.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
      p.addParameter("vel_limit", 100.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
      p.addParameter("task_rate_hz", 8000, @(x) isnumeric(x) && isscalar(x) && x > 0);
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
      out.vm_param_symbol_prefix = char(string(out.vm_param_symbol_prefix));
      out.current_profile = double(out.current_profile(:));
      out.release_to_zero = logical(out.release_to_zero);
      out.wait_for_done = logical(out.wait_for_done);
      out.log_stream_enable = logical(out.log_stream_enable);
      out.cmd_max_n = uint32(out.cmd_max_n);
      out.task_dt_ns = uint64(round(1e9 / out.task_rate_hz));
      out.log_chunk_n = double(out.log_chunk_n);
      out.log_poll_period_s = double(out.log_poll_period_s);
      out.log_host_max_n = double(out.log_host_max_n);
      out.log_warn_on_overflow = logical(out.log_warn_on_overflow);
      out.log_stream_require_success = logical(out.log_stream_require_success);
      out.log_require_complete = logical(out.log_require_complete);
      out.log_require_waveform_exact = logical(out.log_require_waveform_exact);
      out.waveform_diag_max_shift_samples = double(floor(out.waveform_diag_max_shift_samples));
      out.waveform_diag_abs_tol = double(out.waveform_diag_abs_tol);
      out.waveform_diag_preview_n = double(floor(out.waveform_diag_preview_n));
      if strlength(string(out.save_path)) == 0
        stamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
        out.save_path = char(fullfile("results", "ads_validation", "virtualmotor_io_minimal_" + stamp + ".mat"));
      else
        out.save_path = char(string(out.save_path));
      end
    end

    function validate(obj)
      if isempty(strtrim(obj.ams_net_id))
        error("experiment:config:invalid", ...
          "ams_net_id is required. Example: ""192.168.10.3.1.1"".");
      end
      if isempty(strtrim(obj.vm_param_symbol_prefix))
        error("experiment:config:invalid", "vm_param_symbol_prefix is required.");
      end
      if ~(isnumeric(obj.log_poll_period_s) && isscalar(obj.log_poll_period_s) && obj.log_poll_period_s > 0)
        error("experiment:config:invalid", "log_poll_period_s must be > 0.");
      end
      if ~(isnumeric(obj.log_chunk_n) && isscalar(obj.log_chunk_n) && obj.log_chunk_n > 0)
        error("experiment:config:invalid", "log_chunk_n must be > 0.");
      end
      if ~(isnumeric(obj.log_host_max_n) && isscalar(obj.log_host_max_n) && ...
          (isinf(obj.log_host_max_n) || obj.log_host_max_n > 0))
        error("experiment:config:invalid", "log_host_max_n must be positive or inf.");
      end
      if ~(isnumeric(obj.waveform_diag_max_shift_samples) && isscalar(obj.waveform_diag_max_shift_samples) && ...
          isfinite(obj.waveform_diag_max_shift_samples) && obj.waveform_diag_max_shift_samples >= 0 && ...
          floor(obj.waveform_diag_max_shift_samples) == obj.waveform_diag_max_shift_samples)
        error("experiment:config:invalid", "waveform_diag_max_shift_samples must be a nonnegative integer.");
      end
      if ~(isnumeric(obj.waveform_diag_abs_tol) && isscalar(obj.waveform_diag_abs_tol) && ...
          isfinite(obj.waveform_diag_abs_tol) && obj.waveform_diag_abs_tol >= 0)
        error("experiment:config:invalid", "waveform_diag_abs_tol must be a finite scalar >= 0.");
      end
      if ~(isnumeric(obj.waveform_diag_preview_n) && isscalar(obj.waveform_diag_preview_n) && ...
          isfinite(obj.waveform_diag_preview_n) && obj.waveform_diag_preview_n >= 0 && ...
          floor(obj.waveform_diag_preview_n) == obj.waveform_diag_preview_n)
        error("experiment:config:invalid", "waveform_diag_preview_n must be a nonnegative integer.");
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
