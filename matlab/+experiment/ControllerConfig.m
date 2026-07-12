classdef ControllerConfig
  properties
    pid experiment.BiquadStage = experiment.BiquadStage()
    lead experiment.BiquadStage = experiment.BiquadStage()
    notch experiment.BiquadStage = experiment.BiquadStage()
    reso experiment.BiquadStage = experiment.BiquadStage()
  end

  methods (Static)
    function out = p_only(Kp)
      validate_gain(Kp);
      out = experiment.ControllerConfig();
      out.pid = experiment.BiquadStage.from_struct(struct( ...
        "b0", double(Kp), "enable", true));
      out.lead = experiment.BiquadStage.passthrough();
      out.notch = experiment.BiquadStage.passthrough();
      out.reso = experiment.BiquadStage.passthrough();
    end

    function out = from_flat_struct(s)
      if isa(s, "experiment.ControllerConfig")
        if ~isscalar(s)
          error("experiment:controller:invalid", "ControllerConfig must be scalar.");
        end
        out = s.normalize();
        out.validate();
        return;
      end
      if ~isstruct(s) || ~isscalar(s)
        error("experiment:controller:invalid", ...
          "ControllerConfig.from_flat_struct accepts only a scalar struct or ControllerConfig.");
      end
      out = experiment.ControllerConfig();
      if isempty(s)
        return;
      end
      actual = string(fieldnames(s));
      unknown = setdiff(actual, flat_field_names());
      if ~isempty(unknown)
        error("experiment:controller:invalid", ...
          "Unknown ControllerConfig field(s): %s.", strjoin(unknown, ", "));
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
      out.validate();
    end
  end

  methods
    function out = normalize(obj)
      out = obj;
      out.pid = experiment.BiquadStage.from_struct(out.pid);
      out.lead = experiment.BiquadStage.from_struct(out.lead);
      out.notch = experiment.BiquadStage.from_struct(out.notch);
      out.reso = experiment.BiquadStage.from_struct(out.reso);
    end

    function validate(obj)
      obj.pid.validate();
      obj.lead.validate();
      obj.notch.validate();
      obj.reso.validate();
    end

    function s = to_flat_struct(obj)
      out = obj.normalize();
      out.validate();
      s = struct();
      s = copy_fields(s, out.pid.to_flat("pid_"));
      s = copy_fields(s, out.lead.to_flat("lead_"));
      s = copy_fields(s, out.notch.to_flat("notch_"));
      s = copy_fields(s, out.reso.to_flat("reso_"));
      s.enable_pid = logical(out.pid.enable);
      s.enable_lead = logical(out.lead.enable);
      s.enable_notch = logical(out.notch.enable);
      s.enable_reso = logical(out.reso.enable);
    end
  end
end

function names = flat_field_names()
names = ["pid_b0";"pid_b1";"pid_b2";"pid_a1";"pid_a2"; ...
  "lead_b0";"lead_b1";"lead_b2";"lead_a1";"lead_a2"; ...
  "notch_b0";"notch_b1";"notch_b2";"notch_a1";"notch_a2"; ...
  "reso_b0";"reso_b1";"reso_b2";"reso_a1";"reso_a2"; ...
  "enable_pid";"enable_lead";"enable_notch";"enable_reso"];
end

function validate_gain(value)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(double(value)))
  error("experiment:controller:invalid", ...
    "Kp must be a finite real numeric scalar.");
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
