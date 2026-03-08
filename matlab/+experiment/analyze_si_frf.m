function out = analyze_si_frf(logger_source, varargin)
% analyze_si_frf  logger 信号から SI 用 FRF / coherence を算出する。
%
%   out = experiment.analyze_si_frf(logger_source, "Ts", Ts, "Tcycle", Tcycle)
%
%   入力 logger_source:
%     - experiment.read_logger_bin(...) の戻り値
%     - .raw を持つ struct
%     - ff_value / load_velocity を直接持つ raw struct
%
%   戻り値 out (struct):
%     .input_signal_name
%     .output_signal_name
%     .Ts
%     .window_samples
%     .freq_hz
%     .frf
%     .coherence
%     .trim_info
%     .signals
%     .frd_velocity

  if ~isstruct(logger_source)
    error("experiment:analyze_si_frf:invalidInput", ...
      "logger_source must be a struct.");
  end

  p = inputParser;
  p.addParameter("Ts", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
  p.addParameter("Tcycle", [], @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
  p.addParameter("transient_cycles", 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && floor(x) == x);
  p.parse(varargin{:});
  args = p.Results;

  raw = extract_raw(logger_source);
  if ~isfield(raw, "ff_value") || ~isfield(raw, "load_velocity")
    error("experiment:analyze_si_frf:missingSignal", ...
      "logger_source must contain ff_value and load_velocity.");
  end

  input_signal = double(raw.ff_value(:));
  output_signal = double(raw.load_velocity(:));
  if isempty(input_signal) || isempty(output_signal)
    error("experiment:analyze_si_frf:emptySignal", ...
      "ff_value and load_velocity must not be empty.");
  end
  if numel(input_signal) ~= numel(output_signal)
    error("experiment:analyze_si_frf:lengthMismatch", ...
      "ff_value length (%d) must match load_velocity length (%d).", ...
      numel(input_signal), numel(output_signal));
  end

  Ts = resolve_sample_time(raw, args.Ts);
  window_samples = round(args.Tcycle / Ts);
  if window_samples < 2
    error("experiment:analyze_si_frf:invalidWindow", ...
      "Tcycle/Ts must produce at least 2 samples.");
  end

  total_samples = numel(input_signal);
  start_idx = double(args.transient_cycles) * window_samples + 1;
  if start_idx > total_samples
    error("experiment:analyze_si_frf:notEnoughData", ...
      "Transient removal consumed all samples (%d).", total_samples);
  end

  remaining_samples = total_samples - start_idx + 1;
  usable_period_count = floor(remaining_samples / window_samples);
  if usable_period_count < 1
    error("experiment:analyze_si_frf:notEnoughData", ...
      "Need at least one full cycle after transient removal.");
  end

  usable_samples = usable_period_count * window_samples;
  trim_idx = start_idx:(start_idx + usable_samples - 1);
  input_trim = input_signal(trim_idx);
  output_trim = output_signal(trim_idx);
  window = rectwin(window_samples);
  fs = 1 / Ts;

  [frf, freq_hz] = tfestimate(input_trim, output_trim, window, 0, window_samples, fs);
  coherence = mscohere(input_trim, output_trim, window, 0, window_samples, fs);

  t_trim = [];
  if isfield(raw, "t_s") && ~isempty(raw.t_s)
    t_all = double(raw.t_s(:));
    if numel(t_all) == total_samples
      t_trim = t_all(trim_idx);
    end
  end

  out = struct( ...
    "input_signal_name", "ff_value", ...
    "output_signal_name", "load_velocity", ...
    "Ts", double(Ts), ...
    "window_samples", double(window_samples), ...
    "freq_hz", freq_hz(:), ...
    "frf", frf(:), ...
    "coherence", coherence(:), ...
    "trim_info", struct( ...
      "transient_cycles_removed", double(args.transient_cycles), ...
      "start_index", double(start_idx), ...
      "usable_period_count", double(usable_period_count), ...
      "usable_samples", double(usable_samples), ...
      "samples_discarded_tail", double(remaining_samples - usable_samples), ...
      "total_samples", double(total_samples)), ...
    "signals", struct( ...
      "time_s", t_trim, ...
      "input", input_trim(:), ...
      "output", output_trim(:), ...
      "control_input", get_optional_signal(raw, "control_input", trim_idx), ...
      "current_cmd", get_optional_signal(raw, "current_cmd", trim_idx)), ...
    "frd_velocity", frd(frf(:), freq_hz(:), "FrequencyUnit", "Hz"));
end

function raw = extract_raw(logger_source)
  if isfield(logger_source, "raw") && isstruct(logger_source.raw)
    raw = logger_source.raw;
    return;
  end
  raw = logger_source;
end

function Ts = resolve_sample_time(raw, Ts_override)
  if ~isempty(Ts_override)
    Ts = double(Ts_override);
    return;
  end
  if isfield(raw, "t_s") && numel(raw.t_s) >= 2
    dt = diff(double(raw.t_s(:)));
    dt = dt(isfinite(dt) & dt > 0);
    if ~isempty(dt)
      Ts = median(dt);
      return;
    end
  end
  error("experiment:analyze_si_frf:missingSampleTime", ...
    "Ts is required when logger_source does not provide usable t_s.");
end

function out = get_optional_signal(raw, field_name, idx)
  out = zeros(0, 1);
  if isfield(raw, field_name) && ~isempty(raw.(field_name))
    values = double(raw.(field_name)(:));
    if numel(values) >= idx(end)
      out = values(idx);
    end
  end
end
