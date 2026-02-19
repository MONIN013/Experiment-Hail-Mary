classdef TwinCATAdsTransport < ehm.interfaces.IAdsTransport
  properties (Access = private)
    client = []
    adsAssembly = "TwinCAT.Ads"
  end

  methods
    function obj = TwinCATAdsTransport(varargin)
      p = inputParser;
      p.addParameter("ads_assembly", "TwinCAT.Ads", @(x) ischar(x) || isstring(x));
      p.parse(varargin{:});
      obj.adsAssembly = string(p.Results.ads_assembly);
      obj.loadAssembly();
    end

    function connect(obj, amsNetId, port)
      amsNetId = char(string(amsNetId));
      if isempty(strtrim(amsNetId))
        error("ehm:transport:connectFailed", "amsNetId must be explicitly specified.");
      end

      obj.disconnect();
      try
        obj.client = TwinCAT.Ads.TcAdsClient();
        obj.client.Connect(amsNetId, int32(port));
      catch e
        obj.client = [];
        error("ehm:transport:connectFailed", ...
          "Failed to connect ADS client (amsNetId='%s', port=%d): %s", ...
          amsNetId, int32(port), e.message);
      end
    end

    function disconnect(obj)
      if isempty(obj.client)
        return;
      end
      try
        obj.client.Dispose();
      catch
      end
      obj.client = [];
    end

    function delete(obj)
      obj.disconnect();
    end

    function c = readClient(obj)
      c = obj.requireClient();
    end

    function value = readScalar(obj, symbol, netType)
      c = obj.requireClient();
      handle = c.CreateVariableHandle(char(symbol));
      cleanupObj = onCleanup(@()obj.safeDeleteHandle(c, handle)); %#ok<NASGU>

      typeObj = obj.resolveNetType(netType);
      o = c.ReadAny(handle, typeObj);
      value = obj.convertNetObject(o);
    end

    function writeScalar(obj, symbol, value, netType)
      c = obj.requireClient();
      handle = c.CreateVariableHandle(char(symbol));
      cleanupObj = onCleanup(@()obj.safeDeleteHandle(c, handle)); %#ok<NASGU>
      netValue = obj.toNetScalar(value, netType);
      c.WriteAny(handle, netValue);
    end

    function values = readArray(obj, symbol, netType, n)
      c = obj.requireClient();
      nDouble = double(n);
      if nDouble <= 0
        values = zeros(0, 1);
        return;
      end

      handle = c.CreateVariableHandle(char(symbol));
      cleanupObj = onCleanup(@()obj.safeDeleteHandle(c, handle)); %#ok<NASGU>

      elemType = obj.resolveNetType(netType);
      arrayType = elemType.MakeArrayType();
      dims = NET.createArray("System.Int32", 1);
      dims(1) = int32(nDouble);
      o = c.ReadAny(handle, arrayType, dims);

      if isnumeric(o) || islogical(o)
        values = double(o(:));
        return;
      end

      if isa(o, "System.Array")
        values = zeros(nDouble, 1);
        for k = 1:nDouble
          values(k) = obj.convertNetObject(o.GetValue(int32(k - 1)));
        end
        return;
      end

      error("ehm:type:unsupported", ...
        "Unexpected ADS array read return type for symbol '%s'.", string(symbol));
    end

    function writeArray(obj, symbol, values, netType)
      c = obj.requireClient();
      vals = double(values(:));
      nDouble = numel(vals);
      if nDouble == 0
        return;
      end

      handle = c.CreateVariableHandle(char(symbol));
      cleanupObj = onCleanup(@()obj.safeDeleteHandle(c, handle)); %#ok<NASGU>

      switch char(string(netType))
        case "System.Double"
          netArr = NET.createArray("System.Double", nDouble);
          for k = 1:nDouble
            netArr(k) = vals(k);
          end
        case "System.Single"
          netArr = NET.createArray("System.Single", nDouble);
          for k = 1:nDouble
            netArr(k) = single(vals(k));
          end
        case "System.Int32"
          netArr = NET.createArray("System.Int32", nDouble);
          for k = 1:nDouble
            netArr(k) = int32(vals(k));
          end
        case "System.UInt32"
          netArr = NET.createArray("System.UInt32", nDouble);
          for k = 1:nDouble
            netArr(k) = uint32(vals(k));
          end
        case "System.Int64"
          netArr = NET.createArray("System.Int64", nDouble);
          for k = 1:nDouble
            netArr(k) = int64(vals(k));
          end
        case "System.UInt64"
          netArr = NET.createArray("System.UInt64", nDouble);
          for k = 1:nDouble
            netArr(k) = uint64(vals(k));
          end
        otherwise
          error("ehm:type:unsupported", ...
            "Unsupported .NET element type for array write: %s", string(netType));
      end

      c.WriteAny(handle, netArr);
    end
  end

  methods (Static)
    function t = netTypes()
      t = struct( ...
        "bool", "System.Boolean", ...
        "double", "System.Double", ...
        "single", "System.Single", ...
        "u32", "System.UInt32", ...
        "u64", "System.UInt64");
    end
  end

  methods (Access = private)
    function loadAssembly(obj)
      adsAssembly = char(obj.adsAssembly);
      if exist(adsAssembly, "file") == 2
        NET.addAssembly(adsAssembly);
        return;
      end
      try
        NET.addAssembly(adsAssembly);
      catch e
        error("ehm:transport:assemblyLoadFailed", ...
          "Failed to load ADS assembly '%s': %s", adsAssembly, e.message);
      end
    end

    function c = requireClient(obj)
      if isempty(obj.client)
        error("ehm:transport:notConnected", "ADS client is not connected.");
      end
      c = obj.client;
    end

    function typeObj = resolveNetType(~, netTypeName)
      typeObj = System.Type.GetType(char(string(netTypeName)));
      if isempty(typeObj)
        error("ehm:type:unsupported", "Unsupported .NET type: %s", string(netTypeName));
      end
    end

    function value = convertNetObject(~, o)
      if isnumeric(o) || islogical(o)
        value = o;
        return;
      end
      if isa(o, "System.Boolean")
        value = logical(o);
        return;
      end
      if isa(o, "System.Double")
        value = double(o);
        return;
      end
      if isa(o, "System.Single")
        value = single(o);
        return;
      end
      if isa(o, "System.UInt32")
        value = uint32(o);
        return;
      end
      if isa(o, "System.Int32")
        value = int32(o);
        return;
      end
      if isa(o, "System.UInt64")
        value = uint64(o);
        return;
      end
      if isa(o, "System.Int64")
        value = int64(o);
        return;
      end
      value = o;
    end

    function netValue = toNetScalar(~, value, netTypeName)
      switch char(string(netTypeName))
        case "System.Boolean"
          netValue = logical(value);
        case "System.Double"
          netValue = double(value);
        case "System.Single"
          netValue = single(value);
        case "System.Int32"
          netValue = int32(value);
        case "System.UInt32"
          netValue = uint32(value);
        case "System.Int64"
          netValue = int64(value);
        case "System.UInt64"
          netValue = uint64(value);
        otherwise
          error("ehm:type:unsupported", "Unsupported .NET scalar type: %s", string(netTypeName));
      end
    end

    function safeDeleteHandle(~, client, handle)
      try
        client.DeleteVariableHandle(handle);
      catch
      end
    end
  end
end
