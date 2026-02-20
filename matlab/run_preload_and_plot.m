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

%% Run experiment
out = experiment.run_virtualmotor( ...
  "ams_net_id", ams_net_id, ...
  "vm_ams_port", vm_ams_port, ...
  "vm_param_symbol_prefix", vm_param_symbol_prefix, ...
  "current_profile", u, ...
  "hold_seconds", duration_s, ...
  "wait_for_done", true, ...
  "task_rate_hz", task_rate_hz, ...
  "m", m, ...
  "d", d, ...
  "kt", kt, ...
  "tau_limit", tau_limit, ...
  "vel_limit", vel_limit);

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
if ~isempty(metrics.notes)
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
