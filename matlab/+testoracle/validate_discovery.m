function report = validate_discovery(ports, symbols, options)
% validate_discovery  Require a successful nonempty symbol set per ADS port.
arguments
  ports
  symbols
  options.required_ports = []
  options.required_symbols struct = struct("port", {}, "name", {})
end
required_port_columns = ["Port", "Status"];
required_symbol_columns = ["Port", "Status"];
if ~isempty(options.required_symbols)
  required_symbol_columns(end + 1) = "Name";
end
valid_tables = istable(ports) && istable(symbols) && ~isempty(ports) && ...
  all(ismember(required_port_columns, string(ports.Properties.VariableNames))) && ...
  all(ismember(required_symbol_columns, string(symbols.Properties.VariableNames)));
if ~valid_tables
  report = struct("pass", false, "valid_tables", false, ...
    "port_count", 0, "ports", struct([]), ...
    "required_ports_match", false, "unique_ports", false, ...
    "unique_symbols", false, "required_symbols_match", false);
  return;
end

port_values = double(ports.Port(:));
unique_ports = numel(unique(port_values)) == numel(port_values);
required_ports = double(options.required_ports(:));
if isempty(required_ports)
  required_ports_match = true;
else
  required_ports_match = unique_ports && ...
    isequal(sort(port_values), sort(required_ports));
end
if ismember("Name", string(symbols.Properties.VariableNames))
  symbol_keys = string(double(symbols.Port(:))) + "|" + string(symbols.Name(:));
  unique_symbols = numel(unique(symbol_keys)) == numel(symbol_keys);
else
  unique_symbols = true;
end
required_symbols_match = true;
for required = options.required_symbols(:)'
  mask = double(symbols.Port(:)) == double(required.port) & ...
    string(symbols.Name(:)) == string(required.name);
  required_symbols_match = required_symbols_match && nnz(mask) == 1 && ...
    all(string(symbols.Status(mask)) == "ok");
end
items = repmat(struct("port", 0, "port_status_ok", false, ...
  "symbol_count", 0, "symbol_status_ok", false, "pass", false), ...
  numel(port_values), 1);
for index = 1:numel(port_values)
  port = port_values(index);
  port_ok = string(ports.Status(index)) == "ok";
  mask = double(symbols.Port(:)) == port;
  symbol_ok = any(mask) && all(string(symbols.Status(mask)) == "ok");
  items(index) = struct( ...
    "port", port, "port_status_ok", logical(port_ok), ...
    "symbol_count", nnz(mask), "symbol_status_ok", logical(symbol_ok), ...
    "pass", logical(port_ok && symbol_ok));
end
report = struct("pass", logical(all([items.pass]) && required_ports_match && ...
    unique_ports && unique_symbols && required_symbols_match), ...
  "valid_tables", true, "port_count", numel(items), "ports", items, ...
  "required_ports_match", logical(required_ports_match), ...
  "unique_ports", logical(unique_ports), ...
  "unique_symbols", logical(unique_symbols), ...
  "required_symbols_match", logical(required_symbols_match));
end
