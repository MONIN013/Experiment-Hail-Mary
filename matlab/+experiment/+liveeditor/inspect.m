function report = inspect(file_path, options)
%INSPECT Validate the embedded-output structure of a rich .m Live Script.
arguments
  file_path {mustBeTextScalar}
  options.require_outputs (1, 1) logical = true
end

file_path = string(file_path);
issues = strings(0, 1);
if ~isfile(file_path)
  report = empty_report(file_path, "File does not exist.");
  return;
end

raw = string(fileread(file_path));
lines = splitlines(raw);
trimmed_lines = strip(lines);

try
  is_live_code = matlab.desktop.editor.EditorUtils.isLiveCodeFile(char(file_path));
catch cause
  is_live_code = false;
  issues(end + 1, 1) = "Live Code recognition failed: " + string(cause.message);
end
if ~is_live_code
  issues(end + 1, 1) = "MATLAB does not recognize the file as rich Live Code.";
end

appendix_lines = find(startsWith(trimmed_lines, "%[appendix]"));
metadata_lines = find(trimmed_lines == "%[metadata:view]");
if numel(appendix_lines) ~= 1
  issues(end + 1, 1) = "Expected exactly one appendix marker.";
end
if numel(metadata_lines) ~= 1
  issues(end + 1, 1) = "Expected exactly one view metadata marker.";
end

if isempty(appendix_lines)
  source_lines = lines;
  appendix_start = numel(lines) + 1;
else
  appendix_start = appendix_lines(1);
  source_lines = lines(1:max(appendix_start - 1, 0));
end
source_text = join(source_lines, newline);

reference_ids = extract_ids(source_text, ...
  '%\[output:(?!group:)([A-Za-z0-9_-]+)\]');
group_ids = extract_ids(source_text, ...
  '%\[output:group:([A-Za-z0-9_-]+)\]');

definition_ids = strings(0, 1);
definition_json = strings(0, 1);
image_ids = strings(0, 1);
json_count = 0;
if appendix_start <= numel(lines)
  [definition_ids, definition_json, image_ids, json_count, parse_issues] = ...
    parse_appendix(lines, appendix_start);
  issues = [issues; parse_issues];
end

if options.require_outputs && isempty(definition_ids)
  issues(end + 1, 1) = "Expected at least one embedded output definition.";
end
if numel(unique(definition_ids)) ~= numel(definition_ids)
  issues(end + 1, 1) = "Embedded output definition IDs must be unique.";
end

unique_references = unique(reference_ids, "stable");
unique_definitions = unique(definition_ids, "stable");
duplicate_reference_ids = references_reused_across_sections(source_lines);
if ~isempty(duplicate_reference_ids)
  issues(end + 1, 1) = ...
    "Source output reference IDs must belong to exactly one Live section: " + ...
    join(duplicate_reference_ids, ", ");
end
nonempty_json = definition_json(strlength(definition_json) > 0);
if numel(unique(nonempty_json)) ~= numel(nonempty_json)
  issues(end + 1, 1) = "Appendix output JSON payloads must be unique.";
end
missing_definitions = setdiff(unique_references, unique_definitions, "stable");
unreferenced_definitions = setdiff(unique_definitions, unique_references, "stable");
if ~isempty(missing_definitions)
  issues(end + 1, 1) = "Output references without appendix definitions: " + ...
    join(missing_definitions, ", ");
end
if ~isempty(unreferenced_definitions)
  issues(end + 1, 1) = "Appendix outputs without source references: " + ...
    join(unreferenced_definitions, ", ");
end

section_lines = find(trimmed_lines(1:max(appendix_start - 1, 0)) == "%%");
text_lines = find(startsWith(trimmed_lines(1:max(appendix_start - 1, 0)), "%[text]"));
if isempty(section_lines)
  issues(end + 1, 1) = "No Live Script section markers were found.";
end
if isempty(text_lines)
  issues(end + 1, 1) = "No rich text markers were found.";
end

report = struct( ...
  "file_path", file_path, ...
  "valid", isempty(issues), ...
  "issues", issues, ...
  "is_live_code", is_live_code, ...
  "appendix_count", numel(appendix_lines), ...
  "metadata_count", numel(metadata_lines), ...
  "section_count", numel(section_lines), ...
  "text_count", numel(text_lines), ...
  "output_reference_ids", reference_ids, ...
  "output_definition_ids", definition_ids, ...
  "output_json", definition_json, ...
  "group_ids", group_ids, ...
  "image_output_ids", image_ids, ...
  "json_count", json_count);
end

function duplicate_ids = references_reused_across_sections(source_lines)
% Live Editor repeats one output ID on every contributing code line. That
% repetition is valid inside one section; reusing it in another section is
% a second logical source reference and breaks the source/appendix bijection.
duplicate_ids = strings(0, 1);
section_index = 0;
sections_by_id = containers.Map("KeyType", "char", "ValueType", "any");
for line_index = 1:numel(source_lines)
  line = source_lines(line_index);
  if strip(line) == "%%"
    section_index = section_index + 1;
  end
  tokens = regexp(char(line), ...
    '%\[output:(?!group:)([A-Za-z0-9_-]+)\]', "tokens");
  for token_index = 1:numel(tokens)
    output_id = string(tokens{token_index}{1});
    key = char(output_id);
    if isKey(sections_by_id, key)
      sections = sections_by_id(key);
    else
      sections = zeros(0, 1);
    end
    sections_by_id(key) = unique([sections; section_index], "stable");
  end
end
output_ids = string(keys(sections_by_id));
for key = output_ids(:)'
  if numel(sections_by_id(char(key))) > 1
    duplicate_ids(end + 1, 1) = key; %#ok<AGROW>
  end
end
duplicate_ids = sort(duplicate_ids);
end

function report = empty_report(file_path, issue)
report = struct( ...
  "file_path", file_path, ...
  "valid", false, ...
  "issues", string(issue), ...
  "is_live_code", false, ...
  "appendix_count", 0, ...
  "metadata_count", 0, ...
  "section_count", 0, ...
  "text_count", 0, ...
  "output_reference_ids", strings(0, 1), ...
  "output_definition_ids", strings(0, 1), ...
  "output_json", strings(0, 1), ...
  "group_ids", strings(0, 1), ...
  "image_output_ids", strings(0, 1), ...
  "json_count", 0);
end

function ids = extract_ids(text, expression)
tokens = regexp(char(text), expression, "tokens");
if isempty(tokens)
  ids = strings(0, 1);
  return;
end
ids = string(cellfun(@(token) token{1}, tokens, "UniformOutput", false));
ids = ids(:);
end

function [ids, json_text, image_ids, json_count, issues] = ...
    parse_appendix(lines, appendix_start)
ids = strings(0, 1);
json_text = strings(0, 1);
image_ids = strings(0, 1);
json_count = 0;
issues = strings(0, 1);

appendix_line = strip(lines(appendix_start));
appendix_json = extractAfter(appendix_line, "%[appendix]");
[appendix, appendix_issue] = decode_json(appendix_json, "appendix");
if appendix_issue ~= ""
  issues(end + 1, 1) = appendix_issue;
else
  json_count = json_count + 1;
  if ~isstruct(appendix) || ~isfield(appendix, "version") || ...
      string(appendix.version) ~= "1.0"
    issues(end + 1, 1) = "Appendix version must be 1.0.";
  end
end

for line_index = appendix_start + 1:numel(lines)
  marker = regexp(char(strip(lines(line_index))), ...
    '^%\[output:([A-Za-z0-9_-]+)\]$', "tokens", "once");
  if isempty(marker)
    continue;
  end

  output_id = string(marker{1});
  ids(end + 1, 1) = output_id; %#ok<AGROW>
  data_lines = block_data_lines(lines, line_index);
  if numel(data_lines) ~= 1
    issues(end + 1, 1) = "Output " + output_id + ...
      " must contain exactly one JSON data line."; %#ok<AGROW>
    json_text(end + 1, 1) = ""; %#ok<AGROW>
    continue;
  end

  data_line = strip(lines(data_lines));
  payload_text = strip(extractAfter(data_line, "%   data:"));
  json_text(end + 1, 1) = payload_text; %#ok<AGROW>
  [payload, payload_issue] = decode_json(payload_text, "output " + output_id);
  if payload_issue ~= ""
    issues(end + 1, 1) = payload_issue; %#ok<AGROW>
    continue;
  end
  json_count = json_count + 1;

  if ~isstruct(payload) || ~isfield(payload, "dataType") || ...
      ~isfield(payload, "outputData")
    issues(end + 1, 1) = "Output " + output_id + ...
      " must define dataType and outputData."; %#ok<AGROW>
    continue;
  end

  if string(payload.dataType) == "image"
    image_ids(end + 1, 1) = output_id; %#ok<AGROW>
    png_issue = validate_png(payload, output_id);
    if png_issue ~= ""
      issues(end + 1, 1) = png_issue; %#ok<AGROW>
    end
  end
end

metadata_lines = find(strip(lines) == "%[metadata:view]");
for metadata_line = reshape(metadata_lines, 1, [])
  data_lines = block_data_lines(lines, metadata_line);
  if numel(data_lines) ~= 1
    issues(end + 1, 1) = ...
      "View metadata must contain exactly one JSON data line."; %#ok<AGROW>
    continue;
  end
  metadata_json = strip(extractAfter(strip(lines(data_lines)), "%   data:"));
  [~, metadata_issue] = decode_json(metadata_json, "view metadata");
  if metadata_issue ~= ""
    issues(end + 1, 1) = metadata_issue; %#ok<AGROW>
  else
    json_count = json_count + 1;
  end
end
end

function data_lines = block_data_lines(lines, marker_line)
tail = strip(lines(marker_line + 1:end));
separator_offset = find(tail == "%---", 1, "first");
if isempty(separator_offset)
  block_end = numel(lines);
else
  block_end = marker_line + separator_offset - 1;
end
if block_end < marker_line + 1
  data_lines = zeros(0, 1);
  return;
end
candidate_lines = (marker_line + 1:block_end).';
is_data = startsWith(strip(lines(candidate_lines)), "%   data:");
data_lines = candidate_lines(is_data);
end

function [value, issue] = decode_json(text, label)
issue = "";
value = struct();
try
  value = jsondecode(char(text));
catch cause
  issue = "Invalid JSON for " + label + ": " + string(cause.message);
end
end

function issue = validate_png(payload, output_id)
issue = "";
if ~isfield(payload, "outputData") || ~isstruct(payload.outputData) || ...
    ~isfield(payload.outputData, "dataUri")
  issue = "Image output " + output_id + " has no data URI.";
  return;
end

data_uri = string(payload.outputData.dataUri);
prefix = "data:image/png;base64,";
if ~startsWith(data_uri, prefix)
  issue = "Image output " + output_id + " is not a PNG data URI.";
  return;
end

try
  bytes = matlab.net.base64decode(char(extractAfter(data_uri, prefix)));
catch cause
  issue = "Image output " + output_id + " has invalid base64: " + ...
    string(cause.message);
  return;
end
png_magic = uint8([137, 80, 78, 71, 13, 10, 26, 10]);
if numel(bytes) < numel(png_magic) || ...
    ~isequal(reshape(uint8(bytes(1:numel(png_magic))), 1, []), png_magic)
  issue = "Image output " + output_id + " does not have PNG magic bytes.";
end
end
