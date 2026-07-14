function report = compare_parameter_readback(expected, actual, varargin)
% compare_parameter_readback  Verify VM plant and task period readback.
p = inputParser;
p.addParameter("eps_factor", 16, @is_positive_scalar);
p.parse(varargin{:});
expected = normalize_readback(expected);
actual = normalize_readback(actual);
[plant_pass, fields] = compare_struct( ...
  expected.plant, actual.plant, "plant", double(p.Results.eps_factor));
task_match = isequal(uint64(expected.taskDtNs), uint64(actual.taskDtNs));
report = struct( ...
  "pass", plant_pass && task_match, ...
  "plant_pass", plant_pass, ...
  "fields", fields, ...
  "task_dt_ns_exact_match", task_match, ...
  "expected_task_dt_ns", uint64(expected.taskDtNs), ...
  "actual_task_dt_ns", uint64(actual.taskDtNs));
end

function value = normalize_readback(value)
if isa(value, "virtualMotor.PlantConfig")
  value = struct("plant", value.to_struct(), "taskDtNs", uint64(125000));
elseif isstruct(value) && isfield(value, "requested")
  value = value.requested;
end
if ~isstruct(value) || ~isscalar(value) || ...
    ~all(isfield(value, ["plant", "taskDtNs"]))
  error("testoracle:parameter:invalidReadback", ...
    "Expected plant and taskDtNs fields.");
end
value.plant = virtualMotor.PlantConfig.from_struct(value.plant).to_struct();
end

function [pass, fields] = compare_struct(expected, actual, path, eps_factor)
names = sort(string(fieldnames(expected)));
if ~isstruct(actual) || ~isequal(names, sort(string(fieldnames(actual))))
  pass = false;
  fields = struct("path", path, "pass", false, "detail", "field mismatch");
  return;
end
fields = repmat(struct("path", "", "pass", false, "detail", ""), 0, 1);
pass = true;
for name = names(:)'
  lhs = expected.(char(name));
  rhs = actual.(char(name));
  item_path = path + "." + name;
  if isstruct(lhs)
    [item_pass, nested] = compare_struct(lhs, rhs, item_path, eps_factor);
    fields = [fields; nested]; %#ok<AGROW>
  elseif isinteger(lhs)
    item_pass = isequal(lhs, cast(rhs, "like", lhs));
    fields(end + 1, 1) = struct( ...
      "path", item_path, "pass", item_pass, "detail", "integer exact"); %#ok<AGROW>
  else
    scale = max([1, abs(double(lhs)), abs(double(rhs))]);
    tolerance = eps_factor * eps(scale);
    delta = abs(double(lhs) - double(rhs));
    item_pass = isfinite(delta) && delta <= tolerance;
    fields(end + 1, 1) = struct( ...
      "path", item_path, "pass", item_pass, ...
      "detail", sprintf("delta=%.17g tolerance=%.17g", delta, tolerance)); %#ok<AGROW>
  end
  pass = pass && item_pass;
end
end

function tf = is_positive_scalar(value)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
  isfinite(value) && value > 0;
end
