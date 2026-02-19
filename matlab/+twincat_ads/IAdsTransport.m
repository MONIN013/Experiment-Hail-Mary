classdef (Abstract) IAdsTransport < handle
  methods (Abstract)
    connect(obj, ams_net_id, port)
    disconnect(obj)
    value = readScalar(obj, symbol, net_type)
    writeScalar(obj, symbol, value, net_type)
    values = readArray(obj, symbol, net_type, n)
    writeArray(obj, symbol, values, net_type)
  end
end
