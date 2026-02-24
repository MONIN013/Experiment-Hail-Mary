function metrics = preload_eval(raw, cmd, cfg)
metrics = struct();
metrics.current.command = cmd.current_in;
metrics.current.profile_length = numel(cmd.current_profile);
metrics.current.last = raw.current_last;
metrics.position.last = raw.position_last;

log_seq = raw.log_seq(:);
log_i = raw.log_i(:);
log_x = raw.log_x(:);
sample_n = numel(log_seq);
metrics.sample_count = sample_n;

metrics.log.overflow = logical(raw.log_overflow);
[iw, iw_accept, iw_notes] = evaluate_input_waveform(cmd.current_profile(:), log_i, cfg);
metrics.input_waveform = iw;
metrics.comparison.current_command_vs_plc = iw;

[sampling, sampling_accept] = evaluate_sampling(log_seq, log_x, iw, cmd.current_profile(:));
metrics.sampling = sampling;

metrics.acceptance.io_available = true;
metrics.acceptance.log_available = (sample_n > 0);
metrics.acceptance.input_waveform_exact_match = iw_accept;
metrics.acceptance.input_waveform_max_abs_le_1e_6 = iw_accept;
metrics.acceptance.input_waveform_abs_tol_match = logical(iw.zero_shift_abs_tol_match);
metrics.acceptance.input_waveform_shift_aligned_match = logical(iw.best_shift_exact_value_match || iw.best_shift_abs_tol_match);
metrics.acceptance.seq_no_gap_aligned = sampling_accept.seq_no_gap_aligned;
metrics.acceptance.command_and_position_sample_count_match = sampling_accept.sample_count_match;
metrics.acceptance.total_sample_count_exact_match = sampling_accept.total_sample_count_exact_match;

metrics.notes = {
  "VM contract is current input to position output."
  "Log collection belongs to upper layer (GVL_VM_LOG)."
  "Waveform shift sign convention: positive best_shift_samples means log_i is delayed relative to current_profile."
  };
metrics.notes = [metrics.notes; iw_notes];
metrics.notes = [metrics.notes; evaluate_logger_cmd_mapping(raw, cmd)];

if sample_n == 0
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
metrics.seq.first = log_seq(1);
metrics.seq.last = log_seq(end);
metrics.seq.missing_count = sum(~udint_seq_step_is_one(log_seq));

capture_time_s = (log_seq(end) - log_seq(1) + 1) / cfg.task_rate_hz;
metrics.throughput.capture_time_s = capture_time_s;
metrics.throughput.plc_log_rate_hz = sample_n / max(capture_time_s, eps);

metrics.model.position.max_abs_err = max(abs(x_err));
metrics.model.position.mean_abs_err = mean(abs(x_err));
metrics.model.position.rmse = sqrt(mean(x_err.^2));

metrics.acceptance.seq_no_gap = (metrics.seq.missing_count == 0);
metrics.acceptance.position_model_max_abs_le_1e_6 = metrics.model.position.max_abs_err <= 1e-6;
metrics.acceptance.log_not_overflowed = ~metrics.log.overflow;
metrics.acceptance.plc_log_rate_ok = ...
  abs(metrics.throughput.plc_log_rate_hz - cfg.task_rate_hz) / cfg.task_rate_hz < 0.01;
end

function notes = evaluate_logger_cmd_mapping(raw, cmd)
notes = cell(0, 1);
if ~isfield(raw, "log_cmd_value") || isempty(raw.log_cmd_value)
  return;
end

log_cmd_value = double(raw.log_cmd_value(:));
log_i = double(raw.log_i(:));
n_cmp = min(numel(log_cmd_value), numel(log_i));
if n_cmp > 0
  same_i = all(log_cmd_value(1:n_cmp) == log_i(1:n_cmp));
  notes{end + 1, 1} = "Logger command-value diagnostic: log_cmd_value vs log_i exact_match=" + string(same_i) + ...
    " (n=" + string(n_cmp) + ").";
end

if isfield(raw, "log_cmd_idx") && ~isempty(raw.log_cmd_idx) && ~isempty(cmd.current_profile)
  idx = double(raw.log_cmd_idx(:));
  n = min(numel(idx), numel(cmd.current_profile));
  idx = idx(1:n);
  in_range = all(idx >= 0) && all(idx < numel(cmd.current_profile));
  expected = (0:n-1)';
  exact_progression = all(idx == expected);
  notes{end + 1, 1} = "Logger cmd_idx diagnostic: in_range=" + string(in_range) + ...
    ", exact_0_based_progression=" + string(exact_progression) + " (n=" + string(n) + ").";
end
end

function [iw, accept, notes] = evaluate_input_waveform(ref_profile, log_i, cfg)
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
  "corrcoef", NaN, ...
  "zero_shift_max_abs_err", NaN, ...
  "zero_shift_exact_value_match", false, ...
  "zero_shift_abs_tol_match", false, ...
  "best_shift_samples", int32(0), ...
  "best_shift_overlap_length", uint32(0), ...
  "best_shift_exact_value_match", false, ...
  "best_shift_abs_tol_match", false, ...
  "best_shift_max_abs_err", NaN, ...
  "best_shift_rmse", NaN, ...
  "best_shift_corrcoef", NaN, ...
  "mismatch_class", "", ...
  "head_preview", empty_preview_struct(), ...
  "tail_preview", empty_preview_struct());
accept = false;
notes = cell(0, 1);

ref_profile = double(ref_profile(:));
log_i = double(log_i(:));
n_ref = numel(ref_profile);
n_log = numel(log_i);
max_shift = cfg_field_or(cfg, "waveform_diag_max_shift_samples", 1);
abs_tol = cfg_field_or(cfg, "waveform_diag_abs_tol", 1e-12);
preview_n = cfg_field_or(cfg, "waveform_diag_preview_n", 8);

if n_ref == 0
  notes{end + 1, 1} = "Input waveform check skipped: empty current_profile.";
  iw.mismatch_class = "no_reference";
  return;
end

iw.has_reference = true;
iw.segment_length = uint32(n_ref);
iw.exact_sample_count_match = (n_log == n_ref);

if n_log == n_ref
  seg = log_i(1:n_ref);
  err = seg - ref_profile;
  iw.aligned_length = uint32(n_ref);
  iw.best_start_idx = uint32(1);
  iw.max_abs_err = max(abs(err));
  iw.mean_abs_err = mean(abs(err));
  iw.rmse = sqrt(mean(err .^ 2));
  iw.exact_value_match = all(seg == ref_profile);
  iw.zero_shift_max_abs_err = iw.max_abs_err;
  iw.zero_shift_exact_value_match = iw.exact_value_match;
  iw.zero_shift_abs_tol_match = all(abs(err) <= abs_tol);
  if std(ref_profile) > 0 && std(seg) > 0
    c = corrcoef(ref_profile, seg);
    iw.corrcoef = c(1, 2);
  else
    iw.corrcoef = NaN;
  end
else
  notes{end + 1, 1} = ...
    "Input waveform check failed: log_i length must exactly match current_profile length.";
end

[best_diag, shift_diags] = evaluate_shift_candidates(ref_profile, log_i, max_shift, abs_tol);
iw.best_shift_samples = int32(best_diag.shift);
iw.best_shift_overlap_length = uint32(best_diag.overlap_n);
iw.best_shift_exact_value_match = logical(best_diag.all_equal);
iw.best_shift_abs_tol_match = logical(best_diag.abs_tol_match);
iw.best_shift_max_abs_err = best_diag.max_abs_err;
iw.best_shift_rmse = best_diag.rmse;
iw.best_shift_corrcoef = best_diag.corrcoef;

if n_log == n_ref
  accept = iw.exact_sample_count_match && iw.exact_value_match;
else
  accept = false;
end

iw.mismatch_class = classify_waveform_mismatch(iw, n_log, n_ref);
iw.head_preview = make_waveform_preview(ref_profile, log_i, preview_n, best_diag, true);
iw.tail_preview = make_waveform_preview(ref_profile, log_i, preview_n, best_diag, false);

if iw.mismatch_class ~= "exact" && iw.has_reference
  notes{end + 1, 1} = "Waveform mismatch classified as " + string(iw.mismatch_class) + ...
    " (best_shift=" + string(best_diag.shift) + ...
    ", max_abs_err@shift=" + string(num2str(best_diag.max_abs_err, "%.6g")) + ").";
end

if ~isempty(shift_diags) && max_shift > 0
  notes{end + 1, 1} = "Waveform diagnostic shifts evaluated in [" + string(-max_shift) + ", +" + string(max_shift) + "] samples.";
end
end

function [best_diag, all_diags] = evaluate_shift_candidates(ref_profile, log_i, max_shift, abs_tol)
shifts = (-double(max_shift):double(max_shift))';
all_diags = repmat(empty_shift_diag(), numel(shifts), 1);
for k = 1:numel(shifts)
  all_diags(k) = evaluate_shift(ref_profile, log_i, shifts(k), abs_tol);
end
best_idx = 1;
for k = 2:numel(all_diags)
  if shift_diag_better(all_diags(k), all_diags(best_idx))
    best_idx = k;
  end
end
best_diag = all_diags(best_idx);
end

function diag = evaluate_shift(ref_profile, log_i, shift, abs_tol)
diag = empty_shift_diag();
diag.shift = double(shift);

[cmd_seg, log_seg] = overlap_for_shift(ref_profile, log_i, shift);
diag.overlap_n = numel(cmd_seg);
if diag.overlap_n <= 0
  return;
end

err = log_seg - cmd_seg;
diag.max_abs_err = max(abs(err));
diag.mean_abs_err = mean(abs(err));
diag.rmse = sqrt(mean(err.^2));
diag.all_equal = all(log_seg == cmd_seg);
diag.abs_tol_match = all(abs(err) <= abs_tol);
if std(cmd_seg) > 0 && std(log_seg) > 0
  c = corrcoef(cmd_seg, log_seg);
  diag.corrcoef = c(1, 2);
end
end

function tf = shift_diag_better(a, b)
if logical(a.all_equal) ~= logical(b.all_equal)
  tf = logical(a.all_equal);
  return;
end
if logical(a.abs_tol_match) ~= logical(b.abs_tol_match)
  tf = logical(a.abs_tol_match);
  return;
end
if a.max_abs_err ~= b.max_abs_err
  tf = a.max_abs_err < b.max_abs_err;
  return;
end
if abs(a.shift) ~= abs(b.shift)
  tf = abs(a.shift) < abs(b.shift);
  return;
end
tf = a.shift < b.shift;
end

function cls = classify_waveform_mismatch(iw, n_log, n_ref)
if n_ref == 0
  cls = "no_reference";
  return;
end
if n_log ~= n_ref
  cls = "count_mismatch";
  return;
end
if logical(iw.exact_value_match)
  cls = "exact";
  return;
end
if logical(iw.best_shift_abs_tol_match) && abs(double(iw.best_shift_samples)) == 1
  cls = "one_sample_shift";
  return;
end
if logical(iw.best_shift_abs_tol_match) && double(iw.best_shift_samples) == 0 && ~logical(iw.exact_value_match)
  cls = "small_numeric_delta";
  return;
end
cls = "value_transform_or_other";
end

function out = make_waveform_preview(ref_profile, log_i, preview_n, best_diag, from_head)
n = min([double(preview_n), numel(ref_profile), numel(log_i)]);
out = empty_preview_struct();
if n <= 0
  return;
end

if from_head
  idx = (1:n)';
else
  idx = (numel(ref_profile)-n+1:numel(ref_profile))';
  idx_log = (numel(log_i)-n+1:numel(log_i))';
end

if from_head
  out.cmd = ref_profile(1:n);
  out.log = log_i(1:n);
else
  out.cmd = ref_profile(idx);
  out.log = log_i(idx_log);
end
out.err_zero_shift = out.log - out.cmd;

[cmd_best, log_best] = preview_shift_segments(ref_profile, log_i, best_diag.shift, n, from_head);
out.cmd_shifted_best = cmd_best;
if ~isempty(cmd_best) && ~isempty(log_best) && numel(cmd_best) == numel(log_best)
  out.err_best_shift = log_best - cmd_best;
else
  out.err_best_shift = zeros(0, 1);
end
end

function [cmd_out, log_out] = preview_shift_segments(ref_profile, log_i, shift, n, from_head)
[cmd_seg, log_seg] = overlap_for_shift(ref_profile, log_i, shift);
if isempty(cmd_seg) || isempty(log_seg)
  cmd_out = zeros(0, 1);
  log_out = zeros(0, 1);
  return;
end
n_take = min(double(n), numel(cmd_seg));
if from_head
  cmd_out = cmd_seg(1:n_take);
  log_out = log_seg(1:n_take);
else
  cmd_out = cmd_seg(end-n_take+1:end);
  log_out = log_seg(end-n_take+1:end);
end
end

function [cmd_seg, log_seg] = overlap_for_shift(ref_profile, log_i, shift)
n_ref = numel(ref_profile);
n_log = numel(log_i);
if shift >= 0
  cmd_start = 1;
  log_start = 1 + double(shift);
else
  cmd_start = 1 + double(-shift);
  log_start = 1;
end
overlap_n = min(n_ref - cmd_start + 1, n_log - log_start + 1);
if overlap_n <= 0
  cmd_seg = zeros(0, 1);
  log_seg = zeros(0, 1);
  return;
end
cmd_idx = cmd_start:(cmd_start + overlap_n - 1);
log_idx = log_start:(log_start + overlap_n - 1);
cmd_seg = ref_profile(cmd_idx);
log_seg = log_i(log_idx);
end

function p = empty_preview_struct()
p = struct( ...
  "cmd", zeros(0, 1), ...
  "log", zeros(0, 1), ...
  "err_zero_shift", zeros(0, 1), ...
  "cmd_shifted_best", zeros(0, 1), ...
  "err_best_shift", zeros(0, 1));
end

function d = empty_shift_diag()
d = struct( ...
  "shift", 0, ...
  "overlap_n", 0, ...
  "all_equal", false, ...
  "abs_tol_match", false, ...
  "max_abs_err", inf, ...
  "mean_abs_err", inf, ...
  "rmse", inf, ...
  "corrcoef", NaN);
end

function v = cfg_field_or(cfg, name, default_value)
v = default_value;
if isstruct(cfg) && isfield(cfg, name)
  v = cfg.(name);
elseif isobject(cfg) && isprop(cfg, name)
  v = cfg.(name);
end
v = double(v);
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
seq_no_gap_total = (n_seq > 0) && all(udint_seq_step_is_one(log_seq));

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
seq_missing = sum(~udint_seq_step_is_one(aligned_seq));

sampling.aligned_has_window = true;
sampling.aligned_position_count = uint32(aligned_n);
sampling.aligned_sequence_missing_count = uint32(seq_missing);
sampling.pre_roll_count = uint32(start_idx - 1);
sampling.post_roll_count = uint32(n_cur - end_idx);
accept.seq_no_gap_aligned = (seq_missing == 0) && seq_no_gap_total;
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
