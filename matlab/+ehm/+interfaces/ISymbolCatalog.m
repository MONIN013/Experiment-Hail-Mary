classdef (Abstract) ISymbolCatalog < handle
  methods (Abstract)
    symbols = resolveVirtualMotorSymbols(obj, prefix)
    validateRequiredSymbols(obj, transport, symbols)
  end
end
