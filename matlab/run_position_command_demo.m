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

%% Environment defaults from SystemConfig
sys = experiment.SystemConfig;
cfg = experiment.ExperimentConfig.defaults();
logger_file_glob = "*.bin";
logger_dir = string(fileparts(char(sys.LOGGER_DEFAULT_FILE_PATH)));

%% Demo runtime config via ExperimentConfig
target_position_rad = 0.25;
step_duration_s     = 2.0;
hold_margin_s       = 0.50;
pre_step_s          = 2.0;
N_REPEAT            = 3;
Kp = 1;

%% Derived waveforms for this demo
step_sample_n = round(step_duration_s * cfg.task_rate_hz);
pre_step_n = max(1, round(pre_step_s * cfg.task_rate_hz));
if step_sample_n <= 0
  error("experiment:demo:invalid", "step_duration_s must produce at least one sample.");
end
sample_n = pre_step_n + step_sample_n;
per_trial_s = sample_n / cfg.task_rate_hz;
cfg.ref_profile = [zeros(pre_step_n, 1); target_position_rad * ones(step_sample_n, 1)];
cfg.ff_profile = zeros(sample_n, 1);
cfg.dist_profile = zeros(sample_n, 1);
cfg.repeat_count = N_REPEAT;
cfg.wait_for_done = true;
cfg.done_timeout_s = N_REPEAT * per_trial_s + hold_margin_s + 5.0;
cfg.logger_release_timeout_s = 5.0;
cfg.hold_seconds = per_trial_s + hold_margin_s;
cfg.plant = experiment.PlantConfig.from_struct(struct( ...
  "m", 0.02, ...
  "d", 0.2, ...
  "rated_current", 1.2, ...
  "max_permille", 0.0, ...
  "tau_limit", 2.4, ...
  "vel_limit", 2*pi*60));
cfg.controller = experiment.ControllerConfig.p_only(Kp);

fprintf("=== Position Command Demo (P control, Kp=%g, repeats=%d) ===\n", Kp, N_REPEAT);
fprintf("Target=%.4f rad, stepDuration=%.3f s, preStep=%.3f s, perTrial=%.3f s, N=%d\n", ...
  target_position_rad, step_sample_n / cfg.task_rate_hz, pre_step_n / cfg.task_rate_hz, per_trial_s, sample_n);

%% ADS 接続
seq_transport  = twincat_ads.AdsTransport();
ctrl_transport = twincat_ads.AdsTransport();
mod_transport  = twincat_ads.AdsTransport();
cleanup = onCleanup(@() disconnect_all(seq_transport, ctrl_transport, mod_transport));

seq_transport.connect(cfg.ams_net_id, cfg.seq_port);
ctrl_transport.connect(cfg.ams_net_id, cfg.control_port);
mod_transport.connect(cfg.ams_net_id, cfg.module_port);
fprintf("Connected: SEQ=%d, CTRL=%d, MODULE=%d\n", cfg.seq_port, cfg.control_port, cfg.module_port);
fprintf("VM params: m=%.2f d=%.2f rated_current=%.2f\n", ...
  cfg.plant.m, cfg.plant.d, cfg.plant.rated_current);
fprintf("Controller: Kp=%.1f (pid_b0), enable_pid=%d\n", Kp, logical(cfg.controller.pid.enable));

%% 実験実行
conn = struct("seq", seq_transport, "ctrl", ctrl_transport, "module", mod_transport);
out = experiment.ExperimentRunner.run(conn, cfg);
logger_bin = [];
latest_bin = experiment.read_latest_logger_bin(logger_dir, logger_file_glob);
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
    t_log = (0:n_log-1)' / cfg.task_rate_hz;
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
    Kp, N_REPEAT, cfg.plant.m, cfg.plant.d, cfg.plant.rated_current));

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
