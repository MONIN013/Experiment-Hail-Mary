function report = assert_valid(file_path, options)
%ASSERT_VALID Inspect a rich Live Script and throw one concise error on failure.
arguments
  file_path {mustBeTextScalar}
  options.require_outputs (1, 1) logical = true
end

report = experiment.liveeditor.inspect( ...
  file_path, "require_outputs", options.require_outputs);
if report.valid
  return;
end

message = "Rich Live Script validation failed for " + report.file_path + ":" + ...
  newline + "- " + join(report.issues, newline + "- ");
error("experiment:liveeditor:InvalidStructure", "%s", message);
end
