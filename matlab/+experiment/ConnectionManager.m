classdef ConnectionManager
  methods (Static)
    function conn = create(varargin)
      [cfg_args, factory] = split_transport_factory(varargin{:});
      cfg = experiment.ConnectionManager.parse_config(cfg_args{:});
      env = cfg.env;
      session = twincat_ads.AdsSession(env.ams_net_id, ...
        "ads_assembly", cfg.ads_assembly, ...
        "transport_factory", factory);
      conn = struct( ...
        "env", env, ...
        "session", session, ...
        "seq", session.transport(env.seq_port), ...
        "ctrl", session.transport(env.control_port), ...
        "module", session.transport(env.module_port));
    end

    function conn = create_plc_only(varargin)
      [cfg_args, factory] = split_transport_factory(varargin{:});
      cfg = experiment.ConnectionManager.parse_config(cfg_args{:});
      env = cfg.env;
      session = twincat_ads.AdsSession(env.ams_net_id, ...
        "ads_assembly", cfg.ads_assembly, ...
        "transport_factory", factory);
      conn = struct( ...
        "env", env, ...
        "session", session, ...
        "seq", session.transport(env.seq_port), ...
        "ctrl", session.transport(env.control_port));
    end

    function conn = from_transports(seq_transport, ctrl_transport, module_transport, env)
      conn = struct("session", [], "seq", seq_transport, "ctrl", ctrl_transport);
      if nargin >= 3 && ~isempty(module_transport)
        conn.module = module_transport;
      end
      if nargin >= 4 && ~isempty(env)
        conn.env = config.EnvironmentConfig.from_struct(env);
      end
    end
  end

  methods (Static, Access = private)
    function cfg = parse_config(varargin)
      if numel(varargin) == 1 && isa(varargin{1}, "experiment.ExperimentConfig")
        cfg = varargin{1};
      else
        cfg = experiment.ExperimentConfig.from_varargin(varargin{:});
      end
    end
  end
end

function [cfg_args, factory] = split_transport_factory(varargin)
cfg_args = varargin;
factory = [];
for k = 1:2:numel(varargin)
  if k == numel(varargin)
    break;
  end
  if strcmpi(string(varargin{k}), "transport_factory")
    factory = varargin{k + 1};
    cfg_args(k:min(k + 1, numel(varargin))) = [];
    return;
  end
end
end
