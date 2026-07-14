%% Position command demo with repeated trials
%
%  filtered PID を ControllerCore にロードし、同一ステップ位置指令を
%  N_REPEAT 回だけ連続再生する。

tool_file = mfilename("fullpath");
matlab_root = fileparts(fileparts(tool_file));
addpath(matlab_root, fullfile(matlab_root, "experiment"));
clear tool_file matlab_root;

%% Environment defaults from ExperimentConfig
cfg = experiment.ExperimentConfig.defaults();

%% Demo runtime config via ExperimentConfig
target_position_rad = 0.75;
step_duration_s     = 2.0;
hold_margin_s       = 0.50;
pre_step_s          = 2.0;
N_REPEAT            = 1;
controller_bandwidth_rad_s = 20;
Jn = 7.1e-5;
Dn = 5.325e-4;

%% Derived waveforms for this demo
sample_time_s = 1 / cfg.env.task_rate_hz;
cfg.ref_profile = experiment.exp02.reference_profile( ...
  "", "", target_position_rad, pre_step_s, step_duration_s, sample_time_s);
sample_n = numel(cfg.ref_profile);
step_sample_n = round(step_duration_s * cfg.env.task_rate_hz);
pre_step_n = sample_n - step_sample_n;
per_trial_s = sample_n / cfg.env.task_rate_hz;
cfg.ff_profile = zeros(sample_n, 1);
cfg.dist_profile = zeros(sample_n, 1);
cfg.repeat_count = N_REPEAT;
cfg.wait_for_done = true;
cfg.done_timeout_s = N_REPEAT * per_trial_s + hold_margin_s + 5.0;
cfg.logger_release_timeout_s = 5.0;
cfg.hold_seconds = per_trial_s + hold_margin_s;
cfg.host_heartbeat_enable = false;
cfg.external_host_heartbeat_enable = true;
Kpid = experiment.exp02.designpid( ...
  Dn / Jn, 0, 1 / Jn, controller_bandwidth_rad_s);
Kd = c2d(Kpid, sample_time_s, "tustin");
cfg.controller = experiment.controller.from_discrete_tf(Kd);

fprintf("=== Position Command Demo (filtered PID, bandwidth=%g rad/s, repeats=%d) ===\n", ...
  controller_bandwidth_rad_s, N_REPEAT);
fprintf("Target=%.4f rad, stepDuration=%.3f s, preStep=%.3f s, perTrial=%.3f s, N=%d\n", ...
  target_position_rad, step_sample_n / cfg.env.task_rate_hz, pre_step_n / cfg.env.task_rate_hz, per_trial_s, sample_n);

fprintf("Controller: filtered PID (%d SOS section)\n", ...
  size(cfg.controller.sos, 1));

%% 実験実行
collect_out = experiment.exp0n.run_and_collect(cfg);
out = collect_out.run;
logger_bin = collect_out.logger_bin;
if isempty(logger_bin) || double(logger_bin.record_count) <= 0
  error("experiment:demo:loggerUnavailable", ...
    "ExperimentLogger bin is required but unavailable at %s.", string(out.logger.file_path));
end
[signals, signal_metrics] = experiment.exp02.signals_from_logger_bin(logger_bin);
experiment.exp0n.assert_run_contract(out);

%% 結果出力
fprintf("\n--- Result ---\n");
fprintf("done=%d  timed_out=%d\n", ...
  logical(out.host.done), logical(out.host.timed_out));
fprintf("loggerReady(before/after)=%d/%d  loggerError(before/after)=0x%08X/0x%08X\n", ...
  logical(out.logger.ready_before), logical(out.logger.ready_after), ...
  uint32(out.logger.error_before), uint32(out.logger.error_after));
fprintf("loggerFileReleased=%s (%s)\n", passfail(out.logger.file_released), string(out.logger.file_probe_detail));
fprintf("logSource=runner-confirmed (%s)\n", string(logger_bin.file_path));

print_sampling_metrics(out.metrics.sampling, out.metrics.sample_count);

if ~sampling_counts_match(out.metrics.sampling)
  if logical(out.host.done) && ~logical(out.host.timed_out)
    warning("experiment:demo:countMismatchNonFatal", ...
      "Log count mismatch (input=%d, ref=%d, pos=%d). Repeated playback may extend counts. See docs/operations/ExperimentProcedure.md.", ...
      double(out.metrics.sampling.command_count), ...
      double(out.metrics.sampling.ref_log_count), ...
      double(out.metrics.sampling.position_log_count));
  else
    error("experiment:demo:countMismatch", ...
      "Log count mismatch. Increase hold_margin_s or verify PLC sequence.");
  end
end

if logical(out.host.timed_out)
  fprintf("Timeout diag: modeStateSymbol=%s loggerError=0x%08X loggerFileReleased=%d\n", ...
    string(out.host.control_mode_state_symbol), uint32(out.logger.error_after), logical(out.logger.file_released));
end

%% プロット
experiment.plot.feedback_result(signals, signal_metrics);

%% --- helper functions ---

function print_sampling_metrics(sampling, sample_count)
fprintf("Counts: input=%d, seq=%d, ref=%d, ff=%d, dist=%d, u=%d, tau=%d, pos=%d\n", ...
  double(sampling.command_count), double(sample_count), double(sampling.ref_log_count), ...
  double(sampling.ff_log_count), double(sampling.dist_log_count), ...
  double(sampling.controlInput_log_count), double(sampling.target_torque_log_count), ...
  double(sampling.position_log_count));
fprintf("Check: components=%s, input-ref=%s, input-pos=%s, overall=%s\n", ...
  passfail(sampling.all_sample_counts_match), ...
  passfail(double(sampling.command_count) == double(sampling.ref_log_count)), ...
  passfail(double(sampling.command_count) == double(sampling.position_log_count)), ...
  passfail(sampling_counts_match(sampling)));
end

function tf = sampling_counts_match(sampling)
tf = logical(sampling.all_sample_counts_match) && ...
  (double(sampling.command_count) == double(sampling.ref_log_count)) && ...
  (double(sampling.command_count) == double(sampling.position_log_count));
end

function s = passfail(flag)
if logical(flag), s = "OK"; else, s = "NG"; end
end
