classdef AdsTransport < twincat_ads.IAdsTransport
  properties (Access = private)
    client = []
    ads_assembly = ""
  end

  methods
    function obj = AdsTransport(varargin)
      p = inputParser;
      p.addParameter("ads_assembly", "", @(x) ischar(x) || isstring(x));
      p.parse(varargin{:});
      obj.ads_assembly = string(p.Results.ads_assembly);
      obj.loadAssembly();
    end

    function connect(obj, ams_net_id, port)
      ams_net_id = char(string(ams_net_id));
      if isempty(strtrim(ams_net_id))
        error("twincat_ads:transport:connectFailed", "ams_net_id must be explicitly specified.");
      end

      obj.disconnect();
      try
        obj.client = TwinCAT.Ads.TcAdsClient();
        obj.client.Connect(ams_net_id, int32(port));
      catch e
        obj.client = [];
        error("twincat_ads:transport:connectFailed", ...
          "Failed to connect ADS client (ams_net_id='%s', port=%d): %s", ...
          ams_net_id, int32(port), e.message);
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

    function value = readScalar(obj, symbol, net_type)
      c = obj.requireClient();
      handle = c.CreateVariableHandle(char(symbol));
      cleanup_obj = onCleanup(@()obj.safeDeleteHandle(c, handle)); %#ok<NASGU>

      type_obj = obj.resolveNetType(net_type);
      o = c.ReadAny(handle, type_obj);
      value = obj.convertNetObject(o);
    end

    function writeScalar(obj, symbol, value, net_type)
      c = obj.requireClient();
      handle = c.CreateVariableHandle(char(symbol));
      cleanup_obj = onCleanup(@()obj.safeDeleteHandle(c, handle)); %#ok<NASGU>
      net_value = obj.toNetScalar(value, net_type);
      c.WriteAny(handle, net_value);
    end

    function values = readArray(obj, symbol, net_type, n)
      c = obj.requireClient();
      n_double = double(n);
      if n_double <= 0
        values = zeros(0, 1);
        return;
      end

      handle = c.CreateVariableHandle(char(symbol));
      cleanup_obj = onCleanup(@()obj.safeDeleteHandle(c, handle)); %#ok<NASGU>

      elem_type = obj.resolveNetType(net_type);
      array_type = elem_type.MakeArrayType();
      dims = NET.createArray("System.Int32", 1);
      dims(1) = int32(n_double);
      o = c.ReadAny(handle, array_type, dims);

      if isnumeric(o) || islogical(o)
        values = double(o(:));
        return;
      end

      if isa(o, "System.Array")
        values = zeros(n_double, 1);
        for k = 1:n_double
          values(k) = obj.convertNetObject(o.GetValue(int32(k - 1)));
        end
        return;
      end

      error("twincat_ads:type:unsupported", ...
        "Unexpected ADS array read return type for symbol '%s'.", string(symbol));
    end

    function writeArray(obj, symbol, values, net_type)
      c = obj.requireClient();
      vals = double(values(:));
      n_double = numel(vals);
      if n_double == 0
        return;
      end

      handle = c.CreateVariableHandle(char(symbol));
      cleanup_obj = onCleanup(@()obj.safeDeleteHandle(c, handle)); %#ok<NASGU>

      switch char(string(net_type))
        case "System.Double"
          net_arr = NET.createArray("System.Double", n_double);
          for k = 1:n_double
            net_arr(k) = vals(k);
          end
        case "System.Single"
          net_arr = NET.createArray("System.Single", n_double);
          for k = 1:n_double
            net_arr(k) = single(vals(k));
          end
        case "System.Int32"
          net_arr = NET.createArray("System.Int32", n_double);
          for k = 1:n_double
            net_arr(k) = int32(vals(k));
          end
        case "System.UInt32"
          net_arr = NET.createArray("System.UInt32", n_double);
          for k = 1:n_double
            net_arr(k) = uint32(vals(k));
          end
        case "System.Int64"
          net_arr = NET.createArray("System.Int64", n_double);
          for k = 1:n_double
            net_arr(k) = int64(vals(k));
          end
        case "System.UInt64"
          net_arr = NET.createArray("System.UInt64", n_double);
          for k = 1:n_double
            net_arr(k) = uint64(vals(k));
          end
        otherwise
          error("twincat_ads:type:unsupported", ...
            "Unsupported .NET element type for array write: %s", string(net_type));
      end

      c.WriteAny(handle, net_arr);
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
      attempts = strings(0, 1);
      errors = strings(0, 1);
      candidates = obj.assemblyCandidates();
      for k = 1:numel(candidates)
        candidate = candidates(k);
        attempts(end + 1, 1) = candidate; %#ok<AGROW>
        try
          twincat_ads.AdsTransport.tryLoadAssembly(candidate);
          return;
        catch e
          errors(end + 1, 1) = string(e.message); %#ok<AGROW>
        end
      end

      attempt_text = strjoin(attempts, ", ");
      error_text = strjoin(errors, " | ");
      error("twincat_ads:transport:assemblyLoadFailed", ...
        "Failed to load ADS assembly. Attempts: %s. Details: %s", ...
        attempt_text, error_text);
    end

    function candidates = assemblyCandidates(obj)
      known_path = "C:\Program Files (x86)\Beckhoff\TwinCAT\Functions\TE14xx-ToolsForMatlabAndSimulink\TE140x\NET\TwinCAT.Ads.dll";
      explicit = strtrim(obj.ads_assembly);
      base = strings(0, 1);
      if strlength(explicit) > 0
        base(end + 1, 1) = explicit; %#ok<AGROW>
      end
      if isfile(known_path)
        base(end + 1, 1) = known_path; %#ok<AGROW>
      end
      base(end + 1, 1) = "TwinCAT.Ads"; %#ok<AGROW>
      [~, ia] = unique(base, "stable");
      candidates = base(ia);
    end

    function c = requireClient(obj)
      if isempty(obj.client)
        error("twincat_ads:transport:notConnected", "ADS client is not connected.");
      end
      c = obj.client;
    end

    function type_obj = resolveNetType(~, net_type_name)
      type_obj = System.Type.GetType(char(string(net_type_name)));
      if isempty(type_obj)
        error("twincat_ads:type:unsupported", "Unsupported .NET type: %s", string(net_type_name));
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

    function net_value = toNetScalar(~, value, net_type_name)
      switch char(string(net_type_name))
        case "System.Boolean"
          net_value = logical(value);
        case "System.Double"
          net_value = double(value);
        case "System.Single"
          net_value = single(value);
        case "System.Int32"
          net_value = int32(value);
        case "System.UInt32"
          net_value = uint32(value);
        case "System.Int64"
          net_value = int64(value);
        case "System.UInt64"
          net_value = uint64(value);
        otherwise
          error("twincat_ads:type:unsupported", ...
            "Unsupported .NET scalar type: %s", string(net_type_name));
      end
    end

    function safeDeleteHandle(~, client, handle)
      try
        client.DeleteVariableHandle(handle);
      catch
      end
    end
  end

  methods (Static, Access = private)
    function tryLoadAssembly(assembly_name)
      name = char(string(assembly_name));
      if isempty(strtrim(name))
        error("twincat_ads:transport:assemblyLoadFailed", "Assembly name/path is empty.");
      end
      if exist(name, "file") == 2
        NET.addAssembly(name);
        return;
      end
      NET.addAssembly(name);
    end
  end
end
