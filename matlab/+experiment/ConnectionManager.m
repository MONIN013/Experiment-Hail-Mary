classdef ConnectionManager
  methods (Static)
    function conn = create(varargin)
      [cfg_args, factory] = split_transport_factory(varargin{:});
      cfg = experiment.ConnectionManager.parse_config(cfg_args{:});
      session = twincat_ads.AdsSession(cfg.ams_net_id, ...
        "ads_assembly", cfg.ads_assembly, ...
        "transport_factory", factory);
      conn = struct( ...
        "session", session, ...
        "seq", session.transport(cfg.seq_port), ...
        "ctrl", session.transport(cfg.control_port), ...
        "module", session.transport(cfg.module_port));
    end

    function conn = create_plc_only(varargin)
      [cfg_args, factory] = split_transport_factory(varargin{:});
      cfg = experiment.ConnectionManager.parse_config(cfg_args{:});
      session = twincat_ads.AdsSession(cfg.ams_net_id, ...
        "ads_assembly", cfg.ads_assembly, ...
        "transport_factory", factory);
      conn = struct( ...
        "session", session, ...
        "seq", session.transport(cfg.seq_port), ...
        "ctrl", session.transport(cfg.control_port));
    end

    function conn = from_transports(seq_transport, ctrl_transport, module_transport)
      conn = struct("session", [], "seq", seq_transport, "ctrl", ctrl_transport);
      if nargin >= 3 && ~isempty(module_transport)
        conn.module = module_transport;
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
