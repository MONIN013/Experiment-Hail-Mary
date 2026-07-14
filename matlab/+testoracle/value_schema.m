function schema = value_schema(value)
% value_schema  Canonical shape/type description for a saved artifact.
if istable(value)
  names = string(value.Properties.VariableNames);
  variables = repmat(struct("name", "", "schema", struct()), numel(names), 1);
  for index = 1:numel(names)
    variables(index).name = names(index);
    variables(index).schema = testoracle.value_schema(value.(char(names(index))));
  end
  schema = struct("class", "table", "size", double(size(value)), ...
    "variables", variables);
  return;
end
if isstruct(value)
  names = sort(string(fieldnames(value)));
  fields = repmat(struct("name", "", "schema", struct()), numel(names), 1);
  if isscalar(value)
    for index = 1:numel(names)
      fields(index).name = names(index);
      fields(index).schema = testoracle.value_schema(value.(char(names(index))));
    end
  else
    for index = 1:numel(names)
      fields(index).name = names(index);
      fields(index).schema = struct("class", "per-element", "size", double(size(value)));
    end
  end
  schema = struct("class", "struct", "size", double(size(value)), "fields", fields);
  return;
end
if iscell(value)
  element_schema = strings(size(value));
  for index = 1:numel(value)
    element_schema(index) = testoracle.canonical_digest( ...
      testoracle.value_schema(value{index}));
  end
  schema = struct("class", "cell", "size", double(size(value)), ...
    "element_schema_digests", element_schema);
  return;
end
schema = struct("class", string(class(value)), "size", double(size(value)), ...
  "complex", ~isreal(value));
end
