function report = assert_refreshable(file_path)
% assert_refreshable  Validate rich structure before outputs are regenerated.
%
% Source/output ID mismatches are expected after executable code changes and
% are repaired by executeAndSave. All other rich-file corruption remains a
% hard pre-execution failure; the refreshed target is checked strictly.
arguments
  file_path {mustBeTextScalar}
end

report = experiment.liveeditor.inspect(file_path);
if report.valid
  return;
end
allowed_prefixes = [ ...
  "Output references without appendix definitions:"
  "Appendix outputs without source references:"];
allowed = false(size(report.issues));
for prefix = allowed_prefixes'
  allowed = allowed | startsWith(report.issues, prefix);
end
blocking = report.issues(~allowed);
if isempty(blocking)
  return;
end

message = "Rich Live Script is not safely refreshable for " + ...
  report.file_path + ":" + newline + "- " + join(blocking, newline + "- ");
error("experiment:liveeditor:InvalidRefreshSource", "%s", message);
end
