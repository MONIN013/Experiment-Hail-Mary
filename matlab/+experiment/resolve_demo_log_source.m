function out = resolve_demo_log_source(run_out, logger_bin_out)
% resolve_demo_log_source  demo 用に優先ログソースを選択する。
%
% 優先順:
%   1) ExperimentLogger bin が有効
%   2) GVL_SEQ_LOG fallback

arguments
  run_out struct
  logger_bin_out = []
end

out = struct( ...
  "source_name", "none", ...
  "signals", empty_signals(), ...
  "diagnostics", struct("reason", ""));

has_logger_bin = isstruct(logger_bin_out) && isfield(logger_bin_out, "record_count") && ...
  (double(logger_bin_out.record_count) > 0);
if has_logger_bin
  raw = logger_bin_out.raw;
  out.source_name = "experiment_logger_bin";
  out.signals = struct( ...
    "time_s", raw.t_s(:), ...
    "ref_value", raw.ref_value(:), ...
    "position_act", raw.load_position(:), ...
    "control_input", raw.control_input(:), ...
    "target_current", raw.current_cmd(:));
  out.diagnostics.reason = "logger bin records available";
  return;
end

has_fallback = isfield(run_out, "raw") && isstruct(run_out.raw) && ...
  isfield(run_out.raw, "logPositionAct") && ~isempty(run_out.raw.logPositionAct);
if has_fallback
  n = numel(run_out.raw.logPositionAct);
  time_s = [];
  if isfield(run_out, "cmd") && isfield(run_out.cmd, "task_rate_hz") && double(run_out.cmd.task_rate_hz) > 0
    time_s = (0:n-1)' / double(run_out.cmd.task_rate_hz);
  end
  out.source_name = "gvl_seq_log_fallback";
  out.signals = struct( ...
    "time_s", time_s, ...
    "ref_value", col_or_empty(run_out.raw, "logRefValue"), ...
    "position_act", col_or_empty(run_out.raw, "logPositionAct"), ...
    "control_input", col_or_empty(run_out.raw, "logControlInput"), ...
    "target_current", col_or_empty(run_out.raw, "logTargetCurrent"));
  out.diagnostics.reason = "logger bin unavailable; using GVL_SEQ_LOG";
  return;
end

out.diagnostics.reason = "no usable log samples from logger bin or GVL_SEQ_LOG";
end

function s = empty_signals()
s = struct( ...
  "time_s", zeros(0, 1), ...
  "ref_value", zeros(0, 1), ...
  "position_act", zeros(0, 1), ...
  "control_input", zeros(0, 1), ...
  "target_current", zeros(0, 1));
end

function v = col_or_empty(raw, field_name)
if isfield(raw, field_name)
  v = raw.(field_name)(:);
else
  v = zeros(0, 1);
end
end
