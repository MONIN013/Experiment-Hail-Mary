classdef SymbolBrowser
  methods (Static)
    function validate_symbols(transport, probe_list)
      if ~isa(transport, "twincat_ads.IAdsTransport")
        error("twincat_ads:symbol:invalidTransport", ...
          "transport must implement twincat_ads.IAdsTransport.");
      end
      if isempty(probe_list)
        return;
      end

      missing = strings(0, 1);
      for k = 1:size(probe_list, 1)
        symbol = string(probe_list{k, 1});
        net_type = string(probe_list{k, 2});
        try
          transport.read_scalar(symbol, net_type);
        catch
          missing(end + 1, 1) = symbol; %#ok<AGROW>
        end
      end
      if ~isempty(missing)
        error("twincat_ads:symbol:notFound", ...
          "Required ADS symbols not found: %s", strjoin(missing, ", "));
      end
    end

    function [names, types, sizes] = collect_symbols_for_test(symbols, top_level_only)
      if nargin < 2
        top_level_only = true;
      end
      [names, types, sizes] = twincat_ads.internal.SymbolTraversal.collect_symbols( ...
        symbols, logical(top_level_only), inf, inf);
    end

    function [t_ports, t_symbols] = discover_ports_and_symbols(ams_net_id, ports, varargin)
      t_ports = twincat_ads.SymbolBrowser.list_ports(ams_net_id, ports, varargin{:});
      rows = cell(height(t_ports), 1);
      for k = 1:height(t_ports)
        if t_ports.Status(k) == "ok"
          rows{k} = twincat_ads.SymbolBrowser.list_symbols_for_port( ...
            ams_net_id, t_ports.Port(k), varargin{:});
        else
          rows{k} = empty_symbols_table();
        end
      end
      t_symbols = vertcat(rows{:});
      required = {'AmsNetId', 'Port', 'Name', 'Type', 'SizeBytes', 'Status', 'ErrorMessage'};
      if isempty(t_symbols) || ~all(ismember(required, t_symbols.Properties.VariableNames))
        t_symbols = empty_symbols_table();
      end
    end

    function t_ports = list_ports(ams_net_id, ports, varargin)
      p = inputParser;
      p.KeepUnmatched = true;
      p.addParameter("ads_assembly", "", @(x) ischar(x) || isstring(x));
      p.addParameter("connect_timeout_ms", 1000, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.parse(varargin{:});
      cfg = p.Results;

      ams_net_id = string(ams_net_id);
      port_list = int32(ports(:));
      n = numel(port_list);
      status = repmat("connect_failed", n, 1);
      errors = repmat("", n, 1);

      try
        loader = twincat_ads.AdsTransport("ads_assembly", cfg.ads_assembly); %#ok<NASGU>
      catch e
        status(:) = "assembly_failed";
        errors(:) = string(e.message);
        t_ports = table( ...
          repmat(ams_net_id, n, 1), ...
          port_list, ...
          status, ...
          errors, ...
          'VariableNames', {'AmsNetId', 'Port', 'Status', 'ErrorMessage'});
        return;
      end

      for k = 1:n
        client = [];
        try
          client = TwinCAT.Ads.TcAdsClient();
          try_set_client_timeout(client, cfg.connect_timeout_ms);
          client.Connect(char(ams_net_id), port_list(k));
          client.ReadState();
          status(k) = "ok";
        catch e
          status(k) = "connect_failed";
          errors(k) = string(e.message);
        end
        safe_dispose_client(client);
      end

      t_ports = table( ...
        repmat(ams_net_id, n, 1), ...
        port_list, ...
        status, ...
        errors, ...
        'VariableNames', {'AmsNetId', 'Port', 'Status', 'ErrorMessage'});
    end

    function t_symbols = list_symbols_for_port(ams_net_id, port, varargin)
      p = inputParser;
      p.addParameter("ads_assembly", "", @(x) ischar(x) || isstring(x));
      p.addParameter("top_level_only", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("force_reload", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("connect_timeout_ms", 1000, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("traversal_timeout_ms", 5000, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.addParameter("traversal_max_nodes", 50000, @(x) isnumeric(x) && isscalar(x) && x > 0);
      p.parse(varargin{:});
      cfg = p.Results;

      transport = twincat_ads.AdsTransport("ads_assembly", cfg.ads_assembly);
      ams_net_id = string(ams_net_id);
      port = int32(port);

      try
        transport.connect(char(ams_net_id), port);
        client = transport.read_client();
        try_set_client_timeout(client, cfg.connect_timeout_ms);
        loader = TwinCAT.Ads.TypeSystem.SymbolLoaderFactory.Create( ...
          client, TwinCAT.Ads.SymbolLoaderSettings.DefaultDynamic);
        symbols = loader.Symbols;
      catch e
        t_symbols = failed_table(ams_net_id, port, "symbol_loader_failed", string(e.message));
        transport.disconnect();
        return;
      end

      [names, types, sizes] = twincat_ads.internal.SymbolTraversal.collect_symbols( ...
        symbols, ...
        logical(cfg.top_level_only), ...
        double(cfg.traversal_timeout_ms), ...
        double(cfg.traversal_max_nodes));
      symbols = [];
      loader = [];
      transport.disconnect();

      n = numel(names);
      t_symbols = table( ...
        repmat(ams_net_id, n, 1), ...
        repmat(port, n, 1), ...
        names, ...
        types, ...
        sizes, ...
        repmat("ok", n, 1), ...
        repmat("", n, 1), ...
        'VariableNames', {'AmsNetId', 'Port', 'Name', 'Type', 'SizeBytes', 'Status', 'ErrorMessage'});
    end
  end
end

function T = failed_table(ams_net_id, port, status, error_message)
T = table( ...
  ams_net_id, ...
  port, ...
  string(""), ...
  string(""), ...
  int32(0), ...
  string(status), ...
  string(error_message), ...
  'VariableNames', {'AmsNetId', 'Port', 'Name', 'Type', 'SizeBytes', 'Status', 'ErrorMessage'});
end

function T = empty_symbols_table()
T = table( ...
  strings(0, 1), ...
  int32(zeros(0, 1)), ...
  strings(0, 1), ...
  strings(0, 1), ...
  int32(zeros(0, 1)), ...
  strings(0, 1), ...
  strings(0, 1), ...
  'VariableNames', {'AmsNetId', 'Port', 'Name', 'Type', 'SizeBytes', 'Status', 'ErrorMessage'});
end

function try_set_client_timeout(client, timeout_ms)
if isempty(client)
  return;
end
try
  client.Timeout = int32(timeout_ms);
catch
end
end

function safe_dispose_client(client)
if isempty(client)
  return;
end
try
  client.Dispose();
catch
end
end
