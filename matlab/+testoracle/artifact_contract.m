function contract = artifact_contract(expected_value, varargin)
% artifact_contract  Freeze artifact schema, units, and canonical value.
p = inputParser;
p.addParameter("units", repmat(struct("path", "", "unit", ""), 0, 1), ...
  @isstruct);
p.addParameter("absolute_tolerance", struct(), @isstruct);
p.addParameter("required_fields", strings(0, 1), ...
  @(x) ischar(x) || isstring(x) || iscellstr(x));
p.parse(varargin{:});
units = validate_units(expected_value, p.Results.units);

contract = struct( ...
  "schema", testoracle.value_schema(expected_value), ...
  "units", units, ...
  "required_fields", string(p.Results.required_fields(:)), ...
  "absolute_tolerance", p.Results.absolute_tolerance, ...
  "expected_value", expected_value, ...
  "canonical_value_digest", testoracle.canonical_digest(expected_value));
end

function units = validate_units(value, units)
required = ["path", "unit"];
if ~isempty(units) && any(~isfield(units, required))
  error("testoracle:artifact:invalidUnits", ...
    "Unit map entries require path and unit fields.");
end
paths = reshape(string({units.path}), [], 1);
labels = reshape(string({units.unit}), [], 1);
expected_paths = testoracle.artifact_numeric_paths(value);
if numel(unique(paths)) ~= numel(paths) || any(strlength(labels) == 0) || ...
    ~isequal(sort(paths), sort(expected_paths))
  error("testoracle:artifact:invalidUnits", ...
    "Unit map must cover every numeric/logical artifact field exactly once.");
end
if ~isempty(units)
  [~, order] = sort(paths);
  units = units(order);
end
end
