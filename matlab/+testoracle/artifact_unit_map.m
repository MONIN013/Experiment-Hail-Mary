function units = artifact_unit_map(~, value)
% artifact_unit_map  Semantic field-path units for a projected artifact.
[paths, values] = collect_values(value, "root");
units = repmat(struct("path", "", "unit", ""), numel(paths), 1);
for index = 1:numel(paths)
  units(index) = struct( ...
    "path", paths(index), "unit", infer_unit(paths(index), values{index}));
end
if ~isempty(units)
  [~, order] = sort(string({units.path}));
  units = units(order);
end
end

function [paths, values] = collect_values(value, path)
paths = strings(0, 1);
values = cell(0, 1);
if isnumeric(value) || islogical(value)
  paths = path;
  values = {value};
  return;
end
if isstruct(value)
  names = sort(string(fieldnames(value)));
  for element = 1:numel(value)
    element_path = path;
    if numel(value) > 1, element_path = path + "(" + element + ")"; end
    for name = names(:)'
      [nested_paths, nested_values] = collect_values( ...
        value(element).(char(name)), element_path + "." + name);
      paths = [paths; nested_paths]; %#ok<AGROW>
      values = [values; nested_values]; %#ok<AGROW>
    end
  end
elseif iscell(value)
  for index = 1:numel(value)
    [nested_paths, nested_values] = collect_values( ...
      value{index}, path + "{" + index + "}");
    paths = [paths; nested_paths]; %#ok<AGROW>
    values = [values; nested_values]; %#ok<AGROW>
  end
end
end

function unit = infer_unit(path, value)
if islogical(value), unit = "1"; return; end
normalized = lower(regexprep(path, "\\(\\d+\\)|\\{\\d+\\}", ""));
parts = split(normalized, ".");
leaf = erase(parts(end), "_");
if leaf == "tns"
  unit = "ns";
elseif contains(leaf, "controllergain200")
  unit = "A/rad";
elseif endsWith(leaf, "hz") || contains(leaf, "frequency")
  unit = "Hz";
elseif contains(leaf, "magnitudedb")
  unit = "dB";
elseif contains(leaf, "phasedeg")
  unit = "deg";
elseif any(leaf == ["t", "ts", "tend", "tcycle"]) || ...
    contains(leaf, "times")
  unit = "s";
elseif contains(leaf, "iae") || contains(leaf, "integralabsolute")
  unit = "rad*s";
elseif contains(leaf, "velocity")
  unit = "rad/s";
elseif contains(leaf, "position") || contains(leaf, "loadpos") || ...
    contains(leaf, "motorpos") || any(leaf == ["r", "y", "e"]) || ...
    contains(leaf, "quantumrad") || ...
    any(leaf == ["error", "refvalue", "enorm"]) || ...
    contains(leaf, "trackingerror") || ...
    contains(leaf, "errornorm") || contains(leaf, "errorpeak") || ...
    contains(leaf, "maxabserror") || contains(leaf, "finalerror") || ...
    contains(leaf, "overshootrad") || contains(leaf, "tailmean")
  unit = "rad";
elseif leaf == "kfa"
  unit = "A*s^2/rad";
elseif leaf == "kfv"
  unit = "A*s/rad";
elseif leaf == "kfc"
  unit = "A";
elseif contains(leaf, "current") || contains(leaf, "inputa") || ...
    contains(leaf, "maxabsinput") || ...
    (contains(leaf, "maxabs") && contains(leaf, "input")) || ...
    contains(leaf, "feedforward") || contains(leaf, "ff") || ...
    contains(leaf, "control") || contains(leaf, "distvalue") || ...
    any(leaf == ["input", "u", "f"])
  unit = "A";
elseif leaf == "jn"
  unit = "A*s^2/rad";
elseif leaf == "dn"
  unit = "A*s/rad";
elseif contains(leaf, "delay")
  unit = "sample";
elseif contains(leaf, "count") || contains(leaf, "trial") || ...
    contains(leaf, "sections") || any(leaf == ["seq", "completedtrials", ...
      "besttrial", "ndelay"])
  unit = "count";
elseif any(leaf == ["numerator", "denominator", "qnum", "qden"])
  unit = "coefficient";
elseif contains(leaf, "sensitivity") || leaf == "smax" || ...
    contains(leaf, "convergence") || ...
    contains(leaf, "ratio") || contains(leaf, "peak") || ...
    leaf == "overshoot" || contains(leaf, "ok") || ...
    contains(leaf, "exceeded")
  unit = "1";
else
  error("testoracle:artifact:unknownUnit", ...
    "No artifact unit is defined for numeric field %s.", path);
end
end
