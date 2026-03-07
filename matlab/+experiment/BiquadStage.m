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
      out = experiment.BiquadStage();
      if isempty(s)
        return;
      end
      fields = fieldnames(s);
      for k = 1:numel(fields)
        key = fields{k};
        if isprop(out, key)
          out.(key) = s.(key);
        end
      end
      out = out.normalize();
    end
  end

  methods
    function out = normalize(obj)
      out = obj;
      out.b0 = double(out.b0);
      out.b1 = double(out.b1);
      out.b2 = double(out.b2);
      out.a1 = double(out.a1);
      out.a2 = double(out.a2);
      out.enable = logical(out.enable);
    end

    function s = to_flat(obj, prefix)
      prefix = char(string(prefix));
      out = obj.normalize();
      s = struct();
      s.([prefix 'b0']) = out.b0;
      s.([prefix 'b1']) = out.b1;
      s.([prefix 'b2']) = out.b2;
      s.([prefix 'a1']) = out.a1;
      s.([prefix 'a2']) = out.a2;
    end
  end
end
