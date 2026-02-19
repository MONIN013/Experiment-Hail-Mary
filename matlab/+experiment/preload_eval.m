function metrics = preload_eval(raw, cmd, cfg)
metrics = struct();
metrics.current.command = cmd.current_in;
metrics.current.profile_length = numel(cmd.current_profile);
metrics.current.last = raw.current_last;
metrics.position.last = raw.position_last;

log_seq = raw.log_seq(:);
log_i = raw.log_i(:);
log_x = raw.log_x(:);
N = numel(log_seq);
metrics.sample_count = N;

metrics.log.overflow = logical(raw.log_overflow);
[iw, iw_accept, iw_notes] = evaluate_input_waveform(cmd.current_profile(:), log_i);
metrics.input_waveform = iw;
metrics.comparison.current_command_vs_plc = iw;

[sampling, sampling_accept] = evaluate_sampling(log_seq, log_x, iw, cmd.current_profile(:));
metrics.sampling = sampling;

metrics.acceptance.io_available = true;
metrics.acceptance.log_available = (N > 0);
metrics.acceptance.input_waveform_exact_match = iw_accept;
metrics.acceptance.input_waveform_max_abs_le_1e_6 = iw_accept;
metrics.acceptance.seq_no_gap_aligned = sampling_accept.seq_no_gap_aligned;
metrics.acceptance.command_and_position_sample_count_match = sampling_accept.sample_count_match;
metrics.acceptance.total_sample_count_exact_match = sampling_accept.total_sample_count_exact_match;

metrics.notes = {
  "VM contract is current input to position output."
  "Log collection belongs to upper layer (GVL_VM_LOG)."
  };
metrics.notes = [metrics.notes; iw_notes];

if N == 0
  metrics.notes = [
    {
    "No GVL_VM_LOG data found."
    "Contract validation used direct I/O only."
    }
    metrics.notes
  ];
  metrics.acceptance.seq_no_gap = false;
  metrics.acceptance.position_model_max_abs_le_1e_6 = false;
  metrics.acceptance.log_not_overflowed = ~metrics.log.overflow;
  metrics.acceptance.plc_log_rate_ok = false;
  return;
end

pred_x = experiment.simulate_position(log_i, cfg);
x_err = log_x - pred_x;
seq_diff = diff(log_seq);

metrics.seq.first = log_seq(1);
metrics.seq.last = log_seq(end);
metrics.seq.missing_count = sum(seq_diff ~= 1);

capture_time_s = (log_seq(end) - log_seq(1) + 1) / cfg.task_rate_hz;
metrics.throughput.capture_time_s = capture_time_s;
metrics.throughput.plc_log_rate_hz = N / max(capture_time_s, eps);

metrics.model.position.max_abs_err = max(abs(x_err));
metrics.model.position.mean_abs_err = mean(abs(x_err));
metrics.model.position.rmse = sqrt(mean(x_err.^2));

metrics.acceptance.seq_no_gap = (metrics.seq.missing_count == 0);
metrics.acceptance.position_model_max_abs_le_1e_6 = metrics.model.position.max_abs_err <= 1e-6;
metrics.acceptance.log_not_overflowed = ~metrics.log.overflow;
metrics.acceptance.plc_log_rate_ok = ...
  abs(metrics.throughput.plc_log_rate_hz - cfg.task_rate_hz) / cfg.task_rate_hz < 0.01;
end

function [iw, accept, notes] = evaluate_input_waveform(ref_profile, log_i)
iw = struct( ...
  "has_reference", false, ...
  "segment_length", uint32(0), ...
  "aligned_length", uint32(0), ...
  "best_start_idx", uint32(0), ...
  "exact_sample_count_match", false, ...
  "exact_value_match", false, ...
  "max_abs_err", NaN, ...
  "mean_abs_err", NaN, ...
  "rmse", NaN, ...
  "corrcoef", NaN);
accept = false;
notes = {};

ref_profile = double(ref_profile(:));
log_i = double(log_i(:));
n_ref = numel(ref_profile);
n_log = numel(log_i);

if n_ref == 0
  notes{end + 1, 1} = "Input waveform check skipped: empty current_profile.";
  return;
end

iw.has_reference = true;
iw.segment_length = uint32(n_ref);
iw.exact_sample_count_match = (n_log == n_ref);

if n_log ~= n_ref
  notes{end + 1, 1} = ...
    "Input waveform check failed: log_i length must exactly match current_profile length.";
  return;
end

seg = log_i(1:n_ref);
err = seg - ref_profile;
iw.aligned_length = uint32(n_ref);
iw.best_start_idx = uint32(1);
iw.max_abs_err = max(abs(err));
iw.mean_abs_err = mean(abs(err));
iw.rmse = sqrt(mean(err .^ 2));
iw.exact_value_match = all(seg == ref_profile);

if std(ref_profile) > 0 && std(seg) > 0
  c = corrcoef(ref_profile, seg);
  iw.corrcoef = c(1, 2);
else
  iw.corrcoef = NaN;
end

accept = iw.exact_sample_count_match && iw.exact_value_match;
end

function [sampling, accept] = evaluate_sampling(log_seq, log_x, iw, ref_profile)
ref_profile = ref_profile(:);
n_cmd = numel(ref_profile);
n_pos = numel(log_x);
n_seq = numel(log_seq);
n_cur = n_seq;
sample_match_cur_pos = (n_cur == n_pos);
sample_match_cmd_cur_total = (n_cmd == n_cur);
sample_match_cmd_pos_total = (n_cmd == n_pos);
sample_match_all_total = sample_match_cur_pos && sample_match_cmd_cur_total && sample_match_cmd_pos_total;
seq_no_gap_total = (n_seq > 0) && all(diff(log_seq) == 1);

sampling = struct( ...
  "command_count", uint32(n_cmd), ...
  "current_log_count_total", uint32(n_cur), ...
  "position_log_count_total", uint32(n_pos), ...
  "sequence_count_total", uint32(n_seq), ...
  "current_and_position_sample_count_match", sample_match_cur_pos, ...
  "command_and_current_sample_count_match", sample_match_cmd_cur_total, ...
  "command_and_position_sample_count_match", sample_match_cmd_pos_total, ...
  "all_sample_counts_match", sample_match_all_total, ...
  "aligned_position_count", uint32(0), ...
  "aligned_sequence_missing_count", uint32(0), ...
  "pre_roll_count", uint32(0), ...
  "post_roll_count", uint32(0), ...
  "aligned_has_window", false);

accept = struct( ...
  "seq_no_gap_aligned", seq_no_gap_total, ...
  "sample_count_match", sample_match_all_total, ...
  "total_sample_count_exact_match", sample_match_all_total);

start_idx = double(iw.best_start_idx);
aligned_n = double(iw.aligned_length);
if start_idx < 1 || aligned_n <= 0
  return;
end

end_idx = start_idx + aligned_n - 1;
if end_idx > n_pos || end_idx > n_seq
  return;
end

aligned_seq = log_seq(start_idx:end_idx);
seq_missing = sum(diff(aligned_seq) ~= 1);

sampling.aligned_has_window = true;
sampling.aligned_position_count = uint32(aligned_n);
sampling.aligned_sequence_missing_count = uint32(seq_missing);
sampling.pre_roll_count = uint32(start_idx - 1);
sampling.post_roll_count = uint32(n_cur - end_idx);
accept.seq_no_gap_aligned = (seq_missing == 0) && seq_no_gap_total;
end
