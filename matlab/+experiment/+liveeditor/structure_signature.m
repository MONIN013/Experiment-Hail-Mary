function signature = structure_signature(file_path)
%STRUCTURE_SIGNATURE Capture author-owned rich text and section structure.
arguments
  file_path {mustBeTextScalar}
end

lines = splitlines(string(fileread(file_path)));
trimmed_lines = strip(lines);
appendix_line = find(startsWith(trimmed_lines, "%[appendix]"), 1, "first");
if isempty(appendix_line)
  source_end = numel(lines);
else
  source_end = appendix_line - 1;
end

source_lines = lines(1:max(source_end, 0));
source_trimmed = strip(source_lines);
text_indices = find(startsWith(source_trimmed, "%[text]"));
section_indices = find(source_trimmed == "%%");

signature = struct( ...
  "text_lines", source_lines(text_indices), ...
  "text_line_numbers", text_indices, ...
  "section_lines", source_lines(section_indices), ...
  "section_line_numbers", section_indices);
end
