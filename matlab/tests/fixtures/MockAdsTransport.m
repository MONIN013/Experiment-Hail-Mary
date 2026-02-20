classdef MockAdsTransport < twincat_ads.IAdsTransport
  properties
    connected = false
    scalarMap
    arrayMap
    operations
    forceStartTrue = false
  end

  methods
    function obj = MockAdsTransport()
      obj.scalarMap = containers.Map("KeyType", "char", "ValueType", "any");
      obj.arrayMap = containers.Map("KeyType", "char", "ValueType", "any");
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
      if ~isKey(obj.scalarMap, key)
        error("twincat_ads:symbol:notFound", "Missing scalar symbol: %s", key);
      end
      value = obj.scalarMap(key);
    end

    function write_scalar(obj, symbol, value, ~)
      key = char(string(symbol));
      obj.operations(end + 1, 1) = "write_scalar:" + string(key);
      obj.scalarMap(key) = value;
    end

    function values = read_array(obj, symbol, ~, n)
      key = char(string(symbol));
      obj.operations(end + 1, 1) = "read_array:" + string(key);
      if ~isKey(obj.arrayMap, key)
        error("twincat_ads:symbol:notFound", "Missing array symbol: %s", key);
      end
      values = obj.arrayMap(key);
      values = values(:);
      values = values(1:min(numel(values), double(n)));
    end

    function write_array(obj, symbol, values, ~)
      key = char(string(symbol));
      obj.operations(end + 1, 1) = "write_array:" + string(key);
      obj.arrayMap(key) = values(:);
    end
  end
end
