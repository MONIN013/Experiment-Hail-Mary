%% ExperimentSequencer + ControllerCore + VirtualMotorCore SIL validation script
base_dir = fileparts(mfilename("fullpath"));
restoredefaultpath;
addpath(genpath(base_dir));

%% Connection and model parameters
ams_net_id = "192.168.10.3.1.1";
module_ams_port = 351;
vm_param_symbol_prefix = "VirtualMotorCore_Obj1 (Module1).VirtualMotorParameter.";
controller_param_symbol_prefix = "ControllerCore_Obj1 (Module1).";
task_rate_hz = 1000;

m = 1;
d = 6;
kt = 0.1;
tau_limit = 5.0;
vel_limit = 100.0;

%% Input waveform parameters (ref/ff/dist tables)
duration_s = 5.0;
freq_hz = 2.0;
amp_ref = 0.4;
offset_ref = 0.0;
phase_rad = 0.0;

sample_n = round(duration_s * task_rate_hz);
if sample_n <= 0
  error("duration_s must produce at least one sample.");
end
t_cmd = (0:sample_n-1)' / task_rate_hz;
ref_profile = offset_ref + amp_ref * sin(2 * pi * freq_hz * t_cmd + phase_rad);
ff_profile = zeros(sample_n, 1);
dist_profile = zeros(sample_n, 1);

fprintf("Ref table: amp=%.4f, freq=%.4f Hz, duration=%.3f s, N=%d\n", amp_ref, freq_hz, duration_s, sample_n);
stream_opts = derive_streaming_options(task_rate_hz, sample_n);

%% Run experiment
out = experiment.run_virtualmotor( ...
  "ams_net_id", ams_net_id, ...
  "module_ams_port", module_ams_port, ...
  "vm_param_symbol_prefix", vm_param_symbol_prefix, ...
  "controller_param_symbol_prefix", controller_param_symbol_prefix, ...
  "ref_profile", ref_profile, ...
  "ff_profile", ff_profile, ...
  "dist_profile", dist_profile, ...
  "hold_seconds", duration_s, ...
  "wait_for_done", true, ...
  "task_rate_hz", task_rate_hz, ...
  "log_stream_enable", true, ...
  "log_stream_require_success", true, ...
  "log_require_complete", true, ...
  "log_require_waveform_exact", true, ...
  "log_warn_on_overflow", true, ...
  "log_poll_period_s", stream_opts.log_poll_period_s, ...
  "log_chunk_n", stream_opts.log_chunk_n, ...
  "log_host_max_n", stream_opts.log_host_max_n, ...
  "m", m, ...
  "d", d, ...
  "kt", kt, ...
  "tau_limit", tau_limit, ...
  "vel_limit", vel_limit);

validate_complete_capture_or_throw(out, sample_n);

%% Plotting
raw = out.raw;
metrics = out.metrics;
cfg = out.config;
t = (0:numel(raw.log_seq)-1)' / cfg.task_rate_hz;

figure("Name", "Experiment Sequencer + ControllerCore Validation", "Color", "w");
tiledlayout(3, 1, "Padding", "compact", "TileSpacing", "compact");

nexttile;
plot(t, raw.log_ref_value, "b-", "LineWidth", 1.1); hold on;
plot(t_cmd, ref_profile, "k--", "LineWidth", 1.0); hold off;
legend("PLC ref_value", "Command ref_profile", "Location", "best");
grid on; xlabel("Time [s]"); ylabel("ref"); title("Reference Replay");

nexttile;
plot(t, raw.log_control_input, "m-", "LineWidth", 1.1); hold on;
plot(t, raw.log_target_torque, "r--", "LineWidth", 1.1); hold off;
legend("control_input", "target_torque", "Location", "best");
grid on; xlabel("Time [s]"); ylabel("Torque [Nm]"); title("Controller + Dist Adder");

nexttile;
plot(t, raw.log_position_act, "g-", "LineWidth", 1.1);
grid on; xlabel("Time [s]"); ylabel("Position [rad]"); title("Position (log)");

sgtitle(sprintf("SIL Validation | ref max|err|=%.3g | torque sum max|err|=%.3g", ...
  metrics.input_waveform.max_abs_err, metrics.torque_sum.max_abs_err));
drawnow;
print_summary(out);

function print_summary(out)
raw = out.raw;
metrics = out.metrics;
cmd = out.cmd;
fprintf("\n=== ExperimentSequencer + ControllerCore SIL Summary ===\n");
fprintf("Samples\n");
fprintf("  table=%d, seq=%d, ref=%d, ff=%d, dist=%d, u=%d, tau=%d, pos=%d\n", ...
  numel(cmd.ref_profile), numel(raw.log_seq), numel(raw.log_ref_value), numel(raw.log_ff_value), ...
  numel(raw.log_dist_value), numel(raw.log_control_input), numel(raw.log_target_torque), numel(raw.log_position_act));

checks = [ ...
  logical(metrics.input_waveform.exact_sample_count_match), ...
  logical(metrics.input_waveform.exact_value_match), ...
  logical(metrics.ff_waveform.exact_value_match), ...
  logical(metrics.dist_waveform.exact_value_match), ...
  logical(metrics.torque_sum.exact_match), ...
  logical(metrics.acceptance.seq_no_gap), ...
  logical(metrics.acceptance.total_sample_count_exact_match), ...
  ~logical(raw.log_overflow)];
pass_n = sum(checks);

fprintf("Checks\n");
fprintf("  ref_exact=%s, ff_exact=%s, dist_exact=%s, torque_sum=%s, seq_gap=%s, overflow=%s\n", ...
  passfail(metrics.input_waveform.exact_value_match), ...
  passfail(metrics.ff_waveform.exact_value_match), ...
  passfail(metrics.dist_waveform.exact_value_match), ...
  passfail(metrics.torque_sum.exact_match), ...
  passfail(metrics.acceptance.seq_no_gap), ...
  passfail(~raw.log_overflow));
fprintf("  Result %s (%d/%d)\n", passfail(all(checks)), pass_n, numel(checks));
end

function opts = derive_streaming_options(task_rate_hz, sample_n)
log_poll_period_s = min(0.01, max(0.001, 100 / task_rate_hz));
log_chunk_n = max(4096, 4 * ceil(task_rate_hz * log_poll_period_s));
log_host_max_n = max(2 * sample_n, sample_n + 1000);
opts = struct("log_poll_period_s", double(log_poll_period_s), "log_chunk_n", double(log_chunk_n), "log_host_max_n", double(log_host_max_n));
end

function validate_complete_capture_or_throw(out, expected_n)
raw = out.raw;
metrics = out.metrics;
must_be_true(logical(metrics.acceptance.log_available), "experiment:script:logUnavailable", "No log data captured.");
must_be_true(~logical(raw.log_overflow), "experiment:script:logOverflow", "Log overflow detected.");
must_be_true(logical(metrics.sampling.all_sample_counts_match), "experiment:script:sampleCountMismatch", "Log component sample counts mismatch.");
must_be_true(logical(metrics.acceptance.total_sample_count_exact_match), "experiment:script:totalSampleCountMismatch", "Total sample count exact match failed.");
must_be_true(numel(raw.log_seq) == expected_n, "experiment:script:expectedCountMismatch", "Captured sample count does not equal expected_n.");
must_be_true(logical(metrics.input_waveform.exact_value_match), "experiment:script:refMismatch", "ref_profile and log_ref_value mismatch.");
must_be_true(logical(metrics.ff_waveform.exact_value_match), "experiment:script:ffMismatch", "ff_profile and log_ff_value mismatch.");
must_be_true(logical(metrics.dist_waveform.exact_value_match), "experiment:script:distMismatch", "dist_profile and log_dist_value mismatch.");
must_be_true(logical(metrics.torque_sum.exact_match), "experiment:script:torqueSumMismatch", "log_target_torque ~= log_control_input + log_dist_value.");
end

function must_be_true(cond, id, msg)
if ~cond
  error(id, "%s", msg);
end
end

function s = passfail(flag)
if logical(flag)
  s = "OK";
else
  s = "NG";
end
end
