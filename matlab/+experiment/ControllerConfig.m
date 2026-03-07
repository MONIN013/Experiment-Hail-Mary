classdef ControllerConfig
  properties
    pid experiment.BiquadStage = experiment.BiquadStage()
    lead experiment.BiquadStage = experiment.BiquadStage()
    notch experiment.BiquadStage = experiment.BiquadStage()
    reso experiment.BiquadStage = experiment.BiquadStage()
  end

  methods (Static)
    function out = p_only(Kp)
      out = experiment.ControllerConfig();
      out.pid = experiment.BiquadStage.from_struct(struct( ...
        "b0", double(Kp), "enable", true));
      out.lead = experiment.BiquadStage.passthrough();
      out.notch = experiment.BiquadStage.passthrough();
      out.reso = experiment.BiquadStage.passthrough();
    end

    function out = from_flat_struct(s)
      out = experiment.ControllerConfig();
      if isempty(s)
        return;
      end
      out.pid = experiment.BiquadStage.from_struct(struct( ...
        "b0", get_field_or(s, "pid_b0", 0), ...
        "b1", get_field_or(s, "pid_b1", 0), ...
        "b2", get_field_or(s, "pid_b2", 0), ...
        "a1", get_field_or(s, "pid_a1", 0), ...
        "a2", get_field_or(s, "pid_a2", 0), ...
        "enable", get_field_or(s, "enable_pid", true)));
      out.lead = experiment.BiquadStage.from_struct(struct( ...
        "b0", get_field_or(s, "lead_b0", 1), ...
        "b1", get_field_or(s, "lead_b1", 0), ...
        "b2", get_field_or(s, "lead_b2", 0), ...
        "a1", get_field_or(s, "lead_a1", 0), ...
        "a2", get_field_or(s, "lead_a2", 0), ...
        "enable", get_field_or(s, "enable_lead", false)));
      out.notch = experiment.BiquadStage.from_struct(struct( ...
        "b0", get_field_or(s, "notch_b0", 1), ...
        "b1", get_field_or(s, "notch_b1", 0), ...
        "b2", get_field_or(s, "notch_b2", 0), ...
        "a1", get_field_or(s, "notch_a1", 0), ...
        "a2", get_field_or(s, "notch_a2", 0), ...
        "enable", get_field_or(s, "enable_notch", false)));
      out.reso = experiment.BiquadStage.from_struct(struct( ...
        "b0", get_field_or(s, "reso_b0", 1), ...
        "b1", get_field_or(s, "reso_b1", 0), ...
        "b2", get_field_or(s, "reso_b2", 0), ...
        "a1", get_field_or(s, "reso_a1", 0), ...
        "a2", get_field_or(s, "reso_a2", 0), ...
        "enable", get_field_or(s, "enable_reso", false)));
    end
  end

  methods
    function s = to_flat_struct(obj)
      s = struct();
      s = copy_fields(s, obj.pid.to_flat("pid_"));
      s = copy_fields(s, obj.lead.to_flat("lead_"));
      s = copy_fields(s, obj.notch.to_flat("notch_"));
      s = copy_fields(s, obj.reso.to_flat("reso_"));
      s.enable_pid = logical(obj.pid.enable);
      s.enable_lead = logical(obj.lead.enable);
      s.enable_notch = logical(obj.notch.enable);
      s.enable_reso = logical(obj.reso.enable);
    end
  end
end

function value = get_field_or(s, name, default_value)
if isstruct(s) && isfield(s, name)
  value = s.(name);
elseif isobject(s) && isprop(s, name)
  value = s.(name);
else
  value = default_value;
end
end

function out = copy_fields(out, src)
fields = fieldnames(src);
for k = 1:numel(fields)
  out.(fields{k}) = src.(fields{k});
end
end
