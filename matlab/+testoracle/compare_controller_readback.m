function report = compare_controller_readback(controller, actual, varargin)
% compare_controller_readback  Verify padded SOS bank and revision contract.
p = inputParser;
p.addParameter("eps_factor", 16, @is_positive_scalar);
p.parse(varargin{:});
controller = experiment.ControllerConfig.from_struct(controller);
payload = controller.to_ads_payload();
required = ["coefficients", "section_count", "apply_revision", ...
  "applied_revision", "processed_revision", "parameter_error_code"];
if ~isstruct(actual) || ~isscalar(actual) || any(~isfield(actual, required))
  error("testoracle:controller:invalidReadback", ...
    "Controller readback is missing required fields.");
end
expected_coefficients = double(payload.coefficients(:));
actual_coefficients = double(actual.coefficients(:));
coefficient_shape_match = isequal(size(expected_coefficients), size(actual_coefficients));
if coefficient_shape_match
  scale = max(1, max(abs([expected_coefficients; actual_coefficients])));
  coefficient_tolerance = double(p.Results.eps_factor) * eps(scale);
  coefficient_error = max(abs(actual_coefficients - expected_coefficients), [], "omitnan");
  coefficients_match = isfinite(coefficient_error) && ...
    coefficient_error <= coefficient_tolerance;
else
  coefficient_tolerance = 0;
  coefficient_error = Inf;
  coefficients_match = false;
end
section_match = uint32(actual.section_count) == uint32(payload.section_count);
apply_revision = uint32(actual.apply_revision);
revisions_match = apply_revision == uint32(actual.applied_revision) && ...
  apply_revision == uint32(actual.processed_revision);
parameter_ok = uint32(actual.parameter_error_code) == 0;
report = struct( ...
  "pass", coefficients_match && section_match && revisions_match && parameter_ok, ...
  "coefficients_match", coefficients_match, ...
  "coefficient_shape_match", coefficient_shape_match, ...
  "coefficient_max_abs_error", coefficient_error, ...
  "coefficient_tolerance", coefficient_tolerance, ...
  "section_count_exact_match", section_match, ...
  "revision_match", revisions_match, ...
  "parameter_error_zero", parameter_ok);
end

function tf = is_positive_scalar(value)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
  isfinite(value) && value > 0;
end
