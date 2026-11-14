function S = higs_bench_sensitivity(action, out_dir, name, opts)
% higs_bench_sensitivity  Closed-loop sensitivity |S| on the bench: disturbance multisine on a constant-speed ramp.
%   S = higs_bench_sensitivity("run", out_dir, "sens_both", design_path=..., mode="both")
%   S = higs_bench_sensitivity("analyze", out_dir, "sens_both")
% The ramp reaches speed_rad_s within ramp_s and is held for `periods` periods of 1 s (feedforward
% coulomb_a*tanh(v_ref/0.05)). dist_value carries a random-phase multisine (odd lines 5..999 Hz, peak
% dist_a); S = mean over periods 2.. of FFT(current_cmd) / FFT(dist_value) on the excited lines, because current_cmd
% is the plant input after the disturbance is added. Saves <name>.mat (raw log) and <name>_dist.mat (k, u, P).
% S: f [Hz], Sx (complex).
arguments
  action (1,1) string {mustBeMember(action, ["run", "analyze"])}
  out_dir (1,1) string
  name (1,1) string
  opts.design_path (1,1) string = ""
  opts.mode (1,1) string = "linear"
  opts.speed_rad_s (1,1) double = 2
  opts.ramp_s (1,1) double = 0.5
  opts.dist_a (1,1) double = 0.05
  opts.periods (1,1) double = 6
  opts.coulomb_a (1,1) double = 0.10
  opts.seed (1,1) double = 3
  opts.attempts (1,1) double = 3
end

if action == "run"
  rate = double(experiment.ExperimentConfig.defaults().env.task_rate_hz);
  P = rate;
  ts = 1 / rate;
  t = (0:P * opts.periods - 1)' * ts;
  ref = cumsum(opts.speed_rad_s * min(1, t / opts.ramp_s)) * ts;
  rng(opts.seed);
  k = (5:2:999)';
  U = zeros(P, 1);
  U(k + 1) = exp(1j * 2 * pi * rand(numel(k), 1));
  u = real(ifft(U)) * P;
  u = opts.dist_a * u / max(abs(u));
  if ~isfolder(out_dir), mkdir(out_dir); end
  save(fullfile(out_dir, name + "_dist.mat"), "k", "u", "P");
  res = higs_bench_trial(opts.design_path, opts.mode, out_dir, name, reference=ref, coulomb_a=opts.coulomb_a, ...
    inertia=0, disturbance=repmat(u, opts.periods, 1), attempts=opts.attempts);
  if ~res.completed
    error("higs_bench:incomplete", "%s did not complete: %s", name, res.message);
  end
end
S = analyze(out_dir, name);
end

function S = analyze(out_dir, name)
R = load(fullfile(out_dir, name + ".mat"));
D = load(fullfile(out_dir, name + "_dist.mat"));
r = structfun(@double, R.raw, "UniformOutput", false);
P = D.P;
np = floor(numel(r.current_cmd) / P);
per = 2:np;
F = @(x) fft(reshape(x(1:np * P), P, np));
I = F(r.current_cmd);
Dd = F(r.dist_value);
e = D.k + 1;
S.f = D.k;
S.Sx = mean(I(e, per), 2) ./ mean(Dd(e, per), 2);
n = numel(r.motor_position);
tail = round(n / 3):n;
speed = (r.motor_position(n) - r.motor_position(tail(1))) / (numel(tail) - 1) * P;   % one period = 1 s -> samples/s = P
[smax, i] = max(abs(S.Sx));
fprintf("%s: mean speed %.2f rad/s, |S|max %.2f at %d Hz\n", name, speed, smax, S.f(i));
for fq = [11 21 41 61 81 101 151 201 251 301 401 601 901]
  [~, i] = min(abs(S.f - fq));
  fprintf("  %4d Hz |S| %.2f\n", S.f(i), abs(S.Sx(i)));
end
end
