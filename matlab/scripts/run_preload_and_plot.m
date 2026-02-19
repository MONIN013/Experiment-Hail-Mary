%% virtualMotor sine-profile validation script
baseDir = fileparts(fileparts(mfilename("fullpath")));
restoredefaultpath;
addpath(genpath(baseDir));

%% Connection and model parameters
amsNetId = "192.168.10.3.1.1";
vmAmsPort = 351;
vmParamSymbolPrefix = "VirtualMotorCore_Obj1 (Module1).";
taskRateHz = 1000;
M = 1;
D = 6;
Kt = 0.1;
tauLimit = 5.0;
velLimit = 100.0;

%% Input waveform parameters
duration_s = 2.0;
freq_hz = 1.0;
amp_a = 0.4;
offset_a = 0.0;
phase_rad = 0.0;

N = round(duration_s * taskRateHz);
if N <= 0
    error("duration_s must produce at least one sample.");
end
tCmd = (0:N-1)' / taskRateHz;
u = offset_a + amp_a * sin(2 * pi * freq_hz * tCmd + phase_rad);

adsAssembly = "C:\Program Files (x86)\Beckhoff\TwinCAT\Functions\TE14xx-ToolsForMatlabAndSimulink\TE140x\NET\TwinCAT.Ads.dll";

fprintf("Sine command: amp=%.4f A, offset=%.4f A, freq=%.4f Hz, phase=%.4f rad, duration=%.3f s, N=%d\n", ...
    amp_a, offset_a, freq_hz, phase_rad, duration_s, N);

%% Run experiment
out = ehm.apps.run_virtualmotor( ...
    "ams_net_id", amsNetId, ...
    "vm_ams_port", vmAmsPort, ...
    "vm_param_symbol_prefix", vmParamSymbolPrefix, ...
    "current_profile", u, ...
    "hold_seconds", duration_s, ...
    "wait_for_done", true, ...
    "task_rate_hz", taskRateHz, ...
    "M", M, ...
    "D", D, ...
    "Kt", Kt, ...
    "tau_limit", tauLimit, ...
    "vel_limit", velLimit, ...
    "ads_assembly", adsAssembly);

%% Evaluation and plotting
raw = out.raw;
cfg = out.config;
m = out.metrics;
seg = aligned_segment(raw, out.cmd.current_profile(:), m, cfg);

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

sgtitle(sprintf("virtualMotor Validation | current max|err|=%.3g", m.input_waveform.max_abs_err));
drawnow;

print_summary(out, seg);
if ~isempty(m.notes)
    fprintf("--- Notes ---\n");
    for i = 1:numel(m.notes)
        fprintf("  - %s\n", string(m.notes{i}));
    end
end

function seg = aligned_segment(raw, refProfile, metrics, cfg)
logI = raw.log_i(:);
logX = raw.log_x(:);
predX = simulate_position_from_current(logI, cfg);

seg = struct( ...
    "available", false, ...
    "t", zeros(0, 1), ...
    "command_current", zeros(0, 1), ...
    "plc_current", zeros(0, 1), ...
    "plc_position", zeros(0, 1), ...
    "estimated_position", zeros(0, 1), ...
    "velocity", zeros(0, 1));

bestStart = double(metrics.input_waveform.best_start_idx);
segLen = double(metrics.input_waveform.aligned_length);
if bestStart < 1 || segLen <= 0
    return;
end

endIdx = bestStart + segLen - 1;
if endIdx > numel(logI) || endIdx > numel(logX) || segLen > numel(refProfile)
    return;
end

idx = bestStart:endIdx;
seg.available = true;
seg.t = (0:segLen-1)' / cfg.task_rate_hz;
seg.command_current = refProfile(1:segLen);
seg.plc_current = logI(idx);
seg.plc_position = logX(idx);
seg.estimated_position = predX(idx);
seg.velocity = [0.0; diff(seg.plc_position) * cfg.task_rate_hz];
end

function print_summary(out, seg)
m = out.metrics;
raw = out.raw;

fprintf("\n=== virtualMotor Validation Summary ===\n");
countCmd = numel(out.cmd.current_profile);
countI = numel(raw.log_i);
countX = numel(raw.log_x);
countAligned = numel(seg.t);

checks = [ ...
    logical(m.input_waveform.exact_sample_count_match), ...
    logical(m.input_waveform.exact_value_match), ...
    logical(m.sampling.all_sample_counts_match), ...
    logical(m.acceptance.seq_no_gap_aligned), ...
    logical(m.acceptance.total_sample_count_exact_match), ...
    logical(m.acceptance.input_waveform_exact_match)];
passN = sum(checks);
totalN = numel(checks);

fprintf("Overview\n");
fprintf("  Samples  cmd=%d, logI=%d, logX=%d, aligned=%d\n", countCmd, countI, countX, countAligned);
fprintf("  Current  max=%.3g, mean=%.3g, rmse=%.3g, corr=%.6g\n", ...
    m.input_waveform.max_abs_err, ...
    m.input_waveform.mean_abs_err, ...
    m.input_waveform.rmse, ...
    m.input_waveform.corrcoef);
fprintf("  Result   %s  (%d/%d checks passed)\n", passfail(passN == totalN), passN, totalN);

fprintf("\nChecks\n");
print_check("sample_count_match", m.input_waveform.exact_sample_count_match);
print_check("value_exact_match", m.input_waveform.exact_value_match);
print_check("all_sample_counts_match", m.sampling.all_sample_counts_match);
print_check("sequence_no_gap_aligned", m.acceptance.seq_no_gap_aligned);
print_check("total_sample_count_exact", m.acceptance.total_sample_count_exact_match);
print_check("input_waveform_exact", m.acceptance.input_waveform_exact_match);

fprintf("\nAlignment\n");
fprintf("  start_idx=%d, aligned_len=%d, seq_missing=%d, pre_roll=%d, post_roll=%d\n", ...
    double(m.input_waveform.best_start_idx), ...
    double(m.input_waveform.aligned_length), ...
    double(m.sampling.aligned_sequence_missing_count), ...
    double(m.sampling.pre_roll_count), ...
    double(m.sampling.post_roll_count));
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
