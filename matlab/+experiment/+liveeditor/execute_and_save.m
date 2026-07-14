function execution_time = execute_and_save(file_path)
%EXECUTE_AND_SAVE Execute one rich Live Script and persist its fresh outputs.
arguments
  file_path {mustBeTextScalar}
end

execution_time = matlab.internal.liveeditor.executeAndSave(char(file_path));
end
