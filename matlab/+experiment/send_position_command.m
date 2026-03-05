function out = send_position_command(varargin)
cfg = experiment.PositionCommandConfig.from_varargin(varargin{:});
plc_symbols = experiment.VirtualMotorSymbols.from_defaults();
plc_transport = [];
ctrl_transport = [];
module_transport = [];
mode_flags_transport = [];
owns_transport = false;
owns_ctrl_transport = false;
owns_module_transport = false;
owns_mode_flags_transport = false;
mode_flags_symbol = "";
logger_path = "C:\ExperimentData\experiment_logger.bin";
logger_before = empty_logger_status(logger_path);
logger_after = empty_logger_status(logger_path);

if isempty(cfg.plc_transport)
  plc_transport = twincat_ads.AdsTransport("ads_assembly", cfg.ads_assembly);
  owns_transport = true;
  plc_transport.connect(cfg.ams_net_id, cfg.ams_port);
else
  if ~isa(cfg.plc_transport, "twincat_ads.IAdsTransport")
    error("experiment:position_command:invalidConfig", ...
      "plc_transport must implement twincat_ads.IAdsTransport.");
  end
  plc_transport = cfg.plc_transport;
end

if isempty(cfg.control_transport)
  if isempty(cfg.plc_transport)
    if cfg.control_ams_port == cfg.ams_port
      ctrl_transport = plc_transport;
    else
      ctrl_transport = twincat_ads.AdsTransport("ads_assembly", cfg.ads_assembly);
      owns_ctrl_transport = true;
      ctrl_transport.connect(cfg.ams_net_id, cfg.control_ams_port);
    end
  else
    ctrl_transport = plc_transport;
  end
else
  if ~isa(cfg.control_transport, "twincat_ads.IAdsTransport")
    error("experiment:position_command:invalidConfig", ...
      "control_transport must implement twincat_ads.IAdsTransport.");
  end
  ctrl_transport = cfg.control_transport;
end

if isempty(cfg.module_transport)
  module_transport = [];
else
  if ~isa(cfg.module_transport, "twincat_ads.IAdsTransport")
    error("experiment:position_command:invalidConfig", ...
      "module_transport must implement twincat_ads.IAdsTransport.");
  end
  module_transport = cfg.module_transport;
end

if cfg.validate_symbols
  twincat_ads.SymbolBrowser.validate_symbols(plc_transport, plc_symbols.plcRequiredProbes);
end

t = plc_symbols.types;
ctrl = experiment.ModeManagerControl.resolve_symbols( ...
  ctrl_transport, plc_symbols, "experiment:position_command:invalidConfig");
heartbeat_state = experiment.ModeManagerControl.init_heartbeat( ...
  ctrl_transport, ctrl, cfg.host_heartbeat_enable, cfg.host_heartbeat_period_s);
[mode_flags_transport, owns_mode_flags_transport] = resolve_mode_flags_transport( ...
  cfg, plc_transport, ctrl_transport, owns_mode_flags_transport);
[ctrl, mode_flags_symbol] = resolve_mode_flags_symbol( ...
  cfg, mode_flags_transport, ctrl, plc_symbols);
cleanup_obj = onCleanup(@()cleanup_transports( ...
  plc_transport, ctrl_transport, module_transport, mode_flags_transport, ...
  owns_transport, owns_ctrl_transport, owns_module_transport, ...
  owns_mode_flags_transport, plc_symbols, mode_flags_symbol)); %#ok<NASGU>
assert_split_port_modeflags_config(cfg, plc_transport, ctrl_transport, ctrl);
done = false;
timed_out = false;
servo_ready = false;
servo_ready_check_supported = false;
servo_ready_diag = struct();
control_runtime_diag = struct();
t_run = tic;

if ~isempty(module_transport)
  logger_before = read_logger_status(module_transport, t, logger_path);
end

write_mode_flags(mode_flags_transport, ctrl, uint32(0));
plc_transport.write_scalar(plc_symbols.tableLen, uint32(0), t.u32);
[reset_acked, reset_diag, heartbeat_state] = request_reset_and_wait_ack( ...
  ctrl_transport, ctrl, cfg.reset_timeout_s, heartbeat_state);
if ~reset_acked
  error("experiment:position_command:resetAckTimeout", ...
    "Timed out waiting reset acknowledgement (resetAckCounter before=%g after=%g).", ...
    reset_diag.counter_before, reset_diag.counter_after);
end

[idle_ready, idle_diag, heartbeat_state] = wait_for_reset_idle( ...
  plc_transport, ctrl_transport, plc_symbols, ctrl, cfg.reset_timeout_s, heartbeat_state);
if ~idle_ready
  error("experiment:position_command:resetSyncTimeout", ...
    "Timed out waiting reset idle state (idx==0, experimentActive==FALSE). Observed idx=%g experimentActive=%d modeFlagsSymbol=%s", ...
    idle_diag.idx, logical(idle_diag.experiment_active), char(string(ctrl.modeFlagsSymbol)));
end

table_n = numel(cfg.ref_profile);
plc_transport.write_array(plc_symbols.refTable, cfg.ref_profile, t.double);
plc_transport.write_array(plc_symbols.ffTable, cfg.ff_profile, t.double);
plc_transport.write_array(plc_symbols.distTable, cfg.dist_profile, t.double);
plc_transport.write_scalar(plc_symbols.repeatCount, uint32(cfg.repeat_count), t.u32);
plc_transport.write_scalar(plc_symbols.tableLen, uint32(table_n), t.u32);

write_mode_flags(mode_flags_transport, ctrl, uint32(ctrl.MODEF_SERVO_ENABLE));
[servo_ready, servo_ready_check_supported, servo_ready_diag, heartbeat_state] = wait_until_ready( ...
  ctrl_transport, plc_symbols, ctrl, min(cfg.done_timeout_s, 5.0), heartbeat_state);
if servo_ready_check_supported && ~servo_ready
  control_runtime_diag = read_control_runtime_diag(ctrl_transport, t);
  warning("experiment:position_command:servoReadyTimeout", ...
    "Timed out waiting for servo ready/start precondition after MODEF_SERVO_ENABLE (last experimentState=%s driveReady=%s driveState=%s statWord=%s ctrlWord=%s).", ...
    fmt_diag_value(servo_ready_diag.last_experiment_state), ...
    fmt_diag_value(control_runtime_diag.driveReady), ...
    fmt_diag_value(control_runtime_diag.driveState), ...
    fmt_diag_value(control_runtime_diag.statWord), ...
    fmt_diag_value(control_runtime_diag.ctrlWord));
end
write_mode_flags(mode_flags_transport, ctrl, uint32(bitor(ctrl.MODEF_SERVO_ENABLE, ctrl.MODEF_EXPERIMENT_START_REQ)));

if cfg.wait_for_done
  [done, heartbeat_state] = wait_until_done( ...
    plc_transport, ctrl_transport, plc_symbols, ctrl, cfg.done_timeout_s, heartbeat_state);
  timed_out = ~done;
  if timed_out
    if isempty(fieldnames(control_runtime_diag))
      control_runtime_diag = read_control_runtime_diag(ctrl_transport, t);
    end
    warning("experiment:position_command:timeout", ...
      "Timed out waiting for position command completion (experimentState=%s experimentActive=%s driveReady=%s driveState=%s).", ...
      fmt_diag_value(control_runtime_diag.experimentState), ...
      fmt_diag_value(control_runtime_diag.experimentActive), ...
      fmt_diag_value(control_runtime_diag.driveReady), ...
      fmt_diag_value(control_runtime_diag.driveState));
  end
else
  done = false;
  while toc(t_run) < cfg.hold_seconds
    heartbeat_state = experiment.ModeManagerControl.tick_heartbeat( ...
      ctrl_transport, ctrl, heartbeat_state, false);
    pause(min(0.05, cfg.hold_seconds / 10 + eps));
  end
end

write_mode_flags(mode_flags_transport, ctrl, uint32(0));
elapsed_s = toc(t_run);

if ~isempty(module_transport)
  logger_after = read_logger_status(module_transport, t, logger_path);
  [logger_after.file_released, logger_after.file_probe_detail] = probe_logger_file_release(logger_path);
end

position_last = double(plc_transport.read_scalar(plc_symbols.positionActLog, t.double));
control_input_last = double(plc_transport.read_scalar(plc_symbols.controlInput, t.double));

log_data = read_logger_bin_or_empty(logger_path);

out = struct();
out.cmd = struct( ...
  "ref_profile", cfg.ref_profile, ...
  "ff_profile", cfg.ff_profile, ...
  "dist_profile", cfg.dist_profile, ...
  "table_len", table_n, ...
  "repeat_count", double(cfg.repeat_count), ...
  "task_rate_hz", cfg.task_rate_hz);
out.host = struct( ...
  "elapsed_s", elapsed_s, ...
  "wait_for_done", logical(cfg.wait_for_done), ...
  "done", logical(done), ...
  "timed_out", logical(timed_out), ...
  "servo_ready", logical(servo_ready), ...
  "servo_ready_check_supported", logical(servo_ready_check_supported), ...
  "servo_ready_diag", servo_ready_diag, ...
  "control_runtime_diag", control_runtime_diag, ...
  "control_ams_port", double(cfg.control_ams_port), ...
  "host_heartbeat_enable", logical(cfg.host_heartbeat_enable), ...
  "host_heartbeat_period_s", double(cfg.host_heartbeat_period_s), ...
  "mode_flags_symbol", char(string(ctrl.modeFlagsSymbol)), ...
  "experiment_state_symbol", char(string(ctrl.experimentStateSymbol)), ...
  "control_mode_flags_symbol", char(string(ctrl.modeFlagsSymbol)), ...
  "control_experiment_state_symbol", char(string(ctrl.experimentStateSymbol)));
out.raw = struct( ...
  "position_last", position_last, ...
  "control_input_last", control_input_last, ...
  "logRefValue", log_data.logRefValue, ...
  "logFfValue", log_data.logFfValue, ...
  "logDistValue", log_data.logDistValue, ...
  "logControlInput", log_data.logControlInput, ...
  "logTargetCurrent", log_data.logTargetCurrent, ...
  "logPositionAct", log_data.logPositionAct, ...
  "logSeq", log_data.logSeq, ...
  "logT", log_data.logT, ...
  "logIdx", log_data.logIdx, ...
  "log_wrIdx", log_data.wrIdx, ...
  "log_overflow", logical(log_data.overflow));
out.logger = struct( ...
  "file_path", char(string(logger_path)), ...
  "ready_before", logical(logger_before.ready), ...
  "ready_after", logical(logger_after.ready), ...
  "error_before", double(logger_before.error_code), ...
  "error_after", double(logger_after.error_code), ...
  "records_before", double(logger_before.records_written), ...
  "records_after", double(logger_after.records_written), ...
  "file_released", logical(logger_after.file_released), ...
  "file_probe_detail", char(string(logger_after.file_probe_detail)));
out.eval = build_count_eval(out.cmd, out.raw);
end

function cleanup_transports(plc_transport, ctrl_transport, module_transport, mode_flags_transport, ...
    owns_transport, owns_ctrl_transport, owns_module_transport, owns_mode_flags_transport, plc_symbols, mode_flags_symbol)
if isempty(plc_transport) && isempty(ctrl_transport)
  return;
end

same_transport = ~isempty(plc_transport) && ~isempty(ctrl_transport) && (plc_transport == ctrl_transport);
same_mode_ctrl = ~isempty(mode_flags_transport) && ~isempty(ctrl_transport) && (mode_flags_transport == ctrl_transport);
same_mode_plc = ~isempty(mode_flags_transport) && ~isempty(plc_transport) && (mode_flags_transport == plc_transport);
same_module_plc = ~isempty(module_transport) && ~isempty(plc_transport) && (module_transport == plc_transport);
same_module_ctrl = ~isempty(module_transport) && ~isempty(ctrl_transport) && (module_transport == ctrl_transport);
same_module_mode = ~isempty(module_transport) && ~isempty(mode_flags_transport) && (module_transport == mode_flags_transport);
if owns_mode_flags_transport && ~same_mode_ctrl && ~same_mode_plc
  try
    mode_flags_transport.disconnect();
  catch
  end
end
if owns_module_transport && ~same_module_plc && ~same_module_ctrl && ~same_module_mode
  try
    module_transport.disconnect();
  catch
  end
end
if owns_ctrl_transport && ~same_transport
  try
    ctrl_transport.disconnect();
  catch
  end
end
if owns_transport
  try
    plc_transport.disconnect();
  catch
  end
end
end

function write_mode_flags(plc_transport, ctrl, value)
experiment.ModeManagerControl.write_mode_flags(plc_transport, ctrl, value);
end

function [acked, diag, heartbeat_state] = request_reset_and_wait_ack( ...
    control_transport, ctrl, timeout_s, heartbeat_state)
[acked, diag, heartbeat_state] = experiment.ModeManagerControl.request_reset_and_wait_ack( ...
  control_transport, ctrl, timeout_s, heartbeat_state);
end

function [mode_flags_transport, owns_mode_flags_transport] = resolve_mode_flags_transport( ...
    cfg, plc_transport, ctrl_transport, owns_mode_flags_transport)
if ~isempty(cfg.mode_flags_transport)
  mode_flags_transport = cfg.mode_flags_transport;
  return;
end

if isempty(cfg.mode_flags_ams_port)
  mode_flags_transport = ctrl_transport;
  return;
end

if cfg.mode_flags_ams_port == cfg.ams_port
  mode_flags_transport = plc_transport;
  return;
end
if cfg.mode_flags_ams_port == cfg.control_ams_port
  mode_flags_transport = ctrl_transport;
  return;
end

mode_flags_transport = twincat_ads.AdsTransport("ads_assembly", cfg.ads_assembly);
owns_mode_flags_transport = true;
mode_flags_transport.connect(cfg.ams_net_id, cfg.mode_flags_ams_port);
end

function [ctrl, mode_flags_symbol] = resolve_mode_flags_symbol(cfg, mode_flags_transport, ctrl, plc_symbols)
if isempty(strtrim(cfg.mode_flags_symbol))
  mode_flags_symbol = char(string(ctrl.modeFlagsSymbol));
  assert_supported_mode_flags_symbol(mode_flags_symbol);
  return;
end

mode_t = experiment.ModeManagerControl.modeflags_type(plc_symbols.types);
mode_flags_symbol = char(string(cfg.mode_flags_symbol));
assert_supported_mode_flags_symbol(mode_flags_symbol);
current_value = mode_flags_transport.read_scalar(mode_flags_symbol, mode_t);
mode_flags_transport.write_scalar(mode_flags_symbol, cast_modeflags_value(mode_t, current_value), mode_t);
ctrl.modeFlagsSymbol = mode_flags_symbol;
end

function assert_split_port_modeflags_config(cfg, plc_transport, ctrl_transport, ctrl)
same_transport = ~isempty(plc_transport) && ~isempty(ctrl_transport) && (plc_transport == ctrl_transport);
has_explicit_modeflags = ~isempty(strtrim(cfg.mode_flags_symbol)) || ...
  ~isempty(cfg.mode_flags_transport) || ~isempty(cfg.mode_flags_ams_port);
if same_transport || has_explicit_modeflags
  return;
end
if string(ctrl.modeFlagsSymbol) == "GVL_MODE.modeFlags"
  return;
end
invalid_config([ ...
  'Split-port configuration detected (ams_port=%d, control_ams_port=%d) but resolved modeFlags target is ''%s''. ' ...
  'Only ''GVL_MODE.modeFlags'' is supported. Set mode_flags_symbol=''GVL_MODE.modeFlags'' and use control transport/port 852.'], ...
  double(cfg.ams_port), double(cfg.control_ams_port), char(string(ctrl.modeFlagsSymbol)));
end

function assert_supported_mode_flags_symbol(mode_flags_symbol)
if string(mode_flags_symbol) ~= "GVL_MODE.modeFlags"
  invalid_config([ ...
    "Unsupported mode_flags_symbol '%s'. " + ...
    "Only 'GVL_MODE.modeFlags' is supported."], char(string(mode_flags_symbol)));
end
end

function v = cast_modeflags_value(net_type, value)
v = uint16(double(value));
end

function [ready, diag, heartbeat_state] = wait_for_reset_idle( ...
    plc_transport, ctrl_transport, symbols, ctrl, timeout_s, heartbeat_state)
[ready, diag, heartbeat_state] = experiment.ModeManagerControl.wait_for_reset_idle( ...
  plc_transport, ctrl_transport, symbols, ctrl, timeout_s, heartbeat_state);
end

function [ready, supported, diag, heartbeat_state] = wait_until_ready( ...
    ctrl_transport, symbols, ctrl, timeout_s, heartbeat_state)
t = symbols.types;
t0 = tic;
ready = false;
diag = struct("last_experiment_state", NaN);
supported = strlength(string(ctrl.experimentStateSymbol)) > 0;
if ~supported
  return;
end
while toc(t0) < timeout_s
  try
    state = uint32(ctrl_transport.read_scalar(ctrl.experimentStateSymbol, t.u32));
    diag.last_experiment_state = double(state);
    if state == ctrl.STATE_READY || state == ctrl.STATE_DONE
      ready = true;
      return;
    end
  catch
    supported = false;
    ready = false;
    return;
  end
  heartbeat_state = experiment.ModeManagerControl.tick_heartbeat( ...
    ctrl_transport, ctrl, heartbeat_state, false);
  pause(0.01);
end
end

function [done, heartbeat_state] = wait_until_done( ...
    plc_transport, ctrl_transport, symbols, ctrl, timeout_s, heartbeat_state)
[done, heartbeat_state] = experiment.ModeManagerControl.wait_until_done( ...
  ctrl_transport, plc_transport, symbols, ctrl, timeout_s, heartbeat_state);
end

function diag = read_control_runtime_diag(ctrl_transport, t)
diag = struct( ...
  "experimentState", NaN, ...
  "experimentActive", NaN, ...
  "driveReady", NaN, ...
  "driveState", NaN, ...
  "statWord", NaN, ...
  "ctrlWord", NaN);

diag.experimentState = try_read_scalar(ctrl_transport, "GVL_MODE.experimentState", t.u32);
diag.experimentActive = try_read_scalar(ctrl_transport, "GVL_MODE.experimentActive", t.bool);
diag.driveReady = try_read_scalar(ctrl_transport, "MAIN.driveReady", t.bool);
if ~isfield(t, "u16")
  error("experiment:position_command:invalidConfig", ...
    "ADS net type mapping must include u16 for MAIN.driveState/statWord/ctrlWord.");
end
u16 = t.u16;
diag.driveState = try_read_scalar(ctrl_transport, "MAIN.fbStateMachine.driveState", u16);
diag.statWord = try_read_scalar(ctrl_transport, "MAIN.statWord", u16);
diag.ctrlWord = try_read_scalar(ctrl_transport, "MAIN.ctrlWord", u16);
end

function v = try_read_scalar(transport, symbol, net_type)
try
  v_raw = transport.read_scalar(symbol, net_type);
  if islogical(v_raw)
    v = logical(v_raw);
  else
    v = double(v_raw);
  end
catch
  v = NaN;
end
end

function s = fmt_diag_value(v)
if islogical(v)
  s = char(string(double(v)));
elseif isnumeric(v) && isscalar(v) && isfinite(v)
  s = char(string(v));
else
  s = "NA";
end
end

function out = empty_logger_log_data()
out = struct( ...
  "logSeq", zeros(0, 1), ...
  "logRefValue", zeros(0, 1), ...
  "logFfValue", zeros(0, 1), ...
  "logDistValue", zeros(0, 1), ...
  "logControlInput", zeros(0, 1), ...
  "logTargetCurrent", zeros(0, 1), ...
  "logPositionAct", zeros(0, 1), ...
  "logT", zeros(0, 1), ...
  "logIdx", zeros(0, 1), ...
  "wrIdx", 0, ...
  "overflow", false);
end

function log_data = read_logger_bin_or_empty(logger_path)
if ~isfile(logger_path)
  log_data = empty_logger_log_data();
  return;
end
try
  logger_out = experiment.read_logger_bin(logger_path);
catch e
  warning("experiment:position_command:loggerBinReadFailed", ...
    "ExperimentLogger bin read failed; returning empty log payload (%s: %s).", ...
    string(e.identifier), string(e.message));
  log_data = empty_logger_log_data();
  return;
end

sample_n = numel(logger_out.time_s);
log_data = struct( ...
  "logSeq", double((1:sample_n)'), ...
  "logRefValue", double(logger_out.ref_value(:)), ...
  "logFfValue", double(logger_out.ff_value(:)), ...
  "logDistValue", double(logger_out.dist_value(:)), ...
  "logControlInput", double(logger_out.control_input(:)), ...
  "logTargetCurrent", double(logger_out.target_current(:)), ...
  "logPositionAct", double(logger_out.load_position(:)), ...
  "logT", double(round(logger_out.time_s(:) * 1e9)), ...
  "logIdx", double((0:max(sample_n - 1, 0))'), ...
  "wrIdx", double(sample_n), ...
  "overflow", false);
end

function ev = build_count_eval(cmd, raw)
n_cmd = numel(cmd.ref_profile) * max(1, double(cmd.repeat_count));
n_seq = numel(raw.logSeq);
n_ref = numel(raw.logRefValue);
n_ff = numel(raw.logFfValue);
n_dist = numel(raw.logDistValue);
n_u = numel(raw.logControlInput);
n_tau = numel(raw.logTargetCurrent);
n_pos = numel(raw.logPositionAct);

counts_match_each_other = (n_seq == n_ref) && (n_ref == n_ff) && (n_ff == n_dist) && ...
  (n_dist == n_u) && (n_u == n_tau) && (n_tau == n_pos);
input_match_ref = (n_cmd == n_ref);
input_match_pos = (n_cmd == n_pos);

ev = struct( ...
  "input_count", n_cmd, ...
  "log_seq_count", n_seq, ...
  "log_ref_count", n_ref, ...
  "log_ff_count", n_ff, ...
  "log_dist_count", n_dist, ...
  "log_control_input_count", n_u, ...
  "log_target_current_count", n_tau, ...
  "log_position_count", n_pos, ...
  "log_available", (n_ref > 0 || n_pos > 0 || n_seq > 0), ...
  "log_component_counts_match", logical(counts_match_each_other), ...
  "input_count_matches_log_ref", logical(input_match_ref), ...
  "input_count_matches_log_position", logical(input_match_pos), ...
  "input_and_all_log_counts_match", logical(counts_match_each_other && input_match_ref && input_match_pos));
end

function invalid_config(varargin)
error("experiment:position_command:invalidConfig", varargin{:});
end

function status = empty_logger_status(logger_path)
status = struct( ...
  "file_path", char(string(logger_path)), ...
  "ready", false, ...
  "error_code", 0, ...
  "records_written", 0, ...
  "file_released", false, ...
  "file_probe_detail", "");
end

function status = read_logger_status(module_transport, net_types, logger_path)
status = empty_logger_status(logger_path);
ready_symbol = "ExperimentLogger_Obj1 (Module1).Outputs.loggerReady";
error_symbol = "ExperimentLogger_Obj1 (Module1).Outputs.LogStatus.errorCode";
records_symbol = "ExperimentLogger_Obj1 (Module1).Outputs.LogStatus.recordsWritten";
status.ready = logical(read_logger_scalar_or_default(module_transport, ready_symbol, net_types.bool, false));
status.error_code = uint32(read_logger_scalar_or_default(module_transport, error_symbol, net_types.u32, uint32(0)));
status.records_written = uint32(read_logger_scalar_or_default(module_transport, records_symbol, net_types.u32, uint32(0)));
end

function value = read_logger_scalar_or_default(module_transport, symbol, net_type, default_value)
try
  value = module_transport.read_scalar(symbol, net_type);
catch
  value = default_value;
end
end

function [released, detail] = probe_logger_file_release(log_path)
released = false;
detail = "file-missing";
if ~isfile(log_path)
  return;
end
[fid, msg] = fopen(log_path, "a");
if fid < 0
  detail = string(msg);
  return;
end
fclose(fid);
released = true;
detail = "append-open-succeeded";
end
