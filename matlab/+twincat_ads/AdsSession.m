classdef AdsSession < handle
  properties (Access = private)
    ams_net_id = ""
    ads_assembly = ""
    transport_factory
    transport_cache
  end

  methods
    function obj = AdsSession(ams_net_id, varargin)
      p = inputParser;
      p.addParameter("ads_assembly", "", @(x) ischar(x) || isstring(x));
      p.addParameter("transport_factory", [], @(x) isempty(x) || isa(x, "function_handle"));
      p.parse(varargin{:});

      obj.ams_net_id = string(ams_net_id);
      if strlength(strtrim(obj.ams_net_id)) == 0
        error("twincat_ads:session:invalidConfig", "ams_net_id is required.");
      end
      obj.ads_assembly = string(p.Results.ads_assembly);
      obj.transport_factory = p.Results.transport_factory;
      if isempty(obj.transport_factory)
        obj.transport_factory = @twincat_ads.AdsSession.default_transport_factory;
      end
      obj.transport_cache = containers.Map("KeyType", "char", "ValueType", "any");
    end

    function transport_obj = transport(obj, port)
      key = obj.port_key(port);
      if isKey(obj.transport_cache, key)
        transport_obj = obj.transport_cache(key);
        return;
      end

      transport_obj = obj.transport_factory("ads_assembly", char(obj.ads_assembly));
      if ~isa(transport_obj, "twincat_ads.IAdsTransport")
        error("twincat_ads:session:invalidConfig", ...
          "transport_factory must return a twincat_ads.IAdsTransport.");
      end
      transport_obj.connect(char(obj.ams_net_id), double(port));
      obj.transport_cache(key) = transport_obj;
    end

    function close(obj)
      if isempty(obj.transport_cache)
        return;
      end
      keys = obj.transport_cache.keys();
      for k = 1:numel(keys)
        transport_obj = obj.transport_cache(keys{k});
        try
          transport_obj.disconnect();
        catch
        end
      end
      obj.transport_cache = containers.Map("KeyType", "char", "ValueType", "any");
    end

    function delete(obj)
      obj.close();
    end
  end

  methods (Static)
    function transport_obj = default_transport_factory(varargin)
      transport_obj = twincat_ads.AdsTransport(varargin{:});
    end
  end

  methods (Access = private)
    function key = port_key(~, port)
      port = double(port);
      if ~isscalar(port) || ~isfinite(port) || floor(port) ~= port || port < 0
        error("twincat_ads:session:invalidConfig", "port must be a nonnegative integer.");
      end
      key = char(string(port));
    end
  end
end
