function out = splice_transients(signal, transient_samples)
% splice_transients  ILC filter の端点過渡を隣接する有効値で置換する。

  signal = double(signal(:));
  if any(~isfinite(signal))
    error("experiment:exp04:invalidLearningInput", "signal must be finite.");
  end
  if ~(isnumeric(transient_samples) && isscalar(transient_samples) && ...
      isfinite(transient_samples) && transient_samples >= 0 && fix(transient_samples) == transient_samples)
    error("experiment:exp04:invalidLearningInput", ...
      "transient_samples must be a nonnegative integer.");
  end
  transient_samples = double(transient_samples);
  if transient_samples == 0
    out = signal;
    return;
  end
  if numel(signal) <= 2*transient_samples
    error("experiment:exp04:invalidLearningInput", ...
      "signal length must exceed twice transient_samples.");
  end
  first_valid = signal(transient_samples + 1);
  last_valid = signal(end - transient_samples);
  out = [ ...
    repmat(first_valid, transient_samples, 1); ...
    signal(transient_samples + 1:end - transient_samples); ...
    repmat(last_valid, transient_samples, 1)];
end
