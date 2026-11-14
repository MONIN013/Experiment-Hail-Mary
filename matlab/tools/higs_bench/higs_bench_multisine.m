function frf = higs_bench_multisine(action, out_dir, name, opts)
% higs_bench_multisine  Open-loop random-odd multisine identification: current command -> motor/load position FRF.
%   higs_bench_multisine("run", out_dir, "ms030", amplitude_a=0.30)   run + analyze; saves ms030.mat and frf_ms030.mat
%   frf = higs_bench_multisine("analyze", out_dir, "ms030")           analyze a saved log again
% One period = 1 s of the task rate, odd lines 5..4999 Hz, one random line of every three left out (distortion
% detection), crest factor limited by 30 clip/projection steps, peak = amplitude_a. The excitation is sent through
% the feedforward table with a zero-gain P controller, repeated `repeats` times; the first 2 periods are dropped.
% frf: f, Hm, Hl, Ha (motor position, load position, actual current per commanded current), sm, Ts.
arguments
  action (1,1) string {mustBeMember(action, ["run", "analyze"])}
  out_dir (1,1) string
  name (1,1) string
  opts.amplitude_a (1,1) double {mustBePositive} = 0.30
  opts.seed (1,1) double = 1
  opts.repeats (1,1) double = 14
  opts.attempts (1,1) double = 3
end

rate = double(experiment.ExperimentConfig.defaults().env.task_rate_hz);
if action == "run"
  u = excitation(rate, opts.amplitude_a, opts.seed);
  fprintf("crest %.2f rms %.4f A\n", max(abs(u)) / rms(u), rms(u));
  res = higs_bench_run(experiment.ControllerConfig.p_only(0), zeros(size(u)), u, out_dir, name, ...
    repeat=opts.repeats, attempts=opts.attempts);
  if ~res.completed
    error("higs_bench:incomplete", "%s did not complete: %s", name, res.message);
  end
end
frf = analyze(out_dir, name, rate);
end

function u = excitation(rate, amplitude, seed)
P = rate;
rng(seed);
odd = 5:2:4999;
grp = reshape(odd(1:floor(numel(odd) / 3) * 3), 3, []);
skip = grp(sub2ind(size(grp), randi(3, 1, size(grp, 2)), 1:size(grp, 2)));
exc = setdiff(odd, skip);
U = zeros(P, 1);
U(exc + 1) = exp(1j * 2 * pi * rand(numel(exc), 1));
u = real(ifft(U)) * P;
for it = 1:30
  u = sign(u) .* min(abs(u), 0.8 * max(abs(u)));
  X = fft(u);
  X(setdiff(1:P, exc + 1)) = 0;
  X(exc + 1) = exp(1j * angle(X(exc + 1)));
  u = real(ifft(X));
end
u = amplitude * u / max(abs(u));
end

function frf = analyze(out_dir, name, rate)
S = load(fullfile(out_dir, name + ".mat"));
r = structfun(@double, S.raw, "UniformOutput", false);
u = S.FF(:);
P = numel(u);
Ts = 1 / rate;
if P ~= rate, error("higs_bench:period", "Period %d samples is not 1 s at %g Hz.", P, rate); end
X = abs(fft(u));
exc = find(X(1:P / 2) > 1e-6 * max(X)) - 1;
skip = setdiff(5:2:4999, exc);
np = floor(numel(r.current_cmd) / P);
per = 3:np;   % drop 2 transient periods
F = @(x) fft(reshape(x(1:np * P), P, np));
Uc = F(r.current_cmd);
Ym = F(detrend(r.motor_position));
Yl = F(detrend(r.load_position));
Ua = F(r.motor_current_act);
e = exc(:) + 1;
f = exc(:);
Hm = mean(Ym(e, per), 2) ./ mean(Uc(e, per), 2);
Hl = mean(Yl(e, per), 2) ./ mean(Uc(e, per), 2);
Ha = mean(Ua(e, per), 2) ./ mean(Uc(e, per), 2);
sm = std(Ym(e, per) ./ Uc(e, per), 0, 2) ./ sqrt(numel(per));
fprintf("pos range [%.3f %.3f] rad, twist max %.2f mrad, Iact max %.3f A\n", min(r.motor_position), max(r.motor_position), ...
  1e3 * max(abs(r.motor_position - r.load_position)), max(abs(r.motor_current_act)));
% nonlinear distortion: output level on skipped odd lines and on even lines vs excited lines
level = mean(abs(Ym(:, per)), 2);
even = (2:2:5000)';
bands = [5 20; 20 50; 50 100; 100 200; 200 400; 400 800; 800 1600; 1600 3200; 3200 5000];
for b = 1:size(bands, 1)
  ke = f >= bands(b, 1) & f < bands(b, 2);
  ks = skip(:) >= bands(b, 1) & skip(:) < bands(b, 2);
  kv = even >= bands(b, 1) & even < bands(b, 2);
  fprintf("%4d-%4d Hz: Ylevel exc %.2e skippedOdd %.2e even %.2e  | rel.std(H) %.3f\n", bands(b, :), ...
    rms(level(e(ke))), rms(level(skip(ks) + 1)), rms(level(even(kv) + 1)), median(sm(ke) ./ abs(Hm(ke))));
end
for fq = [11 31 51 101 151 201 251 301 351 401 501 1001 2001 4001]
  [~, i] = min(abs(f - fq));
  w = 2 * pi * f(i);
  fprintf("%5d Hz |Hm| %.3e Jeq %.3e ph %7.1f | |Hl| %.3e ph %7.1f | Iact/cmd %.3f %6.1f\n", f(i), abs(Hm(i)), ...
    1 / (abs(Hm(i)) * w^2), angle(Hm(i)) * 180 / pi, abs(Hl(i)), angle(Hl(i)) * 180 / pi, abs(Ha(i)), angle(Ha(i)) * 180 / pi);
end
frf = struct("f", f, "Hm", Hm, "Hl", Hl, "Ha", Ha, "sm", sm, "Ts", Ts);
save(fullfile(out_dir, "frf_" + name + ".mat"), "-struct", "frf");
end
