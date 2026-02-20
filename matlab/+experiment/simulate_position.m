function pred_x = simulate_position(log_i, cfg)
% Simulate position from current using the VM forward model.
log_i = double(log_i(:));
sample_n = numel(log_i);
pred_x = zeros(sample_n, 1);
if sample_n == 0
  return;
end

task_dt_s = 1 / cfg.task_rate_hz;
m_pos = cfg.m;
d_non_neg = max(0, cfg.d);
kt_abs = abs(cfg.kt);
tau_lim = abs(cfg.tau_limit);
vel_lim = abs(cfg.vel_limit);

v = 0.0;
x = 0.0;
for k = 1:sample_n
  tau = clamp_scalar(kt_abs * log_i(k), tau_lim);
  v = v + (task_dt_s / m_pos) * (tau - d_non_neg * v);
  v = clamp_scalar(v, vel_lim);
  x = x + task_dt_s * v;
  pred_x(k) = x;
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
