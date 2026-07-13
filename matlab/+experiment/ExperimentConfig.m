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
    external_host_heartbeat_enable = false
    external_host_heartbeat_period_s = 0.03
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
      if isscalar(varargin) && (isstruct(varargin{1}) || isa(varargin{1}, "experiment.ExperimentConfig"))
        out = experiment.ExperimentConfig.from_struct(varargin{1});
        return;
      end
      p = inputParser;
      defaults = experiment.ExperimentConfig.defaults();
      p.addParameter("env", defaults.env, @(x) isa(x, "config.EnvironmentConfig") || isstruct(x));

      p.addParameter("ads_assembly", "", @(x) ischar(x) || isstring(x));
      p.addParameter("controller", defaults.controller, ...
        @(x) isstruct(x) || isa(x, "experiment.ControllerConfig"));
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
      p.addParameter("external_host_heartbeat_enable", false, @(x) islogical(x) || isnumeric(x));
      p.addParameter("external_host_heartbeat_period_s", 0.03, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("abort_check_period_s", 0.05, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("logger_release_timeout_s", defaults.logger_release_timeout_s, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("save_path", "", @(x) ischar(x) || isstring(x));
      p.addParameter("read_logs", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("validate_symbols", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("write_controller_params", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("waveform_diag_max_shift_samples", 1, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("waveform_diag_abs_tol", 1e-12, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("waveform_diag_preview_n", 8, @(x) isnumeric(x) && isscalar(x));

      p.parse(varargin{:});

      out_struct = p.Results;
      if isfield(out_struct, "logger_release_timeout_s") && ...
          any(strcmpi(p.UsingDefaults, "logger_release_timeout_s"))
        out_struct = rmfield(out_struct, "logger_release_timeout_s");
      end
      out = experiment.ExperimentConfig.from_struct(out_struct);
    end

    function out = from_struct(s)
      if isa(s, "experiment.ExperimentConfig")
        if ~isscalar(s)
          error("experiment:config:invalid", "ExperimentConfig must be scalar.");
        end
        out = s.normalize();
        out.validate();
        return;
      end
      if ~isstruct(s) || ~isscalar(s)
        error("experiment:config:invalid", ...
          "ExperimentConfig.from_struct accepts only a scalar struct or ExperimentConfig.");
      end

      reject_unknown_inputs(s);

      out = experiment.ExperimentConfig.defaults();
      out.env = experiment.ExperimentConfig.extract_env(s, out.env);
      out.logger_release_timeout_s = double(out.env.logger_release_timeout_s);
      fields = fieldnames(s);
      for k = 1:numel(fields)
        key = fields{k};
        if strcmp(key, "env") || strcmp(key, "controller")
          continue;
        end
        if isprop(out, key)
          out.(key) = s.(key);
        end
      end
      if isfield(s, "controller")
        out.controller = experiment.ControllerConfig.from_struct(s.controller);
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
    end
  end

  methods
    function out = normalize(obj)
      out = obj;
      out.env = config.EnvironmentConfig.from_struct(out.env);
      out.ads_assembly = normalize_text_scalar(out.ads_assembly, "ads_assembly");
      out.ref_profile = normalize_numeric_waveform(out.ref_profile, "ref_profile");
      out.ff_profile = normalize_numeric_waveform(out.ff_profile, "ff_profile");
      out.dist_profile = normalize_numeric_waveform(out.dist_profile, "dist_profile");
      out.repeat_count = normalize_finite_scalar(out.repeat_count, "repeat_count");
      out.wait_for_done = normalize_boolean(out.wait_for_done, "wait_for_done");
      out.done_timeout_s = normalize_finite_scalar(out.done_timeout_s, "done_timeout_s");
      out.reset_timeout_s = normalize_finite_scalar(out.reset_timeout_s, "reset_timeout_s");
      out.hold_seconds = normalize_finite_scalar(out.hold_seconds, "hold_seconds");
      out.host_heartbeat_enable = normalize_boolean(out.host_heartbeat_enable, "host_heartbeat_enable");
      out.host_heartbeat_period_s = normalize_finite_scalar(out.host_heartbeat_period_s, "host_heartbeat_period_s");
      out.external_host_heartbeat_enable = normalize_boolean( ...
        out.external_host_heartbeat_enable, "external_host_heartbeat_enable");
      out.external_host_heartbeat_period_s = normalize_finite_scalar( ...
        out.external_host_heartbeat_period_s, "external_host_heartbeat_period_s");
      out.abort_check_period_s = normalize_finite_scalar(out.abort_check_period_s, "abort_check_period_s");
      out.logger_release_timeout_s = normalize_finite_scalar( ...
        out.logger_release_timeout_s, "logger_release_timeout_s");
      out.read_logs = normalize_boolean(out.read_logs, "read_logs");
      out.validate_symbols = normalize_boolean(out.validate_symbols, "validate_symbols");
      out.write_controller_params = normalize_boolean( ...
        out.write_controller_params, "write_controller_params");
      out.waveform_diag_max_shift_samples = normalize_finite_scalar( ...
        out.waveform_diag_max_shift_samples, "waveform_diag_max_shift_samples");
      out.waveform_diag_abs_tol = normalize_finite_scalar( ...
        out.waveform_diag_abs_tol, "waveform_diag_abs_tol");
      out.waveform_diag_preview_n = normalize_finite_scalar( ...
        out.waveform_diag_preview_n, "waveform_diag_preview_n");
      out.save_path = normalize_text_scalar(out.save_path, "save_path");
      if ~isa(out.controller, "experiment.ControllerConfig")
        out.controller = experiment.ControllerConfig.from_struct(out.controller);
      else
        out.controller = out.controller.normalize();
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
      if ~is_positive_integer(obj.repeat_count)
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
      require_positive_scalar(obj.done_timeout_s, "done_timeout_s");
      require_positive_scalar(obj.reset_timeout_s, "reset_timeout_s");
      require_nonnegative_scalar(obj.hold_seconds, "hold_seconds");
      if obj.host_heartbeat_enable && obj.external_host_heartbeat_enable
        error("experiment:config:invalid", ...
          "Internal and external host heartbeat writers cannot both be enabled.");
      end
      if ~(isnumeric(obj.host_heartbeat_period_s) && isscalar(obj.host_heartbeat_period_s) && ...
          isfinite(double(obj.host_heartbeat_period_s)) && obj.host_heartbeat_period_s > 0)
        error("experiment:config:invalid", "host_heartbeat_period_s must be > 0.");
      end
      if ~(isnumeric(obj.external_host_heartbeat_period_s) && isscalar(obj.external_host_heartbeat_period_s) && ...
          isfinite(double(obj.external_host_heartbeat_period_s)) && obj.external_host_heartbeat_period_s > 0)
        error("experiment:config:invalid", "external_host_heartbeat_period_s must be > 0.");
      end
      require_positive_scalar(obj.abort_check_period_s, "abort_check_period_s");
      require_positive_scalar(obj.logger_release_timeout_s, "logger_release_timeout_s");
      if ~(is_nonnegative_integer(obj.waveform_diag_max_shift_samples))
        error("experiment:config:invalid", ...
          "waveform_diag_max_shift_samples must be a nonnegative integer.");
      end
      require_nonnegative_scalar(obj.waveform_diag_abs_tol, "waveform_diag_abs_tol");
      if ~is_positive_integer(obj.waveform_diag_preview_n)
        error("experiment:config:invalid", ...
          "waveform_diag_preview_n must be a positive integer.");
      end
      obj.controller.validate();
      if obj.write_controller_params
        obj.controller.validate_for_task_rate(obj.env.task_rate_hz);
      end
    end

    function s = to_struct(obj)
      out = obj.normalize();
      out.validate();
      s = struct( ...
        "env", out.env.to_struct(), ...
        "ads_assembly", out.ads_assembly, ...
        "controller", out.controller.to_struct(), ...
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
        "external_host_heartbeat_enable", out.external_host_heartbeat_enable, ...
        "external_host_heartbeat_period_s", out.external_host_heartbeat_period_s, ...
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

function reject_unknown_inputs(s)
allowed = string(properties(experiment.ExperimentConfig()));
unknown = setdiff(string(fieldnames(s)), allowed);
if ~isempty(unknown)
  error("experiment:config:invalid", ...
    "Unknown ExperimentConfig field(s): %s.", strjoin(unknown, ", "));
end
end

function vec = normalize_waveform(vec, n_ref, label)
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

function vec = normalize_numeric_waveform(value, label)
if ~(isnumeric(value) && isreal(value) && (isempty(value) || isvector(value)) && ...
    all(isfinite(double(value(:)))))
  error("experiment:config:invalid", ...
    "%s must be a finite real numeric vector.", label);
end
vec = double(value(:));
end

function value = normalize_finite_scalar(value, label)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(double(value)))
  error("experiment:config:invalid", "%s must be a finite real numeric scalar.", label);
end
value = double(value);
end

function value = normalize_boolean(value, label)
if islogical(value) && isscalar(value)
  return;
end
if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(double(value)) && any(double(value) == [0, 1]))
  error("experiment:config:invalid", "%s must be a logical scalar or numeric 0/1.", label);
end
value = logical(value);
end

function value = normalize_text_scalar(value, label)
if ~(ischar(value) && (isrow(value) || isempty(value))) && ...
    ~(isstring(value) && isscalar(value) && ~ismissing(value))
  error("experiment:config:invalid", "%s must be a text scalar.", label);
end
value = char(string(value));
end

function require_positive_scalar(value, label)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(double(value)) && double(value) > 0)
  error("experiment:config:invalid", "%s must be a positive scalar.", label);
end
end

function require_nonnegative_scalar(value, label)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(double(value)) && double(value) >= 0)
  error("experiment:config:invalid", "%s must be a nonnegative scalar.", label);
end
end

function tf = is_positive_integer(value)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
  isfinite(double(value)) && double(value) >= 1 && floor(double(value)) == double(value);
end

function tf = is_nonnegative_integer(value)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
  isfinite(double(value)) && double(value) >= 0 && floor(double(value)) == double(value);
end
