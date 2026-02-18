function metrics = preload_eval(raw, cmd, cfg)
metrics = struct();
metrics.current.command = cmd.current_in;
metrics.current.profile_length = numel(cmd.current_profile);
metrics.current.last = raw.current_last;
metrics.position.last = raw.position_last;

logSeq = raw.log_seq(:);
logI = raw.log_i(:);
logX = raw.log_x(:);
N = numel(logSeq);
metrics.sample_count = N;

metrics.log.overflow = logical(raw.log_overflow);
[iw, iwAccept, iwNotes] = evaluate_input_waveform(cmd.current_profile(:), logI);
metrics.input_waveform = iw;
metrics.comparison.current_command_vs_plc = iw;

[sampling, samplingAccept] = evaluate_sampling(logSeq, logX, iw, cmd.current_profile(:));
metrics.sampling = sampling;

metrics.acceptance.io_available = true;
metrics.acceptance.log_available = (N > 0);
metrics.acceptance.input_waveform_exact_match = iwAccept;
metrics.acceptance.input_waveform_max_abs_le_1e_6 = iwAccept;
metrics.acceptance.seq_no_gap_aligned = samplingAccept.seq_no_gap_aligned;
metrics.acceptance.command_and_position_sample_count_match = samplingAccept.sample_count_match;
metrics.acceptance.total_sample_count_exact_match = samplingAccept.total_sample_count_exact_match;

metrics.notes = {
    "VM contract is current input to position output."
    "Log collection belongs to upper layer (GVL_VM_LOG)."
    };
metrics.notes = [metrics.notes; iwNotes];

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

predX = simulate_position_from_current(logI, cfg);
xErr = logX - predX;
seqDiff = diff(logSeq);

metrics.seq.first = logSeq(1);
metrics.seq.last = logSeq(end);
metrics.seq.missing_count = sum(seqDiff ~= 1);

captureTimeS = (logSeq(end) - logSeq(1) + 1) / cfg.task_rate_hz;
metrics.throughput.capture_time_s = captureTimeS;
metrics.throughput.plc_log_rate_hz = N / max(captureTimeS, eps);

metrics.model.position.max_abs_err = max(abs(xErr));
metrics.model.position.mean_abs_err = mean(abs(xErr));
metrics.model.position.rmse = sqrt(mean(xErr.^2));

metrics.acceptance.seq_no_gap = (metrics.seq.missing_count == 0);
metrics.acceptance.position_model_max_abs_le_1e_6 = metrics.model.position.max_abs_err <= 1e-6;
metrics.acceptance.log_not_overflowed = ~metrics.log.overflow;
metrics.acceptance.plc_log_rate_ok = ...
    abs(metrics.throughput.plc_log_rate_hz - cfg.task_rate_hz) / cfg.task_rate_hz < 0.01;
end

function [iw, accept, notes] = evaluate_input_waveform(refProfile, logI)
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

refProfile = double(refProfile(:));
logI = double(logI(:));
nRef = numel(refProfile);
nLog = numel(logI);

if nRef == 0
    notes{end + 1, 1} = "Input waveform check skipped: empty current_profile.";
    return;
end

iw.has_reference = true;
iw.segment_length = uint32(nRef);
iw.exact_sample_count_match = (nLog == nRef);

if nLog ~= nRef
    notes{end + 1, 1} = "Input waveform check failed: log_i length must exactly match current_profile length.";
    return;
end

seg = logI(1:nRef);
err = seg - refProfile;
iw.aligned_length = uint32(nRef);
iw.best_start_idx = uint32(1);
iw.max_abs_err = max(abs(err));
iw.mean_abs_err = mean(abs(err));
iw.rmse = sqrt(mean(err .^ 2));
iw.exact_value_match = all(seg == refProfile);

if std(refProfile) > 0 && std(seg) > 0
    c = corrcoef(refProfile, seg);
    iw.corrcoef = c(1, 2);
else
    iw.corrcoef = NaN;
end

accept = iw.exact_sample_count_match && iw.exact_value_match;
end

function [sampling, accept] = evaluate_sampling(logSeq, logX, iw, refProfile)
refProfile = refProfile(:);
nCmd = numel(refProfile);
nPos = numel(logX);
nSeq = numel(logSeq);
nCur = nSeq;
sampleMatchCurPos = (nCur == nPos);
sampleMatchCmdCurTotal = (nCmd == nCur);
sampleMatchCmdPosTotal = (nCmd == nPos);
sampleMatchAllTotal = sampleMatchCurPos && sampleMatchCmdCurTotal && sampleMatchCmdPosTotal;
seqNoGapTotal = (nSeq > 0) && all(diff(logSeq) == 1);

sampling = struct( ...
    "command_count", uint32(nCmd), ...
    "current_log_count_total", uint32(nCur), ...
    "position_log_count_total", uint32(nPos), ...
    "sequence_count_total", uint32(nSeq), ...
    "current_and_position_sample_count_match", sampleMatchCurPos, ...
    "command_and_current_sample_count_match", sampleMatchCmdCurTotal, ...
    "command_and_position_sample_count_match", sampleMatchCmdPosTotal, ...
    "all_sample_counts_match", sampleMatchAllTotal, ...
    "aligned_position_count", uint32(0), ...
    "aligned_sequence_missing_count", uint32(0), ...
    "pre_roll_count", uint32(0), ...
    "post_roll_count", uint32(0), ...
    "aligned_has_window", false);

accept = struct( ...
    "seq_no_gap_aligned", seqNoGapTotal, ...
    "sample_count_match", sampleMatchAllTotal, ...
    "total_sample_count_exact_match", sampleMatchAllTotal);

startIdx = double(iw.best_start_idx);
alignedN = double(iw.aligned_length);
if startIdx < 1 || alignedN <= 0
    return;
end

endIdx = startIdx + alignedN - 1;
if endIdx > nPos || endIdx > nSeq
    return;
end

alignedSeq = logSeq(startIdx:endIdx);
seqMissing = sum(diff(alignedSeq) ~= 1);

sampling.aligned_has_window = true;
sampling.aligned_position_count = uint32(alignedN);
sampling.aligned_sequence_missing_count = uint32(seqMissing);
sampling.pre_roll_count = uint32(startIdx - 1);
sampling.post_roll_count = uint32(nCur - endIdx);
accept.seq_no_gap_aligned = (seqMissing == 0) && seqNoGapTotal;
end
