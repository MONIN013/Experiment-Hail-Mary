classdef (Abstract) IAdsTransport < handle
  methods (Abstract)
    connect(obj, amsNetId, port)
    disconnect(obj)
    value = readScalar(obj, symbol, netType)
    writeScalar(obj, symbol, value, netType)
    values = readArray(obj, symbol, netType, n)
    writeArray(obj, symbol, values, netType)
  end
end
