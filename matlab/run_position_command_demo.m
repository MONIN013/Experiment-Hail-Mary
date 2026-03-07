%% Position command demo with repeated trials
%
%  P 制御 (Kp = 180) を ControllerCore にロードし、同一ステップ位置指令を
%  N_REPEAT 回だけ連続再生する。
%
%  P 制御設計根拠 (m=1, d=6, rated_current=0.1):
%    プラント: G(s) = rated_current / (m*s^2 + d*s) = 0.1 / (s^2 + 6s)
%    閉ループ: T(s) = 0.1*Kp / (s^2 + 6s + 0.1*Kp)
%    omega_n = sqrt(0.1*Kp) = sqrt(18) = 4.24 rad/s
%    zeta    = d / (2*sqrt(m*rated_current*Kp)) = 6 / (2*sqrt(0.1*180)) = 0.707
%
%  参照: docs/MatlabSpec.md §7.1

base_dir = fileparts(mfilename("fullpath"));
restoredefaultpath;
addpath(genpath(base_dir));

%% Parameters from SystemConfig
sys = experiment.SystemConfig;
ams_net_id     = sys.AMS_NET_ID;
seq_port       = sys.SEQ_PORT;
control_port   = sys.CONTROL_PORT;
module_port    = sys.MODULE_PORT;
task_rate_hz   = sys.TASK_RATE_HZ;
logger_share_dir = "\\RAINYDAY\ExperimentData";
logger_file_glob = "*.bin";

%% Experiment parameters
target_position_rad = 0.25;
step_duration_s     = 1.0;
hold_margin_s       = 0.50;
pre_step_s          = 1.0;
N_REPEAT            = 1;

%% VM 物理パラメータ
vm_params = struct( ...
  "m",              0.02, ...
  "d",              0.2, ...
  "rated_current",  1.2, ...
  "max_permille",   0.0, ...
  "tau_limit",      2.4, ...
  "vel_limit",      2*pi*60);

%% P 制御パラメータ (Kp = 180, biquad 形式: y[n] = b0*x[n])
Kp = 1;
ctrl_params = struct( ...
  "pid_b0",  Kp,   "pid_b1",  0, "pid_b2",  0, "pid_a1",  0, "pid_a2",  0, ...
  "lead_b0", 1,    "lead_b1", 0, "lead_b2", 0, "lead_a1", 0, "lead_a2", 0, ...
  "notch_b0", 1,   "notch_b1", 0, "notch_b2", 0, "notch_a1", 0, "notch_a2", 0, ...
  "reso_b0", 1,    "reso_b1", 0, "reso_b2", 0, "reso_a1", 0, "reso_a2", 0, ...
  "enable_pid", true, "enable_lead", false, "enable_notch", false, "enable_reso", false);

%% 指令波形: ステップ位置指令
step_sample_n = round(step_duration_s * task_rate_hz);
pre_step_n = max(1, round(pre_step_s * task_rate_hz));
if step_sample_n <= 0
  error("experiment:demo:invalid", "step_duration_s must produce at least one sample.");
end
sample_n = pre_step_n + step_sample_n;
per_trial_s = sample_n / task_rate_hz;
ref_profile  = [zeros(pre_step_n, 1); target_position_rad * ones(step_sample_n, 1)];
ff_profile   = zeros(sample_n, 1);
dist_profile = zeros(sample_n, 1);
done_timeout_s = N_REPEAT * per_trial_s + hold_margin_s + 5.0;

fprintf("=== Position Command Demo (P control, Kp=%g, repeats=%d) ===\n", Kp, N_REPEAT);
fprintf("Target=%.4f rad, stepDuration=%.3f s, preStep=%.3f s, perTrial=%.3f s, N=%d\n", ...
  target_position_rad, step_sample_n / task_rate_hz, pre_step_n / task_rate_hz, per_trial_s, sample_n);

%% ADS 接続
seq_transport  = twincat_ads.AdsTransport();
ctrl_transport = twincat_ads.AdsTransport();
mod_transport  = twincat_ads.AdsTransport();
cleanup = onCleanup(@() disconnect_all(seq_transport, ctrl_transport, mod_transport));

seq_transport.connect(ams_net_id, seq_port);
ctrl_transport.connect(ams_net_id, control_port);
mod_transport.connect(ams_net_id, module_port);
fprintf("Connected: SEQ=%d, CTRL=%d, MODULE=%d\n", seq_port, control_port, module_port);

%% パラメータ書込み
experiment.write_vm_params(mod_transport, char(sys.VM_PREFIX), vm_params, experiment.SystemConfig.task_dt_ns());
experiment.write_controller_params(mod_transport, char(sys.CTRL_PREFIX), ctrl_params);
fprintf("VM params: m=%.2f d=%.2f rated_current=%.2f\n", vm_params.m, vm_params.d, vm_params.rated_current);
fprintf("Controller: Kp=%.1f (pid_b0), enable_pid=true\n", Kp);

%% テーブル書込み + 実験実行
out = experiment.send_position_command( ...
  "ams_net_id", char(ams_net_id), ...
  "ams_port", seq_port, ...
  "control_ams_port", control_port, ...
  "mode_flags_symbol", char(sys.MODE_FLAGS_SYMBOL), ...
  "ref_profile", ref_profile, ...
  "ff_profile", ff_profile, ...
  "dist_profile", dist_profile, ...
  "task_rate_hz", task_rate_hz, ...
  "repeat_count", N_REPEAT, ...
  "wait_for_done", true, ...
  "done_timeout_s", done_timeout_s, ...
  "logger_release_timeout_s", 5.0, ...
  "hold_seconds", per_trial_s + hold_margin_s, ...
  "plc_transport", seq_transport, ...
  "control_transport", ctrl_transport, ...
  "module_transport", mod_transport, ...
  "mode_flags_transport", ctrl_transport, ...
  "validate_symbols", true);
logger_bin = [];
latest_bin = experiment.read_latest_logger_bin(logger_share_dir, logger_file_glob);
if latest_bin.ok
  logger_bin = latest_bin.logger_bin;
end
selected = experiment.resolve_demo_log_source(out, logger_bin);
if selected.source_name ~= "experiment_logger_bin"
  error("experiment:demo:loggerUnavailable", ...
    "ExperimentLogger bin is required but unavailable (%s; demoLookup=%s).", ...
    string(selected.diagnostics.reason), string(latest_bin.reason));
end

%% 結果出力
fprintf("\n--- Result ---\n");
fprintf("done=%d  timed_out=%d\n", ...
  logical(out.host.done), logical(out.host.timed_out));
fprintf("loggerReady(before/after)=%d/%d  loggerError(before/after)=0x%08X/0x%08X\n", ...
  logical(out.logger.ready_before), logical(out.logger.ready_after), ...
  uint32(out.logger.error_before), uint32(out.logger.error_after));
fprintf("loggerFileReleased=%s (%s)\n", passfail(out.logger.file_released), string(out.logger.file_probe_detail));
fprintf("logSource=%s (%s)\n", selected.source_name, string(selected.diagnostics.reason));

print_count_eval(out.eval);

if ~out.eval.input_and_all_log_counts_match
  if logical(out.host.done) && ~logical(out.host.timed_out)
    warning("experiment:demo:countMismatchNonFatal", ...
      "Log count mismatch (input=%d, ref=%d, pos=%d). Repeated playback may extend counts. See docs/ExperimentProcedure.md.", ...
      out.eval.input_count, out.eval.log_ref_count, out.eval.log_position_count);
  else
    error("experiment:demo:countMismatch", ...
      "Log count mismatch. Increase hold_margin_s or verify PLC sequence.");
  end
end

if logical(out.host.timed_out)
  fprintf("Timeout diag: experimentStateSymbol=%s loggerError=0x%08X loggerFileReleased=%d\n", ...
    string(out.host.control_experiment_state_symbol), uint32(out.logger.error_after), logical(out.logger.file_released));
end

%% プロット
n_log = numel(selected.signals.position_act);
if n_log > 0
  t_log = selected.signals.time_s;
  if isempty(t_log)
    t_log = (0:n_log-1)' / task_rate_hz;
  end

  figure("Name", "P Control Position Demo", "Color", "w");
  tiledlayout(2, 1, "Padding", "compact", "TileSpacing", "compact");

  nexttile;
  plot(t_log, selected.signals.ref_value,     "-",  "Color", [0.6 0.6 0.6], "LineWidth", 0.8, "DisplayName", "ref"); hold on;
  plot(t_log, selected.signals.position_act,  "-",  "Color", [0.1 0.6 0.2], "LineWidth", 1.2, "DisplayName", "positionRel");
  hold off;
  grid on; xlabel("Time [s]"); ylabel("Position [rad]");
  legend("Location", "best");
  title(sprintf("Step Response (Kp=%g, repeats=%d, m=%.1f, d=%.1f, rated_current=%.2f)", ...
    Kp, N_REPEAT, vm_params.m, vm_params.d, vm_params.rated_current));

  nexttile;
  plot(t_log, selected.signals.control_input, "-",  "Color", [0.8 0.2 0.7], "LineWidth", 1.2, "DisplayName", "controlInput"); hold on;
  if ~isempty(selected.signals.target_current)
    plot(t_log, selected.signals.target_current, "--", "Color", [0.9 0.2 0.2], "LineWidth", 0.8, "DisplayName", "targetCurrent");
  end
  hold off;
  grid on; xlabel("Time [s]"); ylabel("Current [A]");
  legend("Location", "best");
  title("Controller Output");
end

%% --- helper functions ---

function disconnect_all(varargin)
for k = 1:numel(varargin)
  try
    varargin{k}.disconnect();
  catch
  end
end
end

function print_count_eval(ev)
fprintf("Counts: input=%d, seq=%d, ref=%d, ff=%d, dist=%d, u=%d, tau=%d, pos=%d\n", ...
  ev.input_count, ev.log_seq_count, ev.log_ref_count, ev.log_ff_count, ev.log_dist_count, ...
  ev.log_control_input_count, ev.log_target_current_count, ev.log_position_count);
fprintf("Check: components=%s, input-ref=%s, input-pos=%s, overall=%s\n", ...
  passfail(ev.log_component_counts_match), ...
  passfail(ev.input_count_matches_log_ref), ...
  passfail(ev.input_count_matches_log_position), ...
  passfail(ev.input_and_all_log_counts_match));
end

function s = passfail(flag)
if logical(flag), s = "OK"; else, s = "NG"; end
end

function s = fmt_diag_value(v)
if isempty(v) || (isnumeric(v) && any(isnan(v), "all"))
  s = "NaN";
elseif islogical(v)
  s = string(double(v));
elseif isnumeric(v)
  s = string(double(v));
else
  s = string(v);
end
end
