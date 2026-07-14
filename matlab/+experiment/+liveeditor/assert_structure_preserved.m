function assert_structure_preserved(before, after, file_path)
%ASSERT_STRUCTURE_PRESERVED Guard author text and section boundaries.
arguments
  before (1, 1) struct
  after (1, 1) struct
  file_path {mustBeTextScalar}
end

same_text = isequal(before.text_lines, after.text_lines) && ...
  isequal(before.text_line_numbers, after.text_line_numbers);
same_sections = isequal(before.section_lines, after.section_lines) && ...
  isequal(before.section_line_numbers, after.section_line_numbers);
if same_text && same_sections
  return;
end

error("experiment:liveeditor:AuthoredStructureChanged", ...
  "executeAndSave changed %%[text] content or section boundaries in %s.", ...
  string(file_path));
end
