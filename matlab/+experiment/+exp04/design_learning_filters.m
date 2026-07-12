function out = design_learning_filters(Pd, Pdn, Kd, Ts, alpha, q_cutoff_hz, noQ)
% design_learning_filters  ILC の L inverse、Q filter、収束条件を設計する。

  require_scalar(alpha, "alpha", @(x) x > 0 && x <= 1);
  require_scalar(q_cutoff_hz, "q_cutoff_hz", @(x) x > 0);
  require_scalar(Ts, "Ts", @(x) x > 0);
  if ~(islogical(noQ) && isscalar(noQ))
    error("experiment:exp04:invalidFilterConfig", "noQ must be a logical scalar.");
  end

  Linv = feedback(Pdn, Kd);
  measured_process_sensitivity = feedback(Pd, Kd);
  cutoff_rad_s = 2*pi*double(q_cutoff_hz);
  Q_cont = tf(cutoff_rad_s^2, [1 sqrt(2)*cutoff_rad_s cutoff_rad_s^2]);
  Q = c2d(Q_cont, double(Ts), "tustin");
  if noQ
    Q = tf(1, 1, double(Ts));
  end
  [Qnum, Qden] = tfdata(Q, "v");

  convergence_condition = Q^2 * (1 - alpha*measured_process_sensitivity/Linv);
  if isa(convergence_condition, "frd")
    convergence_response = convergence_condition.ResponseData;
    convergence_frequency_hz = convergence_condition.Frequency(:);
    if ~strcmpi(string(convergence_condition.FrequencyUnit), "Hz")
      convergence_frequency_hz = convergence_frequency_hz / (2*pi);
    end
  else
    convergence_frequency_hz = logspace(0, log10(1/(2*Ts)), 2000)';
    convergence_response = freqresp(convergence_condition, 2*pi*convergence_frequency_hz);
  end
  convergence_mag = squeeze(abs(convergence_response));
  valid = isfinite(convergence_mag(:));
  if ~any(valid)
    error("experiment:exp04:invalidConvergenceResult", ...
      "ILC convergence response contains no finite values.");
  end
  max_convergence_gain = max(convergence_mag(valid));
  if max_convergence_gain >= 1
    error("experiment:exp04:convergenceConditionFailed", ...
      "ILC convergence peak %.6g must be below 1. Reduce alpha or q_cutoff_hz.", ...
      max_convergence_gain);
  end

  out = struct( ...
    "Linv", Linv, ...
    "measured_process_sensitivity", measured_process_sensitivity, ...
    "Q", Q, ...
    "Qnum", Qnum, ...
    "Qden", Qden, ...
    "convergence_condition", convergence_condition, ...
    "convergence_frequency_hz", convergence_frequency_hz, ...
    "max_convergence_gain", double(max_convergence_gain));
end

function require_scalar(value, name, predicate)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(double(value)) && ...
    predicate(double(value)))
  error("experiment:exp04:invalidFilterConfig", "%s is invalid.", name);
end
end
