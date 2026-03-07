classdef PlantConfig
  properties
    m = 0.01
    d = 0.1
    rated_current = 1.2
    max_permille = 0
    tau_limit = 5.0
    vel_limit = 100.0
  end

  methods (Static)
    function out = from_struct(s)
      out = experiment.PlantConfig();
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
      out.m = double(out.m);
      out.d = double(out.d);
      out.rated_current = double(out.rated_current);
      out.max_permille = double(out.max_permille);
      out.tau_limit = double(out.tau_limit);
      out.vel_limit = double(out.vel_limit);
    end

    function s = to_struct(obj)
      out = obj.normalize();
      s = struct( ...
        "m", out.m, ...
        "d", out.d, ...
        "rated_current", out.rated_current, ...
        "max_permille", out.max_permille, ...
        "tau_limit", out.tau_limit, ...
        "vel_limit", out.vel_limit);
    end
  end
end
