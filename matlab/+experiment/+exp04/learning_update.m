function [next_ff, limit_check] = learning_update(current_ff, error_signal, learning_filters, varargin)
% learning_update  inverse learning、Q filtering、端点処理を一度に適用する。

  p = inputParser;
  p.addParameter("alpha", 0.6, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0 && x <= 1);
  p.addParameter("Npad", 100, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && fix(x) == x);
  p.addParameter("transient_samples", 200, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && fix(x) == x);
  p.addParameter("max_input", 1.6, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
  p.parse(varargin{:});
  required_fields = ["Linv", "Qnum", "Qden", "error_quantum_rad"];
  if ~isstruct(learning_filters) || ~all(isfield(learning_filters, required_fields))
    error("experiment:exp04:invalidLearningInput", ...
      "learning_filters must contain Linv, Qnum, Qden, and error_quantum_rad.");
  end

  current_ff = double(current_ff(:));
  error_signal = double(error_signal(:));
  if numel(current_ff) ~= numel(error_signal) || ...
      any(~isfinite([current_ff; error_signal]))
    error("experiment:exp04:invalidLearningInput", ...
      "current_ff and error_signal must be equal-length finite vectors.");
  end
  error_quantum_rad = double(learning_filters.error_quantum_rad);
  if ~(isreal(error_quantum_rad) && isscalar(error_quantum_rad) && ...
      isfinite(error_quantum_rad) && error_quantum_rad > 0)
    error("experiment:exp04:invalidLearningInput", ...
      "learning_filters.error_quantum_rad must be a positive scalar.");
  end
  error_signal = round(error_signal / error_quantum_rad) * error_quantum_rad;
  learned = current_ff + p.Results.alpha * experiment.exp04.srinv( ...
    learning_filters.Linv, error_signal, p.Results.Npad);
  filtered = experiment.exp04.filtfilt_clean( ...
    learning_filters.Qnum, learning_filters.Qden, learned, p.Results.Npad);
  next_ff = experiment.exp04.splice_transients(filtered, p.Results.transient_samples);
  limit_check = experiment.exp04.check_input_limit(next_ff, p.Results.max_input);
end
