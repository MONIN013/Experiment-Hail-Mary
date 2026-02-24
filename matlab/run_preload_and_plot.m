%% virtualMotor sine-profile validation script
base_dir = fileparts(mfilename("fullpath"));
restoredefaultpath;
addpath(genpath(base_dir));

%% Connection and model parameters
ams_net_id = "192.168.10.3.1.1";
vm_ams_port = 351;
vm_param_symbol_prefix = "VirtualMotorCore_Obj1 (Module1).VirtualMotorParameter.";
task_rate_hz = 1000;
m = 1;
d = 6;
kt = 0.1;
tau_limit = 5.0;
vel_limit = 100.0;

%% Input waveform parameters
duration_s = 5.0;
freq_hz = 2.0;
amp_a = 0.4;
offset_a = 0.0;
phase_rad = 0.0;

sample_n = round(duration_s * task_rate_hz);
if sample_n <= 0
  error("duration_s must produce at least one sample.");
end
t_cmd = (0:sample_n-1)' / task_rate_hz;
u = offset_a + amp_a * sin(2 * pi * freq_hz * t_cmd + phase_rad);

fprintf("Sine command: amp=%.4f A, offset=%.4f A, freq=%.4f Hz, phase=%.4f rad, duration=%.3f s, N=%d\n", ...
  amp_a, offset_a, freq_hz, phase_rad, duration_s, sample_n);
stream_opts = derive_streaming_options(task_rate_hz, sample_n);

%% Run experiment
out = experiment.run_virtualmotor( ...
  "ams_net_id", ams_net_id, ...
  "vm_ams_port", vm_ams_port, ...
  "vm_param_symbol_prefix", vm_param_symbol_prefix, ...
  "current_profile", u, ...
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

%% Evaluation and plotting
raw = out.raw;
cfg = out.config;
metrics = out.metrics;
seg = aligned_segment(raw, out.cmd.current_profile(:), metrics, cfg);

figure("Name", "virtualMotor Validation", "Color", "w");
tiledlayout(3, 1, "Padding", "compact", "TileSpacing", "compact");

nexttile;
if seg.available
  plot(seg.t, seg.command_current, "k-", "LineWidth", 1.1); hold on;
  plot(seg.t, seg.plc_current, "b--", "LineWidth", 1.0); hold off;
  legend("Command current", "PLC current", "Location", "best");
else
  text(0.1, 0.5, "Aligned current segment unavailable", "FontSize", 11);
  axis off;
end
grid on;
xlabel("Time [s]"); ylabel("Current [A]");
title("Time x Current");

nexttile;
if seg.available
  plot(seg.t, seg.plc_position, "r-", "LineWidth", 1.1); hold on;
  plot(seg.t, seg.estimated_position, "m--", "LineWidth", 1.0);
  hold off;
  legend("PLC position", "Estimated position", "Location", "best");
else
  text(0.1, 0.5, "Aligned position segment unavailable", "FontSize", 11);
  axis off;
end
grid on;
xlabel("Time [s]");
ylabel("Position");
title("Time x Position");

nexttile;
if seg.available
  plot(seg.t, seg.velocity, "g.-", "LineWidth", 1.1);
else
  text(0.1, 0.5, "Velocity segment unavailable", "FontSize", 11);
  axis off;
end
grid on;
xlabel("Time [s]"); ylabel("Velocity");
title("Time x Velocity");

sgtitle(sprintf("virtualMotor Validation | current max|err|=%.3g", metrics.input_waveform.max_abs_err));
drawnow;

print_summary(out, seg);
if ~logical(metrics.acceptance.input_waveform_exact_match) && ~isempty(metrics.notes)
  fprintf("--- Notes ---\n");
  for i = 1:numel(metrics.notes)
    fprintf("  - %s\n", string(metrics.notes{i}));
  end
end

function seg = aligned_segment(raw, ref_profile, metrics, cfg)
log_i = raw.log_i(:);
log_x = raw.log_x(:);
pred_x = experiment.simulate_position(log_i, cfg);

seg = struct( ...
  "available", false, ...
  "t", zeros(0, 1), ...
  "command_current", zeros(0, 1), ...
  "plc_current", zeros(0, 1), ...
  "plc_position", zeros(0, 1), ...
  "estimated_position", zeros(0, 1), ...
  "velocity", zeros(0, 1));

best_start = double(metrics.input_waveform.best_start_idx);
seg_len = double(metrics.input_waveform.aligned_length);
if best_start < 1 || seg_len <= 0
  return;
end

end_idx = best_start + seg_len - 1;
if end_idx > numel(log_i) || end_idx > numel(log_x) || seg_len > numel(ref_profile)
  return;
end

idx = best_start:end_idx;
seg.available = true;
seg.t = (0:seg_len-1)' / cfg.task_rate_hz;
seg.command_current = ref_profile(1:seg_len);
seg.plc_current = log_i(idx);
seg.plc_position = log_x(idx);
seg.estimated_position = pred_x(idx);
seg.velocity = [0.0; diff(seg.plc_position) * cfg.task_rate_hz];
end

function print_summary(out, seg)
metrics = out.metrics;
raw = out.raw;

fprintf("\n=== virtualMotor Validation Summary ===\n");
count_cmd = numel(out.cmd.current_profile);
count_i = numel(raw.log_i);
count_x = numel(raw.log_x);
count_aligned = numel(seg.t);

checks = [ ...
  logical(metrics.input_waveform.exact_sample_count_match), ...
  logical(metrics.input_waveform.exact_value_match), ...
  logical(metrics.sampling.all_sample_counts_match), ...
  logical(metrics.acceptance.seq_no_gap_aligned), ...
  logical(metrics.acceptance.total_sample_count_exact_match), ...
  logical(metrics.acceptance.input_waveform_exact_match)];
pass_n = sum(checks);
total_n = numel(checks);

fprintf("Overview\n");
fprintf("  Samples  cmd=%d, logI=%d, logX=%d, aligned=%d\n", count_cmd, count_i, count_x, count_aligned);
fprintf("  Current  max=%.3g, mean=%.3g, rmse=%.3g, corr=%.6g\n", ...
  metrics.input_waveform.max_abs_err, ...
  metrics.input_waveform.mean_abs_err, ...
  metrics.input_waveform.rmse, ...
  metrics.input_waveform.corrcoef);
fprintf("  Result   %s  (%d/%d checks passed)\n", passfail(pass_n == total_n), pass_n, total_n);

fprintf("\nStreaming\n");
fprintf("  enabled=%s, fallback=%s, samples=%d, read_total_s=%.6g, overflow=%s\n", ...
  passfail(out.host.log_stream_enabled), ...
  passfail(~out.host.log_stream_fallback_used), ...
  double(out.host.log_samples_captured), ...
  double(out.host.log_read_time_s_total), ...
  passfail(~raw.log_overflow));
if strlength(string(out.host.log_stream_error_identifier)) > 0
  fprintf("  last_error=%s | %s\n", ...
    string(out.host.log_stream_error_identifier), ...
    string(out.host.log_stream_error_message));
end

fprintf("\nChecks\n");
print_check("sample_count_match", metrics.input_waveform.exact_sample_count_match);
print_check("value_exact_match", metrics.input_waveform.exact_value_match);
print_check("all_sample_counts_match", metrics.sampling.all_sample_counts_match);
print_check("sequence_no_gap_aligned", metrics.acceptance.seq_no_gap_aligned);
print_check("total_sample_count_exact", metrics.acceptance.total_sample_count_exact_match);
print_check("input_waveform_exact", metrics.acceptance.input_waveform_exact_match);

fprintf("\nAlignment\n");
fprintf("  start_idx=%d, aligned_len=%d, seq_missing=%d, pre_roll=%d, post_roll=%d\n", ...
  double(metrics.input_waveform.best_start_idx), ...
  double(metrics.input_waveform.aligned_length), ...
  double(metrics.sampling.aligned_sequence_missing_count), ...
  double(metrics.sampling.pre_roll_count), ...
  double(metrics.sampling.post_roll_count));
end

function s = passfail(flag)
if logical(flag)
  s = "OK";
else
  s = "NG";
end
end

function print_check(name, flag)
fprintf("  %-28s %s\n", name, passfail(flag));
end

function opts = derive_streaming_options(task_rate_hz, sample_n)
log_poll_period_s = min(0.01, max(0.001, 100 / task_rate_hz));
log_chunk_n = max(4096, 4 * ceil(task_rate_hz * log_poll_period_s));
log_host_max_n = max(2 * sample_n, sample_n + 1000);
opts = struct( ...
  "log_poll_period_s", double(log_poll_period_s), ...
  "log_chunk_n", double(log_chunk_n), ...
  "log_host_max_n", double(log_host_max_n));
end

function validate_complete_capture_or_throw(out, expected_n)
metrics = out.metrics;
raw = out.raw;
host = out.host;

count_cmd = numel(out.cmd.current_profile);
count_i = numel(raw.log_i);
count_x = numel(raw.log_x);
count_seq = numel(raw.log_seq);
counts_msg = sprintf("cmd=%d, logSeq=%d, logI=%d, logX=%d", count_cmd, count_seq, count_i, count_x);

must_be_true(logical(metrics.acceptance.log_available), ...
  "experiment:script:logUnavailable", ...
  sprintf("No log data captured (%s).", counts_msg));
must_be_true(~logical(raw.log_overflow), ...
  "experiment:script:logOverflow", ...
  sprintf("Log overflow detected (%s).", counts_msg));
must_be_true(logical(metrics.sampling.all_sample_counts_match), ...
  "experiment:script:sampleCountMismatch", ...
  sprintf("Sample counts do not match (%s).", counts_msg));
must_be_true(logical(metrics.acceptance.total_sample_count_exact_match), ...
  "experiment:script:totalSampleCountMismatch", ...
  sprintf("Total sample count exact match failed (%s).", counts_msg));

if isfield(metrics.acceptance, "seq_no_gap")
  seq_ok = logical(metrics.acceptance.seq_no_gap);
else
  seq_ok = logical(metrics.acceptance.seq_no_gap_aligned);
  if count_seq > 1
    seq_ok = seq_ok && all(udint_seq_step_is_one(raw.log_seq(:)));
  end
end
must_be_true(seq_ok, ...
  "experiment:script:sequenceGap", ...
  sprintf("Sequence gap detected in captured samples (%s).", counts_msg));
must_be_true(logical(metrics.acceptance.input_waveform_exact_match), ...
  "experiment:script:waveformMismatch", ...
  sprintf("Captured current waveform differs from commanded profile (%s).", counts_msg));
must_be_true(isfield(host, "log_stream_enabled") && logical(host.log_stream_enabled), ...
  "experiment:script:streamDisabled", ...
  sprintf("Streaming capture was not active at completion (%s).", counts_msg));
must_be_true(isfield(host, "log_stream_fallback_used") && ~logical(host.log_stream_fallback_used), ...
  "experiment:script:streamFallback", ...
  sprintf("Streaming capture fell back to non-streaming path (%s).", counts_msg));
must_be_true(count_i == double(expected_n), ...
  "experiment:script:expectedCountMismatch", ...
  sprintf("Expected exactly %d samples in log_i (%s).", double(expected_n), counts_msg));

if count_i ~= double(expected_n) || count_x ~= double(expected_n) || count_seq ~= double(expected_n)
  error("experiment:script:counts", ...
    "Strict capture validation failed (%s, expected=%d).", counts_msg, double(expected_n));
end
end

function must_be_true(flag, id, msg)
if logical(flag)
  return;
end
error(id, "%s", msg);
end

function tf = udint_seq_step_is_one(seq)
seq = double(seq(:));
if numel(seq) <= 1
  tf = true(0, 1);
  return;
end
max_udint = 2^32;
step = mod(seq(2:end) - seq(1:end-1), max_udint);
tf = (step == 1);
end
