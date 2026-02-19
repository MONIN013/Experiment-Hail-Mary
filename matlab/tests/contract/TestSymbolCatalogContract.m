classdef TestSymbolCatalogContract < matlab.unittest.TestCase
  methods (Test)
    function validateRequiredSymbolsReportsMissing(testCase)
      catalog = ehm.adapters.twincat.TwinCATSymbolCatalog();
      transport = MockAdsTransport();
      symbols = ehm.contracts.VirtualMotorSymbols.fromDefaults();
      testCase.verifyError(@()catalog.validateRequiredSymbols(transport, symbols), "ehm:symbol:notFound");
    end

    function validateRequiredSymbolsPassesWhenPresent(testCase)
      catalog = ehm.adapters.twincat.TwinCATSymbolCatalog();
      transport = MockAdsTransport();
      s = ehm.contracts.VirtualMotorSymbols.fromDefaults();
      transport.scalarMap(char(s.start)) = false;
      transport.scalarMap(char(s.reset)) = false;
      transport.scalarMap(char(s.currentIn)) = 0.0;
      transport.scalarMap(char(s.positionOut)) = 0.0;
      transport.scalarMap(char(s.velocityOut)) = 0.0;
      transport.scalarMap(char(s.cmdLen)) = uint32(0);
      transport.scalarMap(char(s.cmdIdx)) = uint32(0);
      transport.scalarMap(char(s.log.wrIdx)) = uint32(0);
      transport.scalarMap(char(s.log.overflow)) = false;
      testCase.verifyWarningFree(@()catalog.validateRequiredSymbols(transport, s));
    end

    function collectSymbolsSkipsRowsWithMissingName(testCase)
      symbolMissingName = MockDotNetSymbol("TypeName", "INT", "Size", int32(4));
      symbolValid = MockDotNetSymbol("Name", "GVL.mySignal", "TypeName", "REAL", "Size", int32(4));
      symbols = MockDotNetCollection({symbolMissingName, symbolValid});

      testCase.verifyWarningFree(@()ehm.adapters.twincat.TwinCATSymbolCatalog.collectSymbolsForTest(symbols, false));
      [names, types, sizes] = ehm.adapters.twincat.TwinCATSymbolCatalog.collectSymbolsForTest(symbols, false);

      testCase.verifyEqual(names, "GVL.mySignal");
      testCase.verifyEqual(types, "REAL");
      testCase.verifyEqual(sizes, int32(4));
    end
  end
end
