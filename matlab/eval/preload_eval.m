function metrics = preload_eval(raw, cmd, cfg)
% Evaluation for minimal virtualMotor contract: current_in -> position_out.

metrics = struct();
metrics.current.command = cmd.current_in;
metrics.current.last = raw.current_last;
metrics.position.last = raw.position_last;

logSeq = raw.log_seq(:);
logI = raw.log_i(:);
logX = raw.log_x(:);
N = numel(logSeq);
metrics.sample_count = N;

if N == 0
    metrics.notes = {
        "No GVL_VM_LOG data found."
        "Contract validation used direct I/O only."
        };
    metrics.acceptance.io_available = true;
    metrics.acceptance.log_available = false;
    return;
end

Ts = 1 / cfg.task_rate_hz;
mPos = cfg.M;
dNonNeg = max(0, cfg.D);
ktAbs = abs(cfg.Kt);
tauLim = abs(cfg.tau_limit);
velLim = abs(cfg.vel_limit);

predX = zeros(N, 1);
v = 0.0;
x = 0.0;
for k = 1:N
    tau = clamp_scalar(ktAbs * logI(k), tauLim);
    v = v + (Ts / mPos) * (tau - dNonNeg * v);
    v = clamp_scalar(v, velLim);
    x = x + Ts * v;
    predX(k) = x;
end

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
metrics.log.overflow = logical(raw.log_overflow);

metrics.acceptance.io_available = true;
metrics.acceptance.log_available = true;
metrics.acceptance.seq_no_gap = (metrics.seq.missing_count == 0);
metrics.acceptance.position_model_max_abs_le_1e_6 = metrics.model.position.max_abs_err <= 1e-6;
metrics.acceptance.log_not_overflowed = ~metrics.log.overflow;
metrics.acceptance.plc_log_rate_ok = ...
    abs(metrics.throughput.plc_log_rate_hz - cfg.task_rate_hz) / cfg.task_rate_hz < 0.01;

metrics.notes = {
    "VM contract is current input to position output."
    "Log collection belongs to upper layer (GVL_VM_LOG)."
    };
end

function y = clamp_scalar(x, limit)
lim = abs(limit);
if x > lim
    y = lim;
elseif x < -lim
    y = -lim;
else
    y = x;
end
end
