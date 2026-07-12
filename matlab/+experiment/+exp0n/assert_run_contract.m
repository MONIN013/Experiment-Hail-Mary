function assert_run_contract(run_out)
% assert_run_contract  Enforce the shared runtime acceptance contract.

if ~isstruct(run_out) || ~isfield(run_out, "metrics") || ...
    ~isstruct(run_out.metrics) || ~isfield(run_out.metrics, "acceptance")
  error("experiment:exp0n:runtimeContractMismatch", ...
    "Run output does not contain metrics.acceptance.");
end

acceptance = run_out.metrics.acceptance;
required = [ ...
  "input_waveform_exact_match"
  "ff_waveform_exact_match"
  "dist_waveform_exact_match"
  "torque_sum_exact_match"
  "seq_no_gap"
  "total_sample_count_exact_match"];
missing_fields = required(~isfield(acceptance, required));
if ~isempty(missing_fields)
  error("experiment:exp0n:runtimeContractMismatch", ...
    "Runtime acceptance is missing field(s): %s.", strjoin(missing_fields, ", "));
end

values = arrayfun(@(name) logical(acceptance.(char(name))), required);
if ~all(values)
  failed = required(~values);
  error("experiment:exp0n:runtimeContractMismatch", ...
    "Runtime contract validation failed: %s.", strjoin(failed, ", "));
end
end
