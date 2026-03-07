classdef PositionCommandConfig
  properties
    ams_net_id = ""
    ams_port = []
    control_ams_port = []

    ref_profile = zeros(0, 1)
    ff_profile = zeros(0, 1)
    dist_profile = zeros(0, 1)
    task_rate_hz = []
    repeat_count = 1
    hold_seconds = NaN

    wait_for_done = true
    done_timeout_s = 30.0
    reset_timeout_s = 5.0
    host_heartbeat_enable = true
    host_heartbeat_period_s = 0.1
    logger_release_timeout_s = 5.0

    table_max_n = []
    ads_assembly = ""
    read_logs = true
    validate_symbols = true

    plc_transport = []
    control_transport = []
    module_transport = []

    mode_flags_symbol = ""
    mode_flags_ams_port = []
    mode_flags_transport = []
  end

  methods (Static)
    function out = from_varargin(varargin)
      p = inputParser;
      defaults = experiment.SystemConfig.position_command_defaults();
      p.addParameter("ams_net_id", defaults.ams_net_id, @(x) ischar(x) || isstring(x));
      p.addParameter("ams_port", defaults.ams_port, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("control_ams_port", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
      p.addParameter("ref_profile", [], @(x) isnumeric(x));
      p.addParameter("ff_profile", [], @(x) isnumeric(x));
      p.addParameter("dist_profile", [], @(x) isnumeric(x));
      p.addParameter("task_rate_hz", defaults.task_rate_hz, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("repeat_count", defaults.repeat_count, @(x) isnumeric(x) && isscalar(x));
      p.addParameter("hold_seconds", NaN, @(x) isnumeric(x) && isscalar(x) && (isnan(x) || x >= 0));
      p.addParameter("wait_for_done", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("done_timeout_s", 30.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("reset_timeout_s", 5.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("host_heartbeat_enable", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("host_heartbeat_period_s", 0.1, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("logger_release_timeout_s", defaults.logger_release_timeout_s, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("table_max_n", defaults.table_max_n, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("ads_assembly", "", @(x) ischar(x) || isstring(x));
      p.addParameter("read_logs", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("validate_symbols", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("plc_transport", [], @(x) isempty(x) || isa(x, "twincat_ads.IAdsTransport"));
      p.addParameter("control_transport", [], @(x) isempty(x) || isa(x, "twincat_ads.IAdsTransport"));
      p.addParameter("module_transport", [], @(x) isempty(x) || isa(x, "twincat_ads.IAdsTransport"));
      p.addParameter("mode_flags_symbol", defaults.mode_flags_symbol, @(x) ischar(x) || isstring(x));
      p.addParameter("mode_flags_ams_port", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
      p.addParameter("mode_flags_transport", [], @(x) isempty(x) || isa(x, "twincat_ads.IAdsTransport"));
      p.parse(varargin{:});
      out = experiment.PositionCommandConfig.from_struct(p.Results);
    end

    function out = from_struct(s)
      defaults = experiment.SystemConfig.position_command_defaults();
      seeded = defaults;
      f = fieldnames(s);
      for k = 1:numel(f)
        seeded.(f{k}) = s.(f{k});
      end

      out = experiment.PositionCommandConfig();
      f = fieldnames(seeded);
      for k = 1:numel(f)
        key = f{k};
        if isprop(out, key)
          out.(key) = seeded.(key);
        end
      end
      out = out.normalize();
      out.validate();
    end
  end

  methods
    function out = normalize(obj)
      sys = experiment.SystemConfig;
      out = obj;
      out.ams_net_id = char(string(out.ams_net_id));
      out.ams_port = double(out.ams_port);
      out.task_rate_hz = double(out.task_rate_hz);
      out.repeat_count = double(out.repeat_count);
      out.ads_assembly = char(string(out.ads_assembly));
      out.ref_profile = double(out.ref_profile(:));
      out.ff_profile = double(out.ff_profile(:));
      out.dist_profile = double(out.dist_profile(:));
      out.wait_for_done = logical(out.wait_for_done);
      out.done_timeout_s = double(out.done_timeout_s);
      out.reset_timeout_s = double(out.reset_timeout_s);
      out.host_heartbeat_enable = logical(out.host_heartbeat_enable);
      out.host_heartbeat_period_s = double(out.host_heartbeat_period_s);
      out.logger_release_timeout_s = double(out.logger_release_timeout_s);
      out.table_max_n = double(out.table_max_n);
      out.read_logs = logical(out.read_logs);
      out.validate_symbols = logical(out.validate_symbols);
      out.mode_flags_symbol = char(string(out.mode_flags_symbol));
      if isempty(out.control_ams_port)
        if out.ams_port == double(sys.SEQ_PORT)
          out.control_ams_port = double(sys.CONTROL_PORT);
        else
          out.control_ams_port = double(out.ams_port);
        end
      else
        out.control_ams_port = double(out.control_ams_port);
      end
      if isempty(out.mode_flags_ams_port)
        out.mode_flags_ams_port = [];
      else
        out.mode_flags_ams_port = double(out.mode_flags_ams_port);
      end

      n_ref = numel(out.ref_profile);
      if isempty(out.ff_profile) && n_ref > 0
        out.ff_profile = zeros(n_ref, 1);
      end
      if isempty(out.dist_profile) && n_ref > 0
        out.dist_profile = zeros(n_ref, 1);
      end
      if isnan(out.hold_seconds)
        out.hold_seconds = n_ref / out.task_rate_hz;
      else
        out.hold_seconds = double(out.hold_seconds);
      end
    end

    function validate(obj)
      if isempty(strtrim(obj.ams_net_id))
        error("experiment:position_command:invalidConfig", "ams_net_id is required.");
      end
      if isempty(obj.ref_profile)
        error("experiment:position_command:invalidConfig", ...
          "ref_profile is required and must not be empty.");
      end
      if ~(isfinite(obj.task_rate_hz) && obj.task_rate_hz > 0)
        error("experiment:position_command:invalidConfig", "task_rate_hz must be > 0.");
      end
      if ~(isfinite(obj.repeat_count) && obj.repeat_count >= 1 && floor(obj.repeat_count) == obj.repeat_count)
        error("experiment:position_command:invalidConfig", ...
          "repeat_count must be an integer >= 1.");
      end
      if numel(obj.ref_profile) > obj.table_max_n
        error("experiment:position_command:invalidConfig", ...
          "ref_profile length (%d) exceeds table_max_n (%d).", ...
          numel(obj.ref_profile), obj.table_max_n);
      end
      if numel(obj.ff_profile) ~= numel(obj.ref_profile)
        error("experiment:position_command:invalidConfig", ...
          "ff_profile length must match ref_profile length.");
      end
      if numel(obj.dist_profile) ~= numel(obj.ref_profile)
        error("experiment:position_command:invalidConfig", ...
          "dist_profile length must match ref_profile length.");
      end
      if ~(isnumeric(obj.host_heartbeat_period_s) && isscalar(obj.host_heartbeat_period_s) && obj.host_heartbeat_period_s > 0)
        error("experiment:position_command:invalidConfig", ...
          "host_heartbeat_period_s must be > 0.");
      end
      if ~(isnumeric(obj.logger_release_timeout_s) && isscalar(obj.logger_release_timeout_s) && obj.logger_release_timeout_s > 0)
        error("experiment:position_command:invalidConfig", ...
          "logger_release_timeout_s must be > 0.");
      end
      if (~isempty(obj.mode_flags_transport) || ~isempty(obj.mode_flags_ams_port)) && ...
          isempty(strtrim(obj.mode_flags_symbol))
        error("experiment:position_command:invalidConfig", ...
          "mode_flags_symbol is required when mode_flags_transport or mode_flags_ams_port is specified.");
      end
    end
  end
end
