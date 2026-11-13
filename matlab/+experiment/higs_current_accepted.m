function accepted = higs_current_accepted(metrics, limit_a)
% Post-trial criterion only; not a substitute for drive overcurrent protection.
% Fail closed for missing, empty, nonfinite, negative or nonscalar peaks.
accepted = false;
if ~(isnumeric(limit_a) && isreal(limit_a) && isscalar(limit_a) && ...
    isfinite(limit_a) && limit_a > 0 && isstruct(metrics) && isscalar(metrics))
  return;
end
fields = ["current_peak_a", "command_peak_a", "measured_current_peak_a"];
if any(~isfield(metrics, fields)), return; end
for name = fields
  value = metrics.(name);
  if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
      isfinite(value) && value >= 0 && value < limit_a)
    return;
  end
end
accepted = true;
end
