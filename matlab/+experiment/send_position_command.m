function out = send_position_command(varargin)
cfg = parse_config(varargin{:});
plc_symbols = experiment.VirtualMotorSymbols.from_defaults();
plc_transport = [];
ctrl_transport = [];
mode_flags_transport = [];
owns_transport = false;
owns_ctrl_transport = false;
owns_mode_flags_transport = false;
mode_flags_symbol = "";

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
  plc_transport, ctrl_transport, mode_flags_transport, owns_transport, owns_ctrl_transport, ...
  owns_mode_flags_transport, plc_symbols, mode_flags_symbol)); %#ok<NASGU>
assert_split_port_modeflags_config(cfg, plc_transport, ctrl_transport, ctrl);
done = false;
timed_out = false;
servo_ready = false;
servo_ready_check_supported = false;
servo_ready_diag = struct();
control_runtime_diag = struct();
t_run = tic;

write_mode_flags(mode_flags_transport, ctrl, uint32(0));
plc_transport.write_scalar(plc_symbols.idx, uint32(0), t.u32);
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
    "Timed out waiting reset idle state (wrIdx==0, idx==0, experimentActive==FALSE). Observed wrIdx=%g idx=%g experimentActive=%d modeFlagsSymbol=%s", ...
    idle_diag.wr_idx, idle_diag.idx, logical(idle_diag.experiment_active), char(string(ctrl.modeFlagsSymbol)));
end

table_n = numel(cfg.ref_profile);
plc_transport.write_array(plc_symbols.refTable, cfg.ref_profile, t.double);
plc_transport.write_array(plc_symbols.ffTable, cfg.ff_profile, t.double);
plc_transport.write_array(plc_symbols.distTable, cfg.dist_profile, t.double);
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

position_last = double(plc_transport.read_scalar(plc_symbols.positionActLog, t.double));
control_input_last = double(plc_transport.read_scalar(plc_symbols.controlInput, t.double));

if cfg.read_logs
  log_data = read_upper_logs(plc_transport, plc_symbols, cfg.log_n);
else
  log_data = empty_log_data();
end

if log_data.overflow
  warning("experiment:position_command:logOverflow", ...
    "PLC log overflow detected (GVL_SEQ_LOG.overflow=true).");
end

out = struct();
out.cmd = struct( ...
  "ref_profile", cfg.ref_profile, ...
  "ff_profile", cfg.ff_profile, ...
  "dist_profile", cfg.dist_profile, ...
  "table_len", table_n, ...
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
  "logTargetTorque", log_data.logTargetTorque, ...
  "logPositionAct", log_data.logPositionAct, ...
  "logSeq", log_data.logSeq, ...
  "logT", log_data.logT, ...
  "logIdx", log_data.logIdx, ...
  "log_wrIdx", log_data.wrIdx, ...
  "log_overflow", logical(log_data.overflow));
out.eval = build_count_eval(out.cmd, out.raw);
end

function cleanup_transports(plc_transport, ctrl_transport, mode_flags_transport, ...
    owns_transport, owns_ctrl_transport, owns_mode_flags_transport, plc_symbols, mode_flags_symbol)
if isempty(plc_transport) && isempty(ctrl_transport)
  return;
end

same_transport = ~isempty(plc_transport) && ~isempty(ctrl_transport) && (plc_transport == ctrl_transport);
same_mode_ctrl = ~isempty(mode_flags_transport) && ~isempty(ctrl_transport) && (mode_flags_transport == ctrl_transport);
same_mode_plc = ~isempty(mode_flags_transport) && ~isempty(plc_transport) && (mode_flags_transport == plc_transport);
if owns_mode_flags_transport && ~same_mode_ctrl && ~same_mode_plc
  try
    mode_flags_transport.disconnect();
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

function cfg = parse_config(varargin)
p = inputParser;
p.addParameter("ams_net_id", "", @(x) ischar(x) || isstring(x));
p.addParameter("ams_port", 851, @(x) isnumeric(x) && isscalar(x));
p.addParameter("task_rate_hz", 1000, @(x) isnumeric(x) && isscalar(x));
p.addParameter("ref_profile", [], @(x) isnumeric(x));
p.addParameter("ff_profile", [], @(x) isnumeric(x));
p.addParameter("dist_profile", [], @(x) isnumeric(x));
p.addParameter("wait_for_done", true, @(x) islogical(x) || isnumeric(x));
p.addParameter("done_timeout_s", 30.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter("reset_timeout_s", 5.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter("host_heartbeat_enable", true, @(x) islogical(x) || isnumeric(x));
p.addParameter("host_heartbeat_period_s", 0.1, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter("hold_seconds", NaN, @(x) isnumeric(x) && isscalar(x) && (isnan(x) || x >= 0));
p.addParameter("table_max_n", 100000, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter("log_n", 200000, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter("ads_assembly", "", @(x) ischar(x) || isstring(x));
p.addParameter("read_logs", true, @(x) islogical(x) || isnumeric(x));
p.addParameter("validate_symbols", true, @(x) islogical(x) || isnumeric(x));
p.addParameter("plc_transport", [], @(x) isempty(x) || isa(x, "twincat_ads.IAdsTransport"));
p.addParameter("control_ams_port", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("control_transport", [], @(x) isempty(x) || isa(x, "twincat_ads.IAdsTransport"));
p.addParameter("mode_flags_symbol", "", @(x) ischar(x) || isstring(x));
p.addParameter("mode_flags_ams_port", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("mode_flags_transport", [], @(x) isempty(x) || isa(x, "twincat_ads.IAdsTransport"));
p.parse(varargin{:});

cfg = p.Results;
cfg.ams_net_id = char(string(cfg.ams_net_id));
cfg.ams_port = double(cfg.ams_port);
cfg.task_rate_hz = double(cfg.task_rate_hz);
cfg.ref_profile = double(cfg.ref_profile(:));
cfg.ff_profile = double(cfg.ff_profile(:));
cfg.dist_profile = double(cfg.dist_profile(:));
cfg.wait_for_done = logical(cfg.wait_for_done);
cfg.done_timeout_s = double(cfg.done_timeout_s);
cfg.reset_timeout_s = double(cfg.reset_timeout_s);
cfg.host_heartbeat_enable = logical(cfg.host_heartbeat_enable);
cfg.host_heartbeat_period_s = double(cfg.host_heartbeat_period_s);
cfg.table_max_n = double(cfg.table_max_n);
cfg.log_n = double(cfg.log_n);
cfg.ads_assembly = char(string(cfg.ads_assembly));
cfg.read_logs = logical(cfg.read_logs);
cfg.validate_symbols = logical(cfg.validate_symbols);
cfg.mode_flags_symbol = char(string(cfg.mode_flags_symbol));
if isempty(cfg.control_ams_port)
  cfg.control_ams_port = [];
else
  cfg.control_ams_port = double(cfg.control_ams_port);
end
if isempty(cfg.mode_flags_ams_port)
  cfg.mode_flags_ams_port = [];
else
  cfg.mode_flags_ams_port = double(cfg.mode_flags_ams_port);
end

if isempty(strtrim(cfg.ams_net_id))
  invalid_config("ams_net_id is required.");
end
if isempty(cfg.ref_profile)
  invalid_config("ref_profile is required and must not be empty.");
end
if ~(isfinite(cfg.task_rate_hz) && cfg.task_rate_hz > 0)
  invalid_config("task_rate_hz must be > 0.");
end
if numel(cfg.ref_profile) > cfg.table_max_n
  invalid_config("ref_profile length (%d) exceeds table_max_n (%d).", ...
    numel(cfg.ref_profile), cfg.table_max_n);
end
if isempty(cfg.ff_profile)
  cfg.ff_profile = zeros(size(cfg.ref_profile));
end
if isempty(cfg.dist_profile)
  cfg.dist_profile = zeros(size(cfg.ref_profile));
end
if numel(cfg.ff_profile) ~= numel(cfg.ref_profile)
  invalid_config("ff_profile length must match ref_profile length.");
end
if numel(cfg.dist_profile) ~= numel(cfg.ref_profile)
  invalid_config("dist_profile length must match ref_profile length.");
end

if isnan(cfg.hold_seconds)
  cfg.hold_seconds = numel(cfg.ref_profile) / cfg.task_rate_hz;
else
  cfg.hold_seconds = double(cfg.hold_seconds);
end

if isempty(cfg.control_ams_port)
  if cfg.ams_port == 853
    cfg.control_ams_port = 852;
  else
    cfg.control_ams_port = cfg.ams_port;
  end
end

if (~isempty(cfg.mode_flags_transport) || ~isempty(cfg.mode_flags_ams_port)) && ...
    isempty(strtrim(cfg.mode_flags_symbol))
  invalid_config("mode_flags_symbol is required when mode_flags_transport or mode_flags_ams_port is specified.");
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
net_type = string(net_type);
if net_type == "System.UInt16"
  v = uint16(double(value));
else
  v = uint32(double(value));
end
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
if isfield(t, "u16")
  u16 = t.u16;
else
  u16 = t.u32;
end
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

function log_data = read_upper_logs(plc_transport, symbols, log_n)
t = symbols.types;
log_data = empty_log_data();
try
  wr_idx = plc_transport.read_scalar(symbols.log.wrIdx, t.u32);
  overflow = plc_transport.read_scalar(symbols.log.overflow, t.bool);
  valid_n = uint32(min(double(wr_idx), double(log_n)));
  if valid_n > 0
    log_data.logSeq = double(plc_transport.read_array(symbols.log.logSeq, t.u32, valid_n));
    log_data.logRefValue = double(plc_transport.read_array(symbols.log.logRefValue, t.double, valid_n));
    log_data.logFfValue = double(plc_transport.read_array(symbols.log.logFfValue, t.double, valid_n));
    log_data.logDistValue = double(plc_transport.read_array(symbols.log.logDistValue, t.double, valid_n));
    log_data.logControlInput = double(plc_transport.read_array(symbols.log.logControlInput, t.double, valid_n));
    log_data.logTargetTorque = double(plc_transport.read_array(symbols.log.logTargetTorque, t.double, valid_n));
    log_data.logPositionAct = double(plc_transport.read_array(symbols.log.logPositionAct, t.double, valid_n));
    try
      log_data.logT = double(plc_transport.read_array(symbols.log.logT, t.u64, valid_n));
    catch
      log_data.logT = zeros(double(valid_n), 1);
    end
    try
      log_data.logIdx = double(plc_transport.read_array(symbols.log.logIdx, t.u32, valid_n));
    catch
      log_data.logIdx = zeros(0, 1);
    end
  end
  log_data.wrIdx = double(wr_idx);
  log_data.overflow = logical(overflow);
catch e
  log_data = empty_log_data();
  warning("experiment:position_command:logUnavailable", ...
    "Log read failed; keeping empty logs (%s: %s).", ...
    string(e.identifier), string(e.message));
end
end

function out = empty_log_data()
out = struct( ...
  "logSeq", zeros(0, 1), ...
  "logRefValue", zeros(0, 1), ...
  "logFfValue", zeros(0, 1), ...
  "logDistValue", zeros(0, 1), ...
  "logControlInput", zeros(0, 1), ...
  "logTargetTorque", zeros(0, 1), ...
  "logPositionAct", zeros(0, 1), ...
  "logT", zeros(0, 1), ...
  "logIdx", zeros(0, 1), ...
  "wrIdx", 0, ...
  "overflow", false);
end

function ev = build_count_eval(cmd, raw)
n_cmd = numel(cmd.ref_profile);
n_seq = numel(raw.logSeq);
n_ref = numel(raw.logRefValue);
n_ff = numel(raw.logFfValue);
n_dist = numel(raw.logDistValue);
n_u = numel(raw.logControlInput);
n_tau = numel(raw.logTargetTorque);
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
  "log_target_torque_count", n_tau, ...
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
