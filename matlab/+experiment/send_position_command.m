function out = send_position_command(varargin)
abort_condition = [];
[cfg_args, abort_condition] = split_abort_condition(varargin{:});
legacy_cfg = experiment.PositionCommandConfig.from_varargin(cfg_args{:});
cfg = experiment.ExperimentConfig.from_struct(legacy_cfg);

seq_transport = [];
ctrl_transport = [];
module_transport = [];

if ~isempty(legacy_cfg.plc_transport)
  seq_transport = legacy_cfg.plc_transport;
end
if ~isempty(legacy_cfg.control_transport)
  ctrl_transport = legacy_cfg.control_transport;
elseif ~isempty(seq_transport)
  ctrl_transport = seq_transport;
end
if ~isempty(legacy_cfg.module_transport)
  module_transport = legacy_cfg.module_transport;
end

if isempty(seq_transport)
  conn = experiment.ConnectionManager.create_plc_only(cfg);
else
  conn = experiment.ConnectionManager.from_transports(seq_transport, ctrl_transport, module_transport);
end

out = experiment.ExperimentRunner.run(conn, cfg, "abort_condition", abort_condition);
end

function [cfg_args, abort_condition] = split_abort_condition(varargin)
cfg_args = varargin;
abort_condition = [];
for k = 1:2:numel(varargin)
  if k == numel(varargin)
    break;
  end
  if strcmpi(string(varargin{k}), "abort_condition")
    abort_condition = varargin{k + 1};
    cfg_args(k:min(k + 1, numel(varargin))) = [];
    return;
  end
end
end
