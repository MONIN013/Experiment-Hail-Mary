function predX = simulate_position_from_current(logI, cfg)
% Simulate position from current using the VM forward model.
logI = double(logI(:));
N = numel(logI);
predX = zeros(N, 1);
if N == 0
    return;
end

Ts = 1 / cfg.task_rate_hz;
mPos = cfg.M;
dNonNeg = max(0, cfg.D);
ktAbs = abs(cfg.Kt);
tauLim = abs(cfg.tau_limit);
velLim = abs(cfg.vel_limit);

v = 0.0;
x = 0.0;
for k = 1:N
    tau = clamp_scalar(ktAbs * logI(k), tauLim);
    v = v + (Ts / mPos) * (tau - dNonNeg * v);
    v = clamp_scalar(v, velLim);
    x = x + Ts * v;
    predX(k) = x;
end
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
