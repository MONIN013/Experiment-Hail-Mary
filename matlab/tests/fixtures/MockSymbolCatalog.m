classdef MockSymbolCatalog < ehm.interfaces.ISymbolCatalog
  methods
    function symbols = resolveVirtualMotorSymbols(~, prefix)
      if strlength(string(prefix)) == 0
        symbols = ehm.contracts.VirtualMotorSymbols.fromDefaults();
      else
        symbols = ehm.contracts.VirtualMotorSymbols.fromPrefix(prefix);
      end
    end

    function validateRequiredSymbols(~, transport, symbols)
      probes = symbols.requiredProbes;
      for k = 1:size(probes, 1)
        transport.readScalar(probes{k, 1}, probes{k, 2});
      end
    end
  end
end
