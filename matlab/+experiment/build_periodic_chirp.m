function out = build_periodic_chirp(varargin)
% build_periodic_chirp  周期リセット型 chirp を生成する。
%
%   out = experiment.build_periodic_chirp("Ts", Ts, "Tend", Tend, ...)
%
%   戻り値 out (struct):
%     .t                 - 時刻ベクトル [s]
%     .signal            - chirp 信号
%     .Ts                - サンプル周期 [s]
%     .sample_count      - 総サンプル数
%     .cycle_samples     - 1 周期あたりサンプル数
%     .cycle_count       - 総周期数 (概算)
%     .Tcycle            - chirp 周期 [s]
%     .f0                - 開始周波数 [Hz]
%     .f1                - 終了周波数 [Hz]
%     .amplitude         - 振幅
%     .initial_phase     - 初期位相 [rad]

  p = inputParser;
  p.addParameter("Ts", [], @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
  p.addParameter("Tend", [], @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
  p.addParameter("Tcycle", [], @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
  p.addParameter("f0", [], @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
  p.addParameter("f1", [], @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
  p.addParameter("A", 1.0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
  p.addParameter("initial_phase", 0.0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
  p.parse(varargin{:});
  args = p.Results;

  if isempty(args.Ts) || isempty(args.Tend) || isempty(args.Tcycle) || isempty(args.f0) || isempty(args.f1)
    error("experiment:build_periodic_chirp:invalidConfig", ...
      "Ts, Tend, Tcycle, f0, and f1 are required.");
  end
  if args.f1 <= args.f0
    error("experiment:build_periodic_chirp:invalidConfig", ...
      "f1 must be greater than f0.");
  end
  nyquist_hz = 0.5 / args.Ts;
  if args.f1 >= nyquist_hz
    error("experiment:build_periodic_chirp:invalidConfig", ...
      "f1 (%.6g Hz) must be below Nyquist (%.6g Hz).", args.f1, nyquist_hz);
  end

  sample_count = round(args.Tend / args.Ts);
  if sample_count < 1
    error("experiment:build_periodic_chirp:invalidConfig", ...
      "Tend/Ts must produce at least one sample.");
  end

  cycle_samples = round(args.Tcycle / args.Ts);
  if cycle_samples < 1
    error("experiment:build_periodic_chirp:invalidConfig", ...
      "Tcycle/Ts must produce at least one sample.");
  end

  t = args.Ts * (0:sample_count - 1)';
  t_relative = t - floor(t / args.Tcycle) * args.Tcycle;
  chirp_rate = (args.f1 - args.f0) / args.Tcycle;
  signal = args.A * sin(args.initial_phase + ...
    (2 * pi * (args.f0 * t_relative + 0.5 * chirp_rate * t_relative .^ 2)));

  out = struct( ...
    "t", t, ...
    "signal", signal, ...
    "Ts", double(args.Ts), ...
    "sample_count", double(sample_count), ...
    "cycle_samples", double(cycle_samples), ...
    "cycle_count", double(sample_count / cycle_samples), ...
    "Tcycle", double(args.Tcycle), ...
    "f0", double(args.f0), ...
    "f1", double(args.f1), ...
    "amplitude", double(args.A), ...
    "initial_phase", double(args.initial_phase));
end
