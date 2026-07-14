function digest = canonical_digest(value)
% canonical_digest  Stable SHA-256 over supported MATLAB values.
%
% This serializer is deliberately independent of MAT-file headers and JSON
% whitespace.  Field names are sorted, array shapes and numeric classes are
% included, and numeric payloads are hashed in column-major order.

engine = java.security.MessageDigest.getInstance("SHA-256");
update_value(engine, value, "root");
bytes = typecast(engine.digest(), "uint8");
digest = lower(join(string(dec2hex(bytes, 2)), ""));
end

function update_value(engine, value, path)
if istable(value)
  update_text(engine, "table");
  update_shape(engine, size(value));
  names = string(value.Properties.VariableNames);
  update_value(engine, names, path + ".VariableNames");
  update_value(engine, string(value.Properties.RowNames), path + ".RowNames");
  for index = 1:numel(names)
    name = names(index);
    update_text(engine, name);
    update_value(engine, value.(char(name)), path + "." + name);
  end
  return;
end
if isstruct(value)
  update_text(engine, "struct");
  update_shape(engine, size(value));
  names = sort(string(fieldnames(value)));
  update_value(engine, names, path + ".fieldnames");
  for element = 1:numel(value)
    for index = 1:numel(names)
      name = names(index);
      update_value(engine, value(element).(char(name)), ...
        path + "." + name + "(" + element + ")");
    end
  end
  return;
end
if iscell(value)
  update_text(engine, "cell");
  update_shape(engine, size(value));
  for index = 1:numel(value)
    update_value(engine, value{index}, path + "{" + index + "}");
  end
  return;
end
if isstring(value)
  update_text(engine, "string");
  update_shape(engine, size(value));
  for index = 1:numel(value)
    if ismissing(value(index))
      update_text(engine, "<missing>");
    else
      update_text(engine, value(index));
    end
  end
  return;
end
if ischar(value)
  update_text(engine, "char");
  update_shape(engine, size(value));
  update_bytes(engine, unicode2native(value(:).', "UTF-8"));
  return;
end
if isnumeric(value)
  update_numeric(engine, value);
  return;
end
if islogical(value)
  update_text(engine, "logical");
  update_shape(engine, size(value));
  update_bytes(engine, uint8(value(:)));
  return;
end
if isa(value, "datetime") || isa(value, "duration") || isa(value, "calendarDuration")
  update_text(engine, class(value));
  update_shape(engine, size(value));
  update_value(engine, string(value), path + ".text");
  return;
end
if isobject(value) && ismethod(value, "to_struct")
  update_text(engine, "object:" + string(class(value)));
  update_value(engine, value.to_struct(), path + ".to_struct");
  return;
end
if isa(value, "function_handle")
  error("testoracle:manifest:nonCanonicalValue", ...
    "Function handles are forbidden in a frozen manifest (%s).", path);
end
error("testoracle:manifest:nonCanonicalValue", ...
  "Unsupported value of class %s at %s.", class(value), path);
end

function update_numeric(engine, value)
update_text(engine, "numeric:" + string(class(value)));
update_shape(engine, size(value));
update_text(engine, "complex:" + string(~isreal(value)));
if isempty(value)
  update_bytes(engine, zeros(0, 1, "uint8"));
  return;
end
real_value = real(value(:));
real_value(real_value == 0) = 0; % normalize negative zero
update_bytes(engine, numeric_bytes(real_value));
if ~isreal(value)
  imag_value = imag(value(:));
  imag_value(imag_value == 0) = 0;
  update_bytes(engine, numeric_bytes(imag_value));
end
end

function bytes = numeric_bytes(value)
if is_big_endian() && ~isa(value, "uint8") && ~isa(value, "int8")
  value = swapbytes(value);
end
bytes = typecast(value(:), "uint8");
end

function update_shape(engine, shape)
update_bytes(engine, typecast(uint64(shape(:)), "uint8"));
end

function update_text(engine, value)
bytes = unicode2native(char(string(value)), "UTF-8");
update_bytes(engine, bytes);
end

function update_bytes(engine, bytes)
bytes = uint8(bytes(:));
length_bytes = typecast(uint64(numel(bytes)), "uint8");
if is_big_endian()
  length_bytes = typecast(swapbytes(uint64(numel(bytes))), "uint8");
end
engine.update(length_bytes);
if ~isempty(bytes)
  engine.update(bytes);
end
end

function tf = is_big_endian()
[~, ~, endian] = computer;
tf = endian == 'B';
end
