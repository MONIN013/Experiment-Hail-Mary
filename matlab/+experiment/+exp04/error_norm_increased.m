function out = error_norm_increased(previous_norm, current_norm)
% error_norm_increased  trial error norm の悪化を副作用なしで判定する。

  values = double([previous_norm, current_norm]);
  if any(~isfinite(values)) || any(values < 0)
    error("experiment:exp04:invalidErrorNorm", ...
      "error norms must be finite nonnegative scalars.");
  end
  out = logical(values(2) > values(1));
end
