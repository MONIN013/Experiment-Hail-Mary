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
    M = 0.01
    D = 0.1
    Kt = 1.0
    tau_limit = 5.0
    vel_limit = 100.0
    task_rate_hz = 8000
    task_dt_ns = uint64(125000)
    log_n = 200000
    ads_assembly = "TwinCAT.Ads"
    save_path = ""
  end

  methods (Static)
    function out = fromVarargin(varargin)
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
      p.addParameter("M", 0.01, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("D", 0.1, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("Kt", 1.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("tau_limit", 5.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
      p.addParameter("vel_limit", 100.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
      p.addParameter("task_rate_hz", 8000, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("log_n", 200000, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("ads_assembly", "TwinCAT.Ads", @(x) ischar(x) || isstring(x));
      p.addParameter("save_path", "", @(x) ischar(x) || isstring(x));
      p.parse(varargin{:});
      out = ehm.config.RunConfig.fromStruct(p.Results);
    end

    function out = fromStruct(s)
      out = ehm.config.RunConfig();
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
      out.cmd_max_n = uint32(out.cmd_max_n);
      out.task_dt_ns = uint64(round(1e9 / out.task_rate_hz));
      if strlength(string(out.save_path)) == 0
        stamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
        out.save_path = char(fullfile("results", "ads_validation", "virtualmotor_io_minimal_" + stamp + ".mat"));
      else
        out.save_path = char(string(out.save_path));
      end
    end

    function validate(obj)
      if isempty(strtrim(obj.ams_net_id))
        error("ehm:config:invalid", "ams_net_id is required. Example: ""192.168.10.3.1.1"".");
      end
      if isempty(strtrim(obj.vm_param_symbol_prefix))
        error("ehm:config:invalid", "vm_param_symbol_prefix is required.");
      end
    end

    function s = toStruct(obj)
      s = struct();
      p = properties(obj);
      for k = 1:numel(p)
        s.(p{k}) = obj.(p{k});
      end
    end
  end
end
