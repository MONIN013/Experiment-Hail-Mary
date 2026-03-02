%% Position command demo with P control
%
%  P 制御 (Kp = 180) を ControllerCore にロードし、ステップ位置指令を送信する。
%  SystemConfig の固定パラメータを使用。
%
%  P 制御設計根拠 (m=1, d=6, rated_current=0.1):
%    プラント: G(s) = rated_current / (m*s^2 + d*s) = 0.1 / (s^2 + 6s)
%    閉ループ: T(s) = 0.1*Kp / (s^2 + 6s + 0.1*Kp)
%    zeta = d / (2*sqrt(m*rated_current*Kp)) = 6 / (2*sqrt(0.1*180)) = 0.707
%    omega_n = sqrt(0.1*180) = 4.24 rad/s
%
%  参照: docs/MatlabSpec.md

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

%% Experiment parameters
target_position_rad = 0.25;
duration_s          = 3.0;     % 整定観察のため 3 秒
hold_margin_s       = 0.50;
pre_step_s          = 1.0;    % リセット直後の残留を避けるため先頭 20 ms はゼロ指令

%% VM 物理パラメータ
vm_params = struct( ...
  "m",              0.02, ...
  "d",              0.2, ...
  "rated_current",  1.2, ...
  "max_permille",   0.0, ...
  "tau_limit",      2.4, ...
  "vel_limit",      100.0);

%% P 制御パラメータ (Kp = 180, biquad 形式: y[n] = b0*x[n])
Kp = 10;
ctrl_params = struct( ...
  "pid_b0",  Kp,   "pid_b1",  0, "pid_b2",  0, "pid_a1",  0, "pid_a2",  0, ...
  "lead_b0", 1,    "lead_b1", 0, "lead_b2", 0, "lead_a1", 0, "lead_a2", 0, ...
  "notch_b0", 1,   "notch_b1", 0, "notch_b2", 0, "notch_a1", 0, "notch_a2", 0, ...
  "reso_b0", 1,    "reso_b1", 0, "reso_b2", 0, "reso_a1", 0, "reso_a2", 0, ...
  "enable_pid", true, "enable_lead", false, "enable_notch", false, "enable_reso", false);

%% 指令波形: ステップ位置指令
step_sample_n = round(duration_s * task_rate_hz);
pre_step_n = max(1, round(pre_step_s * task_rate_hz));
if step_sample_n <= 0
  error("experiment:demo:invalid", "duration_s must produce at least one sample.");
end
sample_n = pre_step_n + step_sample_n;
duration_s = step_sample_n / task_rate_hz;
ref_profile  = [zeros(pre_step_n, 1); target_position_rad * ones(step_sample_n, 1)];
ff_profile   = zeros(sample_n, 1);
dist_profile = zeros(sample_n, 1);

fprintf("=== Position Command Demo (P control, Kp=%g) ===\n", Kp);
fprintf("Target=%.4f rad, stepDuration=%.3f s, preStep=%.3f s, N=%d\n", ...
  target_position_rad, duration_s, pre_step_n / task_rate_hz, sample_n);

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
experiment.write_vm_params(mod_transport, vm_params);
experiment.write_controller_params(mod_transport, ctrl_params);
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
  "wait_for_done", true, ...
  "done_timeout_s", duration_s + hold_margin_s + 5.0, ...
  "hold_seconds", duration_s + hold_margin_s, ...
  "plc_transport", seq_transport, ...
  "control_transport", ctrl_transport, ...
  "mode_flags_transport", ctrl_transport, ...
  "validate_symbols", true);

%% 結果出力
fprintf("\n--- Result ---\n");
fprintf("done=%d  timed_out=%d  overflow=%d  position_last=%.6f rad\n", ...
  logical(out.host.done), logical(out.host.timed_out), ...
  logical(out.raw.log_overflow), out.raw.position_last);

print_count_eval(out.eval);

if ~out.eval.input_and_all_log_counts_match
  if logical(out.host.done) && ~logical(out.host.timed_out)
    warning("experiment:demo:countMismatchNonFatal", ...
      "Log count mismatch (input=%d, ref=%d, pos=%d). See docs/ExperimentProcedure.md.", ...
      out.eval.input_count, out.eval.log_ref_count, out.eval.log_position_count);
  else
    error("experiment:demo:countMismatch", ...
      "Log count mismatch. Increase hold_margin_s or verify PLC sequence.");
  end
end

%% プロット
if ~isempty(out.raw.logRefValue) && ~isempty(out.raw.logPositionAct)
  t = (0:numel(out.raw.logRefValue)-1)' / task_rate_hz;
  figure("Name", "P Control Position Demo", "Color", "w");
  tiledlayout(2, 1, "Padding", "compact", "TileSpacing", "compact");

  nexttile;
  plot(t, out.raw.logRefValue, "b-", "LineWidth", 1.1); hold on;
  plot(t, out.raw.logPositionAct, "g-", "LineWidth", 1.1); hold off;
  grid on; xlabel("Time [s]"); ylabel("Position [rad]");
  legend("ref", "positionRel", "Location", "best");
  title(sprintf("Step Response (Kp=%g, m=%.1f, d=%.1f, rated_current=%.2f)", ...
    Kp, vm_params.m, vm_params.d, vm_params.rated_current));

  nexttile;
  plot(t, out.raw.logControlInput, "m-", "LineWidth", 1.1); hold on;
  if ~isempty(out.raw.logTargetCurrent)
    plot(t, out.raw.logTargetCurrent, "r--", "LineWidth", 0.9);
    legend("controlInput", "targetCurrent", "Location", "best");
  else
    legend("controlInput", "Location", "best");
  end
  hold off;
  grid on; xlabel("Time [s]"); ylabel("Current [A]");
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
