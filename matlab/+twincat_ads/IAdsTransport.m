classdef (Abstract) IAdsTransport < handle
  methods (Abstract)
    connect(obj, ams_net_id, port)
    disconnect(obj)
    value = read_scalar(obj, symbol, net_type)
    write_scalar(obj, symbol, value, net_type)
    values = read_array(obj, symbol, net_type, n)
    write_array(obj, symbol, values, net_type)
  end
end
