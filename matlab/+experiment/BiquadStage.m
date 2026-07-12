classdef BiquadStage
  properties
    b0 = 1
    b1 = 0
    b2 = 0
    a1 = 0
    a2 = 0
    enable = false
  end

  methods (Static)
    function out = passthrough()
      out = experiment.BiquadStage();
    end

    function out = from_struct(s)
      if isa(s, "experiment.BiquadStage")
        if ~isscalar(s)
          error("experiment:biquad:invalid", "BiquadStage must be scalar.");
        end
        out = s.normalize();
        out.validate();
        return;
      end
      if ~isstruct(s) || ~isscalar(s)
        error("experiment:biquad:invalid", ...
          "BiquadStage.from_struct accepts only a scalar struct or BiquadStage.");
      end
      out = experiment.BiquadStage();
      if isempty(s)
        return;
      end
      fields = fieldnames(s);
      unknown = setdiff(string(fields), ["b0", "b1", "b2", "a1", "a2", "enable"]);
      if ~isempty(unknown)
        error("experiment:biquad:invalid", ...
          "Unknown BiquadStage field(s): %s.", strjoin(unknown, ", "));
      end
      for k = 1:numel(fields)
        key = fields{k};
        out.(key) = s.(key);
      end
      out = out.normalize();
      out.validate();
    end
  end

  methods
    function out = normalize(obj)
      out = obj;
      out.b0 = normalize_coefficient(out.b0, "b0");
      out.b1 = normalize_coefficient(out.b1, "b1");
      out.b2 = normalize_coefficient(out.b2, "b2");
      out.a1 = normalize_coefficient(out.a1, "a1");
      out.a2 = normalize_coefficient(out.a2, "a2");
      out.enable = normalize_boolean(out.enable);
    end

    function validate(obj)
      normalize_coefficient(obj.b0, "b0");
      normalize_coefficient(obj.b1, "b1");
      normalize_coefficient(obj.b2, "b2");
      normalize_coefficient(obj.a1, "a1");
      normalize_coefficient(obj.a2, "a2");
      normalize_boolean(obj.enable);
    end

    function s = to_flat(obj, prefix)
      prefix = char(string(prefix));
      out = obj.normalize();
      out.validate();
      s = struct();
      s.([prefix 'b0']) = out.b0;
      s.([prefix 'b1']) = out.b1;
      s.([prefix 'b2']) = out.b2;
      s.([prefix 'a1']) = out.a1;
      s.([prefix 'a2']) = out.a2;
    end
  end
end

function value = normalize_coefficient(value, name)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(double(value)))
  error("experiment:biquad:invalid", ...
    "%s must be a finite real numeric scalar.", name);
end
value = double(value);
end

function value = normalize_boolean(value)
if islogical(value) && isscalar(value)
  return;
end
if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(double(value)) && any(double(value) == [0, 1]))
  error("experiment:biquad:invalid", ...
    "enable must be a logical scalar or numeric 0/1.");
end
value = logical(value);
end
