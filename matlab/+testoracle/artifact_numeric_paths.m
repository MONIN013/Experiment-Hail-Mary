function paths = artifact_numeric_paths(value)
% artifact_numeric_paths  Enumerate every numeric/logical artifact leaf.
paths = collect_paths(value, "root");
paths = sort(paths(:));
end

function paths = collect_paths(value, path)
paths = strings(0, 1);
if isnumeric(value) || islogical(value)
  paths = path;
  return;
end
if isstruct(value)
  names = sort(string(fieldnames(value)));
  for element = 1:numel(value)
    element_path = path;
    if numel(value) > 1, element_path = path + "(" + element + ")"; end
    for name = names(:)'
      paths = [paths; collect_paths(value(element).(char(name)), ...
        element_path + "." + name)]; %#ok<AGROW>
    end
  end
elseif iscell(value)
  for index = 1:numel(value)
    paths = [paths; collect_paths(value{index}, ...
      path + "{" + index + "}")]; %#ok<AGROW>
  end
end
end
