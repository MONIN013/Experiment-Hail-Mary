classdef ExperimentConfig
  properties
    env config.EnvironmentConfig = config.EnvironmentConfig()
    ads_assembly = ""

    controller experiment.ControllerConfig = experiment.ControllerConfig()

    ref_profile = zeros(0, 1)
    ff_profile = zeros(0, 1)
    dist_profile = zeros(0, 1)

    repeat_count = 1
    wait_for_done = true
    done_timeout_s = 30.0
    reset_timeout_s = 5.0
    hold_seconds = 0

    host_heartbeat_enable = true
    host_heartbeat_period_s = 0.1
    abort_check_period_s = 0.05
    logger_release_timeout_s = 5.0

    save_path = ""
    read_logs = true
    validate_symbols = true

    write_controller_params = true

    waveform_diag_max_shift_samples = 1
    waveform_diag_abs_tol = 1e-12
    waveform_diag_preview_n = 8
  end

  methods (Static)
    function out = defaults()
      out = experiment.ExperimentConfig();
      out.env = config.EnvironmentConfig.current();
      out.logger_release_timeout_s = double(out.env.logger_release_timeout_s);
      out.controller = experiment.ControllerConfig();
    end

    function out = from_varargin(varargin)
      if numel(varargin) == 1 && (isstruct(varargin{1}) || isa(varargin{1}, "experiment.ExperimentConfig"))
        out = experiment.ExperimentConfig.from_struct(varargin{1});
        return;
      end

      p = inputParser;
      defaults = experiment.ExperimentConfig.defaults();
      p.addParameter("env", defaults.env, @(x) isa(x, "config.EnvironmentConfig") || isstruct(x));
      p.addParameter("environment", [], @(x) isempty(x) || isa(x, "config.EnvironmentConfig") || isstruct(x));

      p.addParameter("ams_net_id", defaults.env.ams_net_id, @(x) ischar(x) || isstring(x));
      p.addParameter("seq_port", defaults.env.seq_port, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("control_port", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
      p.addParameter("module_port", defaults.env.module_port, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("task_rate_hz", defaults.env.task_rate_hz, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("table_max_n", defaults.env.table_max_n, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("controller_prefix", defaults.env.controller_prefix, @(x) ischar(x) || isstring(x));
      p.addParameter("controller_param_symbol_prefix", [], @(x) isempty(x) || ischar(x) || isstring(x));
      p.addParameter("logger_target_file_path", defaults.env.logger_target_file_path, @(x) ischar(x) || isstring(x));
      p.addParameter("logger_host_file_path", defaults.env.logger_host_file_path, @(x) ischar(x) || isstring(x));

      p.addParameter("ads_assembly", "", @(x) ischar(x) || isstring(x));
      p.addParameter("ref_profile", [], @isnumeric);
      p.addParameter("ff_profile", [], @isnumeric);
      p.addParameter("dist_profile", [], @isnumeric);
      p.addParameter("repeat_count", 1, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("wait_for_done", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("done_timeout_s", 30.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("reset_timeout_s", 5.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("hold_seconds", 0.0, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("host_heartbeat_enable", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("host_heartbeat_period_s", 0.1, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("abort_check_period_s", 0.05, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("logger_release_timeout_s", defaults.logger_release_timeout_s, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("save_path", "", @(x) ischar(x) || isstring(x));
      p.addParameter("read_logs", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("validate_symbols", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("write_controller_params", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("waveform_diag_max_shift_samples", 1, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("waveform_diag_abs_tol", 1e-12, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("waveform_diag_preview_n", 8, @(x) isnumeric(x) && isscalar(x));

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
      p.parse(varargin{:});

      out_struct = p.Results;
      explicit = explicit_name_value_keys(varargin);
      env_keys = ["ams_net_id", "seq_port", "control_port", "module_port", ...
        "task_rate_hz", "table_max_n", "controller_prefix", ...
        "controller_param_symbol_prefix", "logger_target_file_path", ...
        "logger_host_file_path"];
      for k = 1:numel(env_keys)
        key = char(env_keys(k));
        if isfield(out_struct, key) && ~any(explicit == lower(string(key)))
          out_struct = rmfield(out_struct, key);
        end
      end
      if isfield(out_struct, "logger_release_timeout_s") && ~any(explicit == "logger_release_timeout_s")
        out_struct = rmfield(out_struct, "logger_release_timeout_s");
      end
      out = experiment.ExperimentConfig.from_struct(out_struct);
    end

    function out = from_struct(s)
      if isa(s, "experiment.ExperimentConfig")
        out = s.normalize();
        out.validate();
        return;
      end
      if ~isstruct(s)
        error("experiment:config:invalid", ...
          "ExperimentConfig.from_struct accepts only struct or ExperimentConfig.");
      end

      reject_legacy_inputs(s);
      reject_legacy_plant_inputs(s);
      reject_removed_vm_inputs(s);

      out = experiment.ExperimentConfig.defaults();
      out.env = experiment.ExperimentConfig.extract_env(s, out.env);
      out.logger_release_timeout_s = double(out.env.logger_release_timeout_s);
      controller_struct = extract_controller_struct(s);

      fields = fieldnames(s);
      for k = 1:numel(fields)
        key = fields{k};
        if strcmp(key, "env") || strcmp(key, "environment") || is_env_input_field(key)
          continue;
        end
        if isprop(out, key)
          out.(key) = s.(key);
        end
      end
      if isfield(s, "controller")
        if isa(s.controller, "experiment.ControllerConfig")
          out.controller = s.controller;
        else
          out.controller = experiment.ControllerConfig.from_flat_struct(s.controller);
        end
      else
        out.controller = experiment.ControllerConfig.from_flat_struct(controller_struct);
      end
      out = out.normalize();
      out.validate();
    end
  end

  methods (Static, Access = private)
    function env = extract_env(s, default_env)
      env = config.EnvironmentConfig.from_struct(default_env);
      if isfield(s, "env")
        env = config.EnvironmentConfig.from_struct(s.env);
      end
      if isfield(s, "environment") && ~isempty(s.environment)
        env = config.EnvironmentConfig.from_struct(s.environment);
      end

      env_struct = struct();
      env_fields = config.EnvironmentConfig.field_names();
      for k = 1:numel(env_fields)
        key = char(env_fields(k));
        if isfield(s, key)
          env_struct.(key) = s.(key);
        end
      end
      if isfield(s, "controller_param_symbol_prefix") && ~isempty(s.controller_param_symbol_prefix)
        env_struct.controller_prefix = s.controller_param_symbol_prefix;
      end
      if ~isempty(fieldnames(env_struct))
        env = config.EnvironmentConfig.from_struct( ...
          config.EnvironmentConfig.merge_structs(env.to_struct(), env_struct));
      end
    end
  end

  methods
    function out = normalize(obj)
      out = obj;
      out.env = config.EnvironmentConfig.from_struct(out.env);
      out.ads_assembly = char(string(out.ads_assembly));
      out.ref_profile = double(out.ref_profile(:));
      out.ff_profile = double(out.ff_profile(:));
      out.dist_profile = double(out.dist_profile(:));
      out.repeat_count = double(out.repeat_count);
      out.wait_for_done = logical(out.wait_for_done);
      out.done_timeout_s = double(out.done_timeout_s);
      out.reset_timeout_s = double(out.reset_timeout_s);
      out.hold_seconds = double(out.hold_seconds);
      out.host_heartbeat_enable = logical(out.host_heartbeat_enable);
      out.host_heartbeat_period_s = double(out.host_heartbeat_period_s);
      out.abort_check_period_s = double(out.abort_check_period_s);
      out.logger_release_timeout_s = double(out.logger_release_timeout_s);
      out.read_logs = logical(out.read_logs);
      out.validate_symbols = logical(out.validate_symbols);
      out.write_controller_params = logical(out.write_controller_params);
      out.waveform_diag_max_shift_samples = double(floor(out.waveform_diag_max_shift_samples));
      out.waveform_diag_abs_tol = double(out.waveform_diag_abs_tol);
      out.waveform_diag_preview_n = double(floor(out.waveform_diag_preview_n));
      out.save_path = char(string(out.save_path));
      if ~isa(out.controller, "experiment.ControllerConfig")
        out.controller = experiment.ControllerConfig.from_flat_struct(out.controller);
      end
      n_ref = numel(out.ref_profile);
      out.ff_profile = normalize_waveform(out.ff_profile, n_ref, "ff_profile");
      out.dist_profile = normalize_waveform(out.dist_profile, n_ref, "dist_profile");
    end

    function validate(obj)
      obj.env.validate();
      if isempty(obj.ref_profile)
        error("experiment:config:invalid", "ref_profile is required and must not be empty.");
      end
      if obj.repeat_count < 1 || floor(obj.repeat_count) ~= obj.repeat_count
        error("experiment:config:invalid", "repeat_count must be an integer >= 1.");
      end
      if numel(obj.ref_profile) > obj.env.table_max_n
        error("experiment:config:invalid", ...
          "ref_profile length (%d) exceeds table_max_n (%d).", numel(obj.ref_profile), obj.env.table_max_n);
      end
      if numel(obj.ff_profile) ~= numel(obj.ref_profile)
        error("experiment:config:invalid", "ff_profile length must match ref_profile length.");
      end
      if numel(obj.dist_profile) ~= numel(obj.ref_profile)
        error("experiment:config:invalid", "dist_profile length must match ref_profile length.");
      end
      if ~(isnumeric(obj.host_heartbeat_period_s) && isscalar(obj.host_heartbeat_period_s) && obj.host_heartbeat_period_s > 0)
        error("experiment:config:invalid", "host_heartbeat_period_s must be > 0.");
      end
      if ~(isnumeric(obj.abort_check_period_s) && isscalar(obj.abort_check_period_s) && obj.abort_check_period_s > 0)
        error("experiment:config:invalid", "abort_check_period_s must be > 0.");
      end
      if ~(isnumeric(obj.logger_release_timeout_s) && isscalar(obj.logger_release_timeout_s) && obj.logger_release_timeout_s > 0)
        error("experiment:config:invalid", "logger_release_timeout_s must be > 0.");
      end
    end

    function s = to_struct(obj)
      out = obj.normalize();
      s = struct( ...
        "env", out.env.to_struct(), ...
        "ads_assembly", out.ads_assembly, ...
        "controller", out.controller.to_flat_struct(), ...
        "ref_profile", out.ref_profile, ...
        "ff_profile", out.ff_profile, ...
        "dist_profile", out.dist_profile, ...
        "repeat_count", out.repeat_count, ...
        "wait_for_done", out.wait_for_done, ...
        "done_timeout_s", out.done_timeout_s, ...
        "reset_timeout_s", out.reset_timeout_s, ...
        "hold_seconds", out.hold_seconds, ...
        "host_heartbeat_enable", out.host_heartbeat_enable, ...
        "host_heartbeat_period_s", out.host_heartbeat_period_s, ...
        "abort_check_period_s", out.abort_check_period_s, ...
        "logger_release_timeout_s", out.logger_release_timeout_s, ...
        "save_path", out.save_path, ...
        "read_logs", out.read_logs, ...
        "validate_symbols", out.validate_symbols, ...
        "write_controller_params", out.write_controller_params, ...
        "waveform_diag_max_shift_samples", out.waveform_diag_max_shift_samples, ...
        "waveform_diag_abs_tol", out.waveform_diag_abs_tol, ...
        "waveform_diag_preview_n", out.waveform_diag_preview_n);
    end
  end
end

function names = explicit_name_value_keys(args)
names = strings(0, 1);
if isempty(args)
  return;
end
for k = 1:2:numel(args)
  if k == numel(args)
    break;
  end
  if ischar(args{k}) || isstring(args{k})
    names(end + 1, 1) = lower(string(args{k}));
  end
end
end

function tf = is_env_input_field(key)
tf = any(string(key) == config.EnvironmentConfig.field_names()) || ...
  strcmp(key, "controller_param_symbol_prefix");
end

function reject_legacy_inputs(s)
legacy_keys = ["ams_port", "control_ams_port", "module_ams_port"];
for k = 1:numel(legacy_keys)
  key = char(legacy_keys(k));
  if isfield(s, key)
    error("experiment:config:invalid", ...
      "%s is no longer supported. Use cfg.env seq/control/module ports.", key);
  end
end
end

function reject_legacy_plant_inputs(s)
legacy_keys = ["m", "d", "rated_current", "max_permille", "tau_limit", "vel_limit", "plant"];
for k = 1:numel(legacy_keys)
  key = char(legacy_keys(k));
  if isfield(s, key)
    error("experiment:config:invalid", ...
      "%s is no longer supported in ExperimentConfig.", key);
  end
end
end

function reject_removed_vm_inputs(s)
removed_keys = ["write_plant_params", "vm_param_symbol_prefix"];
for k = 1:numel(removed_keys)
  key = char(removed_keys(k));
  if isfield(s, key)
    error("experiment:config:invalid", ...
      "%s is no longer supported in ExperimentConfig.", key);
  end
end
end

function out = extract_controller_struct(s)
out = struct();
keys = {"pid_b0","pid_b1","pid_b2","pid_a1","pid_a2", ...
  "lead_b0","lead_b1","lead_b2","lead_a1","lead_a2", ...
  "notch_b0","notch_b1","notch_b2","notch_a1","notch_a2", ...
  "reso_b0","reso_b1","reso_b2","reso_a1","reso_a2", ...
  "enable_pid","enable_lead","enable_notch","enable_reso"};
for k = 1:numel(keys)
  key = keys{k};
  if isfield(s, key)
    out.(key) = s.(key);
  end
end
end

function vec = normalize_waveform(vec, n_ref, label)
vec = double(vec(:));
if isempty(vec)
  vec = zeros(n_ref, 1);
  return;
end
if numel(vec) < n_ref
  vec(end + 1:n_ref, 1) = 0;
  return;
end
if numel(vec) > n_ref
  error("experiment:config:invalid", "%s length must not exceed ref_profile length.", label);
end
end
