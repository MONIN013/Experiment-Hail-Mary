classdef MockAdsTransport < twincat_ads.IAdsTransport
  properties
    connected = false
    scalarMap
    scalarReadSequenceMap
    scalarReadSequenceIndexMap
    arrayMap
    arraySliceErrorMap
    operations
    forceStartTrue = false
    autoResetAck = true
  end

  methods
    function obj = MockAdsTransport()
      obj.scalarMap = containers.Map("KeyType", "char", "ValueType", "any");
      obj.scalarReadSequenceMap = containers.Map("KeyType", "char", "ValueType", "any");
      obj.scalarReadSequenceIndexMap = containers.Map("KeyType", "char", "ValueType", "any");
      obj.arrayMap = containers.Map("KeyType", "char", "ValueType", "any");
      obj.arraySliceErrorMap = containers.Map("KeyType", "char", "ValueType", "any");
      obj.operations = strings(0, 1);
    end

    function connect(obj, ~, ~)
      obj.connected = true;
      obj.operations(end + 1, 1) = "connect";
    end

    function disconnect(obj)
      obj.connected = false;
      obj.operations(end + 1, 1) = "disconnect";
    end

    function value = read_scalar(obj, symbol, ~)
      key = char(string(symbol));
      obj.operations(end + 1, 1) = "read_scalar:" + string(key);
      if contains(key, "experiment_start") && obj.forceStartTrue
        value = true;
        return;
      end
      if isKey(obj.scalarReadSequenceMap, key)
        seq = obj.scalarReadSequenceMap(key);
        idx = 1;
        if isKey(obj.scalarReadSequenceIndexMap, key)
          idx = obj.scalarReadSequenceIndexMap(key);
        end
        idx = min(double(idx), numel(seq));
        if iscell(seq)
          value = seq{idx};
        else
          value = seq(idx);
        end
        obj.scalarReadSequenceIndexMap(key) = idx + 1;
        return;
      end
      if ~isKey(obj.scalarMap, key)
        error("twincat_ads:symbol:notFound", "Missing scalar symbol: %s", key);
      end
      value = obj.scalarMap(key);
    end

    function write_scalar(obj, symbol, value, ~)
      key = char(string(symbol));
      obj.operations(end + 1, 1) = "write_scalar:" + string(key);
      obj.scalarMap(key) = value;
      if obj.autoResetAck && strcmp(key, "GVL_MODE.resetReq") && logical(value)
        ack_key = "GVL_MODE.resetAckCounter";
        if isKey(obj.scalarMap, ack_key)
          obj.scalarMap(ack_key) = uint32(double(obj.scalarMap(ack_key)) + 1);
        end
        obj.scalarMap(key) = false;
      end
    end

    function values = read_struct(obj, symbol_map)
      values = struct();
      fields = fieldnames(symbol_map);
      for k = 1:numel(fields)
        field_name = fields{k};
        entry = symbol_map.(field_name);
        [symbol, net_type] = parse_struct_entry(entry);
        values.(field_name) = obj.read_scalar(symbol, net_type);
      end
    end

    function write_struct(obj, symbol_map, values)
      fields = fieldnames(symbol_map);
      for k = 1:numel(fields)
        field_name = fields{k};
        if ~isfield(values, field_name)
          error("twincat_ads:transport:invalidStructMap", ...
            "Missing field '%s' in write_struct values.", field_name);
        end
        entry = symbol_map.(field_name);
        [symbol, net_type] = parse_struct_entry(entry);
        obj.write_scalar(symbol, values.(field_name), net_type);
      end
    end

    function values = read_array(obj, symbol, ~, n)
      key = char(string(symbol));
      obj.operations(end + 1, 1) = "read_array:" + string(key);
      values = obj.read_array_from_key(key, n);
    end

    function values = read_array_slice(obj, symbol, ~, start_idx, n)
      base_key = char(string(symbol));
      start_idx = double(start_idx);
      if start_idx < 0 || floor(start_idx) ~= start_idx
        error("twincat_ads:transport:invalidIndex", "start_idx must be nonnegative integer");
      end
      obj.operations(end + 1, 1) = "read_array_slice:" + string(base_key);
      if isKey(obj.arraySliceErrorMap, base_key)
        e = obj.arraySliceErrorMap(base_key);
        error(e.identifier, "%s", e.message);
      end
      if ~isKey(obj.arrayMap, base_key)
        error("twincat_ads:symbol:notFound", "Missing array symbol: %s", base_key);
      end
      values = obj.arrayMap(base_key);
      values = values(:);
      first = double(start_idx) + 1;
      if first > numel(values)
        values = values([]); % keep type
        return;
      end
      last = min(numel(values), first + double(n) - 1);
      values = values(first:last);
    end

    function write_array(obj, symbol, values, ~)
      key = char(string(symbol));
      obj.operations(end + 1, 1) = "write_array:" + string(key);
      obj.arrayMap(key) = values(:);
    end

    function set_scalar_read_sequence(obj, symbol, values)
      key = char(string(symbol));
      vals = values(:);
      if isempty(vals)
        if isKey(obj.scalarReadSequenceMap, key)
          remove(obj.scalarReadSequenceMap, key);
        end
        if isKey(obj.scalarReadSequenceIndexMap, key)
          remove(obj.scalarReadSequenceIndexMap, key);
        end
        return;
      end
      obj.scalarReadSequenceMap(key) = num2cell(vals);
      obj.scalarReadSequenceIndexMap(key) = 1;
    end

    function set_read_array_slice_error(obj, symbol, identifier, message)
      key = char(string(symbol));
      if nargin < 4
        message = "mock read_array_slice failure";
      end
      if strlength(string(identifier)) == 0
        if isKey(obj.arraySliceErrorMap, key)
          remove(obj.arraySliceErrorMap, key);
        end
        return;
      end
      obj.arraySliceErrorMap(key) = struct( ...
        "identifier", char(string(identifier)), ...
        "message", char(string(message)));
    end
  end

  methods (Access = private)
    function values = read_array_from_key(obj, key, n)
      if ~isKey(obj.arrayMap, key)
        error("twincat_ads:symbol:notFound", "Missing array symbol: %s", key);
      end
      values = obj.arrayMap(key);
      values = values(:);
      values = values(1:min(numel(values), double(n)));
    end
  end
end

function [symbol, net_type] = parse_struct_entry(entry)
if ~iscell(entry) || numel(entry) ~= 2
  error("twincat_ads:transport:invalidStructMap", ...
    "Struct map entry must be a 1x2 cell array {symbol, net_type}.");
end
symbol = entry{1};
net_type = entry{2};
end
