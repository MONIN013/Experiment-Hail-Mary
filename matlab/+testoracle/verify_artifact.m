function report = verify_artifact(actual_value, contract, varargin)
% verify_artifact  Validate artifact schema and frozen expected values.
p = inputParser;
p.addParameter("units", repmat(struct("path", "", "unit", ""), 0, 1), ...
  @isstruct);
p.parse(varargin{:});
required = ["schema", "units", "required_fields", "absolute_tolerance", ...
  "expected_value", "canonical_value_digest"];
if ~isstruct(contract) || ~isscalar(contract) || any(~isfield(contract, required))
  error("testoracle:artifact:invalidContract", ...
    "Artifact contract is missing required fields.");
end

schema = testoracle.value_schema(actual_value);
schema_match = isequaln(schema, contract.schema);
actual_units = p.Results.units;
actual_unit_paths = reshape(string({actual_units.path}), [], 1);
actual_unit_labels = reshape(string({actual_units.unit}), [], 1);
numeric_paths = testoracle.artifact_numeric_paths(actual_value);
valid_actual_units = (isempty(actual_units) || ...
  all(isfield(actual_units, ["path", "unit"]))) && ...
  numel(unique(actual_unit_paths)) == numel(actual_unit_paths) && ...
  all(strlength(actual_unit_labels) > 0) && ...
  isequal(sort(actual_unit_paths), sort(numeric_paths));
units_match = valid_actual_units && isequaln(actual_units, contract.units);
missing = missing_paths(actual_value, string(contract.required_fields));
[value_match, failures, canonicalized] = compare_value( ...
  actual_value, contract.expected_value, contract.absolute_tolerance, "root");
canonical_digest = testoracle.canonical_digest(canonicalized);
digest_match = canonical_digest == string(contract.canonical_value_digest);

report = struct( ...
  "pass", schema_match && units_match && isempty(missing) && ...
    value_match && digest_match, ...
  "schema_match", schema_match, ...
  "units_match", units_match, "actual_units", actual_units, ...
  "missing_required_fields", missing, ...
  "value_match", value_match, ...
  "value_failures", failures, ...
  "canonical_value_digest", canonical_digest, ...
  "digest_match", digest_match);
end

function missing = missing_paths(value, paths)
missing = strings(0, 1);
for index = 1:numel(paths)
  path = paths(index);
  if strlength(path) == 0, continue; end
  parts = split(path, ".");
  cursor = value;
  exists = true;
  for part = parts(:)'
    if isstruct(cursor) && isscalar(cursor) && isfield(cursor, char(part))
      cursor = cursor.(char(part));
    else
      exists = false;
      break;
    end
  end
  if ~exists, missing(end + 1, 1) = path; end %#ok<AGROW>
end
end

function [pass, failures, canonicalized] = compare_value(actual, expected, tolerance, path)
failures = strings(0, 1);
canonicalized = actual;
if isnumeric(expected) || islogical(expected)
  if ~isequal(size(actual), size(expected)) || ~isnumeric(actual) && ~islogical(actual)
    pass = false;
    failures = path + " shape/type mismatch";
    return;
  end
  limit = resolve_tolerance(tolerance, path);
  actual_numeric = double(actual);
  expected_numeric = double(expected);
  paired_nan = isnan(actual_numeric) & isnan(expected_numeric);
  unpaired_nan = xor(isnan(actual_numeric), isnan(expected_numeric));
  paired_inf = isinf(actual_numeric) & isinf(expected_numeric) & ...
    sign(actual_numeric) == sign(expected_numeric);
  invalid_inf = xor(isinf(actual_numeric), isinf(expected_numeric)) | ...
    (isinf(actual_numeric) & isinf(expected_numeric) & ...
      sign(actual_numeric) ~= sign(expected_numeric));
  delta = abs(actual_numeric - expected_numeric);
  delta(paired_nan | paired_inf) = 0;
  pass = ~any(unpaired_nan(:)) && ~any(invalid_inf(:)) && ...
    all(delta(:) <= limit) && ...
    all(isfinite(delta(:)));
  if pass
    canonicalized = expected;
  else
    failures = path + " exceeds absolute tolerance " + limit;
  end
  return;
end
if isstruct(expected)
  pass = isstruct(actual) && isequal(size(actual), size(expected)) && ...
    isequal(sort(string(fieldnames(actual))), sort(string(fieldnames(expected))));
  if ~pass
    failures = path + " struct mismatch";
    return;
  end
  canonicalized = actual;
  names = string(fieldnames(expected));
  for element = 1:numel(expected)
    for name = names(:)'
      [item_pass, item_failures, item_value] = compare_value( ...
        actual(element).(char(name)), expected(element).(char(name)), ...
        tolerance, path + "." + name);
      pass = pass && item_pass;
      failures = [failures; item_failures]; %#ok<AGROW>
      canonicalized(element).(char(name)) = item_value;
    end
  end
  return;
end
if iscell(expected)
  pass = iscell(actual) && isequal(size(actual), size(expected));
  if ~pass
    failures = path + " cell mismatch";
    return;
  end
  for index = 1:numel(expected)
    [item_pass, item_failures, canonicalized{index}] = compare_value( ...
      actual{index}, expected{index}, tolerance, path + "{" + index + "}");
    pass = pass && item_pass;
    failures = [failures; item_failures]; %#ok<AGROW>
  end
  return;
end
pass = isequaln(actual, expected);
if pass
  canonicalized = expected;
else
  failures = path + " value mismatch";
end
end

function value = resolve_tolerance(tolerance, path)
value = 0;
if isempty(fieldnames(tolerance)), return; end
key = matlab.lang.makeValidName(erase(path, "root."));
if isfield(tolerance, key)
  value = double(tolerance.(key));
elseif isfield(tolerance, "default")
  value = double(tolerance.default);
end
if ~(isscalar(value) && isfinite(value) && value >= 0)
  error("testoracle:artifact:invalidTolerance", ...
    "Tolerance for %s must be a finite nonnegative scalar.", path);
end
end
