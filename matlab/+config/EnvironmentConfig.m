classdef EnvironmentConfig
% EnvironmentConfig  Machine/environment values for MATLAB runs.
%
% DEFAULT_* constants are repository initial values only. Machine-local
% overrides are generated into config.LocalEnvironmentConfig by setup.

  properties (Constant)
    DEFAULT_AMS_NET_ID = "local"
    DEFAULT_SEQ_PORT = 853
    DEFAULT_CONTROL_PORT = 852
    DEFAULT_MODULE_PORT = 351
    DEFAULT_TASK_RATE_HZ = 8000
    DEFAULT_CONTROLLER_PREFIX = "ControllerCore_Obj1 (Module1)."
    DEFAULT_LOGGER_TARGET_FILE_PATH = "C:\ExperimentData\experiment_logger.bin"
    DEFAULT_LOGGER_HOST_FILE_PATH = "C:\ExperimentData\experiment_logger.bin"
    % DEFAULT_LOGGER_HOST_FILE_PATH = "\\sunnyday\ExperimentData\experiment_logger.bin"
    DEFAULT_TABLE_MAX_N = 100000
    DEFAULT_LOGGER_RELEASE_TIMEOUT_S = 5.0
  end

  properties
    ams_net_id = config.EnvironmentConfig.DEFAULT_AMS_NET_ID
    seq_port = config.EnvironmentConfig.DEFAULT_SEQ_PORT
    control_port = config.EnvironmentConfig.DEFAULT_CONTROL_PORT
    module_port = config.EnvironmentConfig.DEFAULT_MODULE_PORT
    task_rate_hz = config.EnvironmentConfig.DEFAULT_TASK_RATE_HZ
    controller_prefix = config.EnvironmentConfig.DEFAULT_CONTROLLER_PREFIX
    logger_target_file_path = config.EnvironmentConfig.DEFAULT_LOGGER_TARGET_FILE_PATH
    logger_host_file_path = config.EnvironmentConfig.DEFAULT_LOGGER_HOST_FILE_PATH
    table_max_n = config.EnvironmentConfig.DEFAULT_TABLE_MAX_N
    logger_release_timeout_s = config.EnvironmentConfig.DEFAULT_LOGGER_RELEASE_TIMEOUT_S
  end

  methods (Static)
    function out = defaults()
      out = config.EnvironmentConfig();
      out = out.normalize();
      out.validate();
    end

    function out = current(varargin)
      p = inputParser;
      p.addParameter("use_local", true, @(x) islogical(x) || isnumeric(x));
      p.parse(varargin{:});

      out = config.EnvironmentConfig.defaults();
      if logical(p.Results.use_local) && exist("config.LocalEnvironmentConfig", "class") == 8
        local = config.LocalEnvironmentConfig.to_struct();
        out = config.EnvironmentConfig.from_struct( ...
          config.EnvironmentConfig.merge_structs(out.to_struct(), local));
      end
    end

    function out = from_struct(s)
      if isa(s, "config.EnvironmentConfig")
        out = s.normalize();
        out.validate();
        return;
      end
      if ~isstruct(s)
        error("config:EnvironmentConfig:invalid", ...
          "EnvironmentConfig.from_struct accepts only struct or EnvironmentConfig.");
      end

      allowed = config.EnvironmentConfig.field_names();
      actual = string(fieldnames(s));
      unknown = setdiff(actual, allowed);
      if ~isempty(unknown)
        error("config:EnvironmentConfig:invalid", ...
          "Unknown environment field(s): %s.", strjoin(unknown, ", "));
      end

      out = config.EnvironmentConfig.defaults();
      for k = 1:numel(actual)
        key = char(actual(k));
        out.(key) = s.(key);
      end
      out = out.normalize();
      out.validate();
    end

    function file_path = local_config_file()
      file_path = fullfile(fileparts(mfilename("fullpath")), "LocalEnvironmentConfig.m");
    end

    function fields = field_names()
      fields = [
        "ams_net_id"
        "seq_port"
        "control_port"
        "module_port"
        "task_rate_hz"
        "controller_prefix"
        "logger_target_file_path"
        "logger_host_file_path"
        "table_max_n"
        "logger_release_timeout_s"
      ];
    end

    function out = merge_structs(base, override)
      out = base;
      fields = fieldnames(override);
      for k = 1:numel(fields)
        out.(fields{k}) = override.(fields{k});
      end
    end
  end

  methods
    function out = normalize(obj)
      out = obj;
      out.ams_net_id = string(out.ams_net_id);
      out.seq_port = coerce_double(out.seq_port, "seq_port");
      out.control_port = coerce_double(out.control_port, "control_port");
      out.module_port = coerce_double(out.module_port, "module_port");
      out.task_rate_hz = coerce_double(out.task_rate_hz, "task_rate_hz");
      out.controller_prefix = string(out.controller_prefix);
      out.logger_target_file_path = string(out.logger_target_file_path);
      out.logger_host_file_path = string(out.logger_host_file_path);
      out.table_max_n = coerce_double(out.table_max_n, "table_max_n");
      out.logger_release_timeout_s = coerce_double(out.logger_release_timeout_s, "logger_release_timeout_s");
    end

    function validate(obj)
      if strlength(strtrim(string(obj.ams_net_id))) == 0
        error("config:EnvironmentConfig:invalid", "ams_net_id is required.");
      end
      must_be_positive_integer(obj.seq_port, "seq_port");
      must_be_positive_integer(obj.control_port, "control_port");
      must_be_positive_integer(obj.module_port, "module_port");
      must_be_positive_scalar(obj.task_rate_hz, "task_rate_hz");
      must_be_positive_integer(obj.table_max_n, "table_max_n");
      must_be_positive_scalar(obj.logger_release_timeout_s, "logger_release_timeout_s");
      if strlength(strtrim(string(obj.controller_prefix))) == 0
        error("config:EnvironmentConfig:invalid", "controller_prefix is required.");
      end
      if strlength(strtrim(string(obj.logger_target_file_path))) == 0
        error("config:EnvironmentConfig:invalid", "logger_target_file_path is required.");
      end
      if strlength(strtrim(string(obj.logger_host_file_path))) == 0
        error("config:EnvironmentConfig:invalid", "logger_host_file_path is required.");
      end
    end

    function s = to_struct(obj)
      out = obj.normalize();
      s = struct( ...
        "ams_net_id", out.ams_net_id, ...
        "seq_port", out.seq_port, ...
        "control_port", out.control_port, ...
        "module_port", out.module_port, ...
        "task_rate_hz", out.task_rate_hz, ...
        "controller_prefix", out.controller_prefix, ...
        "logger_target_file_path", out.logger_target_file_path, ...
        "logger_host_file_path", out.logger_host_file_path, ...
        "table_max_n", out.table_max_n, ...
        "logger_release_timeout_s", out.logger_release_timeout_s);
    end

    function task_dt_ns = task_dt_ns(obj)
      env = obj.normalize();
      task_dt_ns = uint64(round(1e9 / double(env.task_rate_hz)));
    end
  end
end

function must_be_positive_scalar(value, name)
if ~(isnumeric(value) && isscalar(value) && isfinite(double(value)) && double(value) > 0)
  error("config:EnvironmentConfig:invalid", "%s must be a positive scalar.", name);
end
end

function value = coerce_double(value, name)
if ~(isnumeric(value) && isscalar(value))
  error("config:EnvironmentConfig:invalid", "%s must be a numeric scalar.", name);
end
value = double(value);
end

function must_be_positive_integer(value, name)
must_be_positive_scalar(value, name);
if floor(double(value)) ~= double(value)
  error("config:EnvironmentConfig:invalid", "%s must be an integer.", name);
end
end
