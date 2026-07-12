function out = check_input_limit(signal, max_input)
% check_input_limit  次 trial の FF 入力上限を副作用なしで判定する。

  signal = double(signal(:));
  if any(~isfinite(signal)) || ~(isnumeric(max_input) && isreal(max_input) && ...
      isscalar(max_input) && isfinite(max_input) && max_input > 0)
    error("experiment:exp04:invalidLearningInput", ...
      "signal must be finite and max_input must be positive.");
  end
  max_abs_input = max(abs(signal));
  ok = max_abs_input <= max_input;
  if ok
    reason = "ok";
  else
    reason = "input_limit";
  end
  out = struct( ...
    "ok", logical(ok), ...
    "reason", reason, ...
    "max_abs_input", double(max_abs_input), ...
    "limit", double(max_input));
end
