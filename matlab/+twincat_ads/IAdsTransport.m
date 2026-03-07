classdef (Abstract) IAdsTransport < handle
  methods (Abstract)
    connect(obj, ams_net_id, port)
    disconnect(obj)
    value = read_scalar(obj, symbol, net_type)
    write_scalar(obj, symbol, value, net_type)
    values = read_struct(obj, symbol_map)
    write_struct(obj, symbol_map, values)
    values = read_array(obj, symbol, net_type, n)
    values = read_array_slice(obj, symbol, net_type, start_idx, n)
    write_array(obj, symbol, values, net_type)
  end
end
