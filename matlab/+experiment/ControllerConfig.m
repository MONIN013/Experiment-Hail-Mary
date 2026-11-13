classdef ControllerConfig
  properties (Constant)
    MAX_SOS_SECTIONS = 10
    SOS_COLUMN_COUNT = 6
    ADS_COEFFICIENTS_PER_SECTION = 5
  end

  properties
    % Packed SOS rows: lpPre, Hlp, lpPost, p, iPre, Hi, iPost, post.
    sos = [1,0,0,1,0,0; 1,0,0,1,0,0; 0,0,0,1,0,0; 1,0,0,1,0,0]
    sample_time_s = NaN
    higs_lp_enabled = false
    higs_lp_gain = 1
    higs_lp_omega_ts = 0
    higs_i_enabled = false
    higs_i_gain = 1
    higs_i_omega_ts = 0
    lp_pre_section_count = 0
    lp_post_section_count = 0
    p_section_count = 1
    i_pre_section_count = 1
    i_post_section_count = 0
    post_section_count = 0
  end

  methods (Static)
    function out = p_only(Kp)
      validate_gain(Kp);
      out = experiment.ControllerConfig.from_sos([double(Kp),0,0,1,0,0], NaN);
    end

    function out = from_sos(sos, sample_time_s)
      % Map a generic cascade to P; a zero I pre-section disables the I branch.
      sos = normalize_sos(sos);
      if size(sos,1) > 7
        error("experiment:controller:tooManySections", ...
          "A generic SOS cascade can contain at most seven rows alongside the three fixed routing rows.");
      end
      if nargin < 2, sample_time_s = NaN; end
      out = experiment.ControllerConfig();
      out.sos = [identity_sos(); sos; zero_sos(); identity_sos()];
      out.sample_time_s = sample_time_s;
      out.p_section_count = size(sos,1);
      out.i_pre_section_count = 1;
      out = out.normalize();
      out.validate();
    end

    function out = from_struct(value)
      if isa(value, "experiment.ControllerConfig")
        if ~isscalar(value), error("experiment:controller:invalid", "ControllerConfig must be scalar."); end
        out = value.normalize(); out.validate(); return;
      end
      if ~isstruct(value) || ~isscalar(value)
        error("experiment:controller:invalid", ...
          "ControllerConfig.from_struct accepts only a scalar struct or ControllerConfig.");
      end
      fields = ["sos", "sample_time_s", "higs_lp_enabled", "higs_lp_gain", ...
        "higs_lp_omega_ts", "higs_i_enabled", "higs_i_gain", "higs_i_omega_ts", ...
        "lp_pre_section_count", "lp_post_section_count", "p_section_count", ...
        "i_pre_section_count", "i_post_section_count", "post_section_count"];
      unknown = setdiff(string(fieldnames(value)), fields);
      if ~isempty(unknown)
        error("experiment:controller:invalid", "Unknown ControllerConfig field(s): %s.", strjoin(unknown, ", "));
      end
      out = experiment.ControllerConfig();
      for name = fields
        if isfield(value,name), out.(name) = value.(name); end
      end
      out = out.normalize(); out.validate();
    end
  end

  methods
    function out = normalize(obj)
      out = obj;
      out.sos = normalize_sos(obj.sos);
      out.sample_time_s = normalize_sample_time(obj.sample_time_s);
      validate_payload(out);
      out.higs_lp_enabled = logical(out.higs_lp_enabled);
      out.higs_lp_gain = double(out.higs_lp_gain);
      out.higs_lp_omega_ts = double(out.higs_lp_omega_ts);
      out.higs_i_enabled = logical(out.higs_i_enabled);
      out.higs_i_gain = double(out.higs_i_gain);
      out.higs_i_omega_ts = double(out.higs_i_omega_ts);
      for name = ["lp_pre_section_count","lp_post_section_count","p_section_count", ...
          "i_pre_section_count","i_post_section_count","post_section_count"]
        out.(name) = double(out.(name));
      end
    end

    function validate(obj)
      normalize_sos(obj.sos);
      normalize_sample_time(obj.sample_time_s);
      validate_payload(obj);
    end

    function s = to_struct(obj)
      out = obj.normalize(); out.validate();
      s = struct("sos",out.sos,"sample_time_s",out.sample_time_s, ...
        "higs_lp_enabled",out.higs_lp_enabled,"higs_lp_gain",out.higs_lp_gain, ...
        "higs_lp_omega_ts",out.higs_lp_omega_ts,"higs_i_enabled",out.higs_i_enabled, ...
        "higs_i_gain",out.higs_i_gain,"higs_i_omega_ts",out.higs_i_omega_ts, ...
        "lp_pre_section_count",out.lp_pre_section_count, ...
        "lp_post_section_count",out.lp_post_section_count,"p_section_count",out.p_section_count, ...
        "i_pre_section_count",out.i_pre_section_count,"i_post_section_count",out.i_post_section_count, ...
        "post_section_count",out.post_section_count);
    end

    function validate_for_task_rate(obj, task_rate_hz)
      out = obj.normalize(); out.validate();
      if ~(isnumeric(task_rate_hz) && isreal(task_rate_hz) && isscalar(task_rate_hz) && ...
          isfinite(double(task_rate_hz)) && double(task_rate_hz)>0)
        error("experiment:controller:invalidTaskRate", "task_rate_hz must be a finite positive scalar.");
      end
      has_memory = out.higs_lp_enabled || out.higs_i_enabled || ...
        any(any(out.sos(:,[2,3,5,6]) ~= 0));
      if isnan(out.sample_time_s)
        if has_memory, error("experiment:controller:missingSampleTime", "A dynamic controller must declare sample_time_s."); end
        return;
      end
      expected = 1/double(task_rate_hz);
      tolerance = max(1e-15,32*eps(max(expected,out.sample_time_s)));
      if abs(out.sample_time_s-expected)>tolerance
        error("experiment:controller:sampleTimeMismatch", ...
          "Controller sample_time_s %.17g does not match task period %.17g s (%g Hz).", ...
          out.sample_time_s,expected,double(task_rate_hz));
      end
    end

    function payload = to_ads_payload(obj)
      out = obj.normalize(); out.validate();
      rows = repmat([1,0,0,0,0],out.MAX_SOS_SECTIONS,1);
      n = size(out.sos,1);
      rows(1:n,:) = out.sos(:,[1,2,3,5,6]);
      payload = struct("coefficients",reshape(rows.',[],1), ...
        "section_count",uint32(n), ...
        "section_counts",uint32([out.lp_pre_section_count,out.lp_post_section_count, ...
          out.p_section_count,out.i_pre_section_count,out.i_post_section_count,out.post_section_count]), ...
        "higs_lp_enabled",out.higs_lp_enabled,"higs_lp_gain",out.higs_lp_gain, ...
        "higs_lp_omega_ts",out.higs_lp_omega_ts,"higs_i_enabled",out.higs_i_enabled, ...
        "higs_i_gain",out.higs_i_gain,"higs_i_omega_ts",out.higs_i_omega_ts);
    end

    function seg = segments(obj)
      % Split the packed bank into the rows of each Fig. 8.9 segment.
      out = obj.normalize(); out.validate();
      index = 1;
      seg = struct();
      for item = {"lpPre", out.lp_pre_section_count; "lpH", 1; "lpPost", out.lp_post_section_count; ...
          "p", out.p_section_count; "iPre", out.i_pre_section_count; "iH", 1; ...
          "iPost", out.i_post_section_count; "post", out.post_section_count}.'
        count = item{2};
        seg.(item{1}) = out.sos(index:index+count-1, :);
        index = index + count;
      end
    end

    function K = linear_system(obj)
      % Linear controller with every HIGS replaced by its linear H row.
      out = obj.normalize(); out.validate();
      seg = out.segments();
      one = identity_system(out.sample_time_s);
      LP = cascade(seg.lpPost, cascade(seg.lpH, cascade(seg.lpPre, one)));
      P = cascade(seg.p, one);
      I = cascade(seg.iPost, cascade(seg.iH, cascade(seg.iPre, one)));
      K = cascade(seg.post, (P + I) * LP);
    end
  end
end

function validate_payload(cfg)
count_names = ["lp_pre_section_count", "lp_post_section_count", "p_section_count", ...
  "i_pre_section_count", "i_post_section_count", "post_section_count"];
counts = zeros(1, numel(count_names));
for k = 1:numel(count_names)
  value = cfg.(count_names(k));
  validate_scalar(value, count_names(k));
  if value < 0 || fix(value) ~= value
    error("experiment:controller:invalid", "Section counts must be nonnegative integers.");
  end
  counts(k) = double(value);
end
validate_boolean(cfg.higs_lp_enabled, "higs_lp_enabled");
validate_boolean(cfg.higs_i_enabled, "higs_i_enabled");
validate_scalar(cfg.higs_lp_gain, "higs_lp_gain");
validate_scalar(cfg.higs_lp_omega_ts, "higs_lp_omega_ts");
validate_scalar(cfg.higs_i_gain, "higs_i_gain");
validate_scalar(cfg.higs_i_omega_ts, "higs_i_omega_ts");
if cfg.higs_lp_gain <= 0 || cfg.higs_lp_omega_ts < 0 || ...
    cfg.higs_i_gain <= 0 || cfg.higs_i_omega_ts < 0
  error("experiment:controller:invalid", "HIGS gains must be positive and omega_ts values nonnegative.");
end
if cfg.higs_lp_enabled && ~(cfg.higs_lp_omega_ts > 0 && cfg.higs_lp_omega_ts <= cfg.higs_lp_gain)
  error("experiment:controller:invalid", "Enabled LP HIGS requires 0 < omega_ts <= gain.");
end
if cfg.higs_i_enabled && ~(cfg.higs_i_omega_ts > 0 && cfg.higs_i_omega_ts <= cfg.higs_i_gain)
  error("experiment:controller:invalid", "Enabled I HIGS requires 0 < omega_ts <= gain.");
end
n = sum(counts) + 2;
if n ~= size(cfg.sos, 1)
  error("experiment:controller:invalid", "Packed SOS must contain six variable segments and two HIGS sections.");
end
if n > experiment.ControllerConfig.MAX_SOS_SECTIONS
  error("experiment:controller:tooManySections", ...
    "Packed SOS has %d sections; ControllerCore supports at most %d.", ...
    n, experiment.ControllerConfig.MAX_SOS_SECTIONS);
end
end

function validate_boolean(value, name)
if ~((islogical(value) || isnumeric(value)) && isreal(value) && isscalar(value) && ...
    isfinite(double(value)) && any(double(value) == [0, 1]))
  error("experiment:controller:invalid", "%s must be a logical scalar.", name);
end
end

function validate_scalar(value, name)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(double(value)))
  error("experiment:controller:invalid", "%s must be a finite real scalar.", name);
end
end

function sys = cascade(sos, sys)
for k = 1:size(sos, 1)
  section = tf(sos(k, 1:3), sos(k, 4:6), sys.Ts, "Variable", "z^-1");
  sys = ss(section) * sys;
end
end

function sys = identity_system(sample_time_s)
if isnan(sample_time_s)
  sample_time_s = 1;
end
sys = ss([], [], [], 1, sample_time_s);
end

function sos = normalize_sos(value)
if isempty(value)
  if ~(isnumeric(value) && isreal(value) && ismatrix(value) && ...
      (isequal(size(value), [0, 0]) || size(value, 2) == 6))
    error("experiment:controller:invalid", "sos must be a finite real numeric N-by-6 matrix.");
  end
  sos = zeros(0, 6);
  return;
end
if ~(isnumeric(value) && isreal(value) && ismatrix(value) && ...
    size(value, 2) == experiment.ControllerConfig.SOS_COLUMN_COUNT && ...
    all(isfinite(double(value(:)))))
  error("experiment:controller:invalid", ...
    "sos must be a finite real numeric N-by-6 matrix [b0 b1 b2 a0 a1 a2].");
end
if size(value, 1) > experiment.ControllerConfig.MAX_SOS_SECTIONS
  error("experiment:controller:tooManySections", ...
    "Controller SOS has %d sections; ControllerCore supports at most %d.", ...
    size(value, 1), experiment.ControllerConfig.MAX_SOS_SECTIONS);
end

sos = double(value);
a0 = sos(:, 4);
if any(a0 == 0)
  error("experiment:controller:invalid", "Every SOS a0 coefficient must be nonzero.");
end
sos(:, 1:3) = sos(:, 1:3) ./ a0;
sos(:, 5:6) = sos(:, 5:6) ./ a0;
sos(:, 4) = 1;
if ~all(isfinite(sos(:)))
  error("experiment:controller:invalid", "Normalized SOS coefficients must be finite.");
end
end

function validate_gain(value)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(double(value)))
  error("experiment:controller:invalid", "Kp must be a finite real numeric scalar.");
end
end

function value = normalize_sample_time(value)
if ~(isnumeric(value) && isreal(value) && isscalar(value))
  error("experiment:controller:invalid", ...
    "sample_time_s must be NaN or a finite positive real scalar.");
end
value = double(value);
if ~(isnan(value) || (isfinite(value) && value > 0))
  error("experiment:controller:invalid", ...
    "sample_time_s must be NaN or a finite positive real scalar.");
end
end

function s = identity_sos()
s = [1, 0, 0, 1, 0, 0];
end

function s = zero_sos()
s = [0, 0, 0, 1, 0, 0];
end
