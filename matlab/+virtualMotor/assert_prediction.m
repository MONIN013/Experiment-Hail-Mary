function assert_prediction(metrics, label)
% assert_prediction  Raise a compact error when VM prediction comparison fails.
if nargin < 2
  label = "VirtualMotor run";
end
if isstruct(metrics) && isfield(metrics, "pass") && logical(metrics.pass)
  return;
end

failed = strings(0, 1);
if ~isstruct(metrics)
  failed = "invalid metrics";
elseif isfield(metrics, "signals")
  names = string(fieldnames(metrics.signals));
  for k = 1:numel(names)
    item = metrics.signals.(char(names(k)));
    if ~logical(item.pass)
      failed(end + 1, 1) = sprintf("%s(max=%g tol=%g)", ...
        names(k), item.max_abs_error, item.tolerance); %#ok<AGROW>
    end
  end
  if ~metrics.seq_exact_match, failed(end + 1, 1) = "seq"; end
  if ~metrics.timestamp_exact_match, failed(end + 1, 1) = "timestamp"; end
  if ~metrics.predicted_fault_free, failed(end + 1, 1) = "predicted fault"; end
  if ~metrics.predicted_position_unsaturated, failed(end + 1, 1) = "predicted position saturation"; end
else
  failed = "missing signal metrics";
end
error("virtualMotor:prediction:mismatch", ...
  "%s did not match the precomputed VirtualMotor response: %s.", ...
  string(label), strjoin(failed, ", "));
end
