function metrics = preload_eval(raw, cmd, cfg)
ref_segment = getfield_or(cmd, "ref_profile", zeros(0, 1));
ff_segment = getfield_or(cmd, "ff_profile", zeros(0, 1));
dist_segment = getfield_or(cmd, "dist_profile", zeros(0, 1));
repeat_count = max(1, floor(scalar_field_or(cmd, "repeat_count", 1)));
ref_cmd = repeat_waveform(ref_segment, repeat_count);
ff_cmd = repeat_waveform(ff_segment, repeat_count);
dist_cmd = repeat_waveform(dist_segment, repeat_count);

log_seq = col(raw, "seq");
log_ref = col(raw, "ref_value");
log_ff = col(raw, "ff_value");
log_dist = col(raw, "dist_value");
log_u = col(raw, "control_input");
log_tau = col(raw, "target_current");
log_pos = col(raw, "position_act");

n_cmd = numel(ref_cmd);
n_seq = numel(log_seq);
counts = [n_seq, numel(log_ref), numel(log_ff), numel(log_dist), numel(log_u), numel(log_tau), numel(log_pos)];
all_counts_match = all(counts == n_seq);
seq_gap_count = sum(~udint_seq_step_is_one(log_seq));

metrics = struct();
metrics.sample_count = n_seq;
metrics.seq = struct("missing_count", double(seq_gap_count));
if n_seq > 0
  metrics.seq.first = double(log_seq(1));
  metrics.seq.last = double(log_seq(end));
else
  metrics.seq.first = NaN;
  metrics.seq.last = NaN;
end

metrics.input_waveform = compare_exact_waveform(ref_cmd, log_ref, cfg);
metrics.ff_waveform = compare_exact_waveform(ff_cmd, log_ff, cfg);
metrics.dist_waveform = compare_exact_waveform(dist_cmd, log_dist, cfg);
metrics.torque_sum = compare_torque_sum(log_u, log_dist, log_tau);
metrics.position_diag = build_position_diag(log_pos, cfg);

metrics.sampling = struct( ...
  "command_count", uint32(n_cmd), ...
  "segment_command_count", uint32(numel(ref_segment)), ...
  "repeat_count", uint32(repeat_count), ...
  "ref_log_count", uint32(numel(log_ref)), ...
  "ff_log_count", uint32(numel(log_ff)), ...
  "dist_log_count", uint32(numel(log_dist)), ...
  "controlInput_log_count", uint32(numel(log_u)), ...
  "target_torque_log_count", uint32(numel(log_tau)), ...
  "position_log_count", uint32(numel(log_pos)), ...
  "all_sample_counts_match", logical(all_counts_match), ...
  "aligned_sequence_missing_count", uint32(seq_gap_count));

metrics.acceptance = struct();
metrics.acceptance.io_available = true;
metrics.acceptance.log_available = (n_seq > 0);
metrics.acceptance.input_waveform_exact_match = logical(metrics.input_waveform.exact_value_match && metrics.input_waveform.exact_sample_count_match);
metrics.acceptance.ff_waveform_exact_match = logical(metrics.ff_waveform.exact_value_match && metrics.ff_waveform.exact_sample_count_match);
metrics.acceptance.dist_waveform_exact_match = logical(metrics.dist_waveform.exact_value_match && metrics.dist_waveform.exact_sample_count_match);
metrics.acceptance.torque_sum_exact_match = logical(metrics.torque_sum.exact_match);
metrics.acceptance.seq_no_gap = (seq_gap_count == 0);
metrics.acceptance.seq_no_gap_aligned = metrics.acceptance.seq_no_gap;
metrics.acceptance.total_sample_count_exact_match = (n_seq == n_cmd);
metrics.acceptance.command_and_position_sample_count_match = (n_cmd == numel(log_pos));

metrics.notes = {
  "ExperimentSequencer contract: ref/ff/dist table replay (DriverAdapter combines current-domain controlInput + distValue, and the resulting command current is recorded in logs)."
  "ControllerCore contract: controlInput = u_fb + ffValue."
  "Load-side position is logged via ExperimentLogger load_position."
};
end

function c = compare_exact_waveform(cmd_vec, log_vec, cfg)
cmd_vec = double(cmd_vec(:));
log_vec = double(log_vec(:));
n_cmd = numel(cmd_vec);
n_log = numel(log_vec);
abs_tol = cfg_field_or(cfg, "waveform_diag_abs_tol", 1e-12);
preview_n = min(cfg_field_or(cfg, "waveform_diag_preview_n", 8), min(n_cmd, n_log));

c = struct( ...
  "has_reference", n_cmd > 0, ...
  "segment_length", uint32(n_cmd), ...
  "aligned_length", uint32(min(n_cmd, n_log)), ...
  "best_start_idx", uint32(1), ...
  "exact_sample_count_match", n_cmd == n_log, ...
  "exact_value_match", false, ...
  "max_abs_err", NaN, ...
  "mean_abs_err", NaN, ...
  "rmse", NaN, ...
  "corrcoef", NaN, ...
  "zero_shift_max_abs_err", NaN, ...
  "zero_shift_exact_value_match", false, ...
  "zero_shift_abs_tol_match", false, ...
  "best_shift_samples", int32(0), ...
  "best_shift_overlap_length", uint32(min(n_cmd, n_log)), ...
  "best_shift_exact_value_match", false, ...
  "best_shift_abs_tol_match", false, ...
  "best_shift_max_abs_err", NaN, ...
  "best_shift_rmse", NaN, ...
  "best_shift_corrcoef", NaN, ...
  "mismatch_class", "count_mismatch", ...
  "head_preview", empty_preview_struct(), ...
  "tail_preview", empty_preview_struct());

if n_cmd == 0
  c.mismatch_class = "no_reference";
  return;
end
if n_cmd ~= n_log
  c.head_preview = make_preview(cmd_vec, log_vec, preview_n, true);
  c.tail_preview = make_preview(cmd_vec, log_vec, preview_n, false);
  return;
end

err = log_vec - cmd_vec;
c.max_abs_err = max(abs(err));
c.mean_abs_err = mean(abs(err));
c.rmse = sqrt(mean(err.^2));
c.zero_shift_max_abs_err = c.max_abs_err;
c.exact_value_match = all(log_vec == cmd_vec);
c.zero_shift_exact_value_match = c.exact_value_match;
c.zero_shift_abs_tol_match = all(abs(err) <= abs_tol);
c.best_shift_exact_value_match = c.exact_value_match;
c.best_shift_abs_tol_match = c.zero_shift_abs_tol_match;
c.best_shift_max_abs_err = c.max_abs_err;
c.best_shift_rmse = c.rmse;
if std(cmd_vec) > 0 && std(log_vec) > 0
  m = corrcoef(cmd_vec, log_vec);
  c.corrcoef = m(1, 2);
  c.best_shift_corrcoef = c.corrcoef;
end
if c.exact_value_match
  c.mismatch_class = "exact";
elseif c.zero_shift_abs_tol_match
  c.mismatch_class = "small_numeric_delta";
else
  c.mismatch_class = "value_transform_or_other";
end
c.head_preview = make_preview(cmd_vec, log_vec, preview_n, true);
c.tail_preview = make_preview(cmd_vec, log_vec, preview_n, false);
end

function out = compare_torque_sum(log_u, log_dist, logTau)
log_u = double(log_u(:));
log_dist = double(log_dist(:));
logTau = double(logTau(:));
n = min([numel(log_u), numel(log_dist), numel(logTau)]);
out = struct("exact_match", false, "max_abs_err", NaN, "rmse", NaN, "n", uint32(n));
if n <= 0
  return;
end
err = (log_u(1:n) + log_dist(1:n)) - logTau(1:n);
out.max_abs_err = max(abs(err));
out.rmse = sqrt(mean(err.^2));
out.exact_match = all(abs(err) <= 1e-12);
end

function pd = build_position_diag(log_pos, cfg)
log_pos = double(log_pos(:));
pd = struct("available", ~isempty(log_pos), "sample_count", uint32(numel(log_pos)));
if isempty(log_pos)
  return;
end
if has_cfg_field(cfg, "task_rate_hz")
  pd.velocity_est = [0.0; diff(log_pos) * double(cfg.task_rate_hz)];
else
  pd.velocity_est = zeros(numel(log_pos), 1);
end
end

function out = make_preview(cmd_vec, log_vec, n, from_head)
out = empty_preview_struct();
if n <= 0
  return;
end
if from_head
  out.cmd = cmd_vec(1:n);
  out.log = log_vec(1:n);
else
  out.cmd = cmd_vec(end-n+1:end);
  out.log = log_vec(end-n+1:end);
end
out.err_zero_shift = out.log - out.cmd;
out.cmd_shifted_best = out.cmd;
out.err_best_shift = out.err_zero_shift;
end

function p = empty_preview_struct()
p = struct("cmd", zeros(0,1), "log", zeros(0,1), "err_zero_shift", zeros(0,1), "cmd_shifted_best", zeros(0,1), "err_best_shift", zeros(0,1));
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

function tf = has_cfg_field(cfg, name)
tf = (isstruct(cfg) && isfield(cfg, name)) || (isobject(cfg) && isprop(cfg, name));
end

function x = col(s, field)
if isfield(s, field)
  x = double(s.(field)(:));
else
  x = zeros(0, 1);
end
end

function v = getfield_or(s, field, default_value)
if isfield(s, field)
  v = s.(field);
else
  v = default_value;
end
v = double(v(:));
end

function v = scalar_field_or(s, field, default_value)
v = default_value;
if isfield(s, field)
  v = s.(field);
end
v = double(v);
if isempty(v)
  v = default_value;
else
  v = v(1);
end
end

function out = repeat_waveform(segment, repeat_count)
segment = double(segment(:));
if isempty(segment)
  out = zeros(0, 1);
else
  out = repmat(segment, double(repeat_count), 1);
end
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

