classdef ControllerConfig
  properties (Constant)
    MAX_SOS_SECTIONS = 10
    SOS_COLUMN_COUNT = 6
    ADS_COEFFICIENTS_PER_SECTION = 5
  end

  properties
    % Rows use the MATLAB SOS convention [b0 b1 b2 a0 a1 a2].
    % An empty bank is identity feedback; a zero controller is one row with
    % a zero numerator.
    sos = zeros(0, 6)
    % NaN is allowed only for memoryless controllers (identity, zero, gain).
    sample_time_s = NaN
  end

  methods (Static)
    function out = p_only(Kp)
      validate_gain(Kp);
      out = experiment.ControllerConfig.from_struct(struct( ...
        "sos", [double(Kp), 0, 0, 1, 0, 0], ...
        "sample_time_s", NaN));
    end

    function out = from_struct(value)
      if isa(value, "experiment.ControllerConfig")
        if ~isscalar(value)
          error("experiment:controller:invalid", "ControllerConfig must be scalar.");
        end
        out = value.normalize();
        out.validate();
        return;
      end
      if ~isstruct(value) || ~isscalar(value)
        error("experiment:controller:invalid", ...
          "ControllerConfig.from_struct accepts only a scalar struct or ControllerConfig.");
      end

      actual = string(fieldnames(value));
      unknown = setdiff(actual, ["sos", "sample_time_s"]);
      if ~isempty(unknown)
        error("experiment:controller:invalid", ...
          "Unknown ControllerConfig field(s): %s.", strjoin(unknown, ", "));
      end

      out = experiment.ControllerConfig();
      if isfield(value, "sos")
        out.sos = value.sos;
      end
      if isfield(value, "sample_time_s")
        out.sample_time_s = value.sample_time_s;
      end
      out = out.normalize();
      out.validate();
    end
  end

  methods
    function out = normalize(obj)
      out = obj;
      out.sos = normalize_sos(obj.sos);
      out.sample_time_s = normalize_sample_time(obj.sample_time_s);
    end

    function validate(obj)
      normalize_sos(obj.sos);
      normalize_sample_time(obj.sample_time_s);
    end

    function s = to_struct(obj)
      out = obj.normalize();
      out.validate();
      s = struct("sos", out.sos, "sample_time_s", out.sample_time_s);
    end

    function validate_for_task_rate(obj, task_rate_hz)
      out = obj.normalize();
      out.validate();
      if ~(isnumeric(task_rate_hz) && isreal(task_rate_hz) && isscalar(task_rate_hz) && ...
          isfinite(double(task_rate_hz)) && double(task_rate_hz) > 0)
        error("experiment:controller:invalidTaskRate", ...
          "task_rate_hz must be a finite positive scalar.");
      end

      has_memory = ~isempty(out.sos) && any(any(out.sos(:, [2, 3, 5, 6]) ~= 0));
      if isnan(out.sample_time_s)
        if has_memory
          error("experiment:controller:missingSampleTime", ...
            "A dynamic SOS controller must declare sample_time_s.");
        end
        return;
      end

      expected = 1 / double(task_rate_hz);
      tolerance = max(1e-15, 32 * eps(max(expected, out.sample_time_s)));
      if abs(out.sample_time_s - expected) > tolerance
        error("experiment:controller:sampleTimeMismatch", ...
          "Controller sample_time_s %.17g does not match task period %.17g s (%g Hz).", ...
          out.sample_time_s, expected, double(task_rate_hz));
      end
    end

    function payload = to_ads_payload(obj)
      out = obj.normalize();
      out.validate();

      rows = repmat([1, 0, 0, 0, 0], out.MAX_SOS_SECTIONS, 1);
      section_count = size(out.sos, 1);
      if section_count > 0
        rows(1:section_count, :) = out.sos(:, [1, 2, 3, 5, 6]);
      end

      payload = struct( ...
        "coefficients", reshape(rows.', [], 1), ...
        "section_count", uint32(section_count));
    end
  end
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
