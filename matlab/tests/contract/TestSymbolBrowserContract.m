classdef TestSymbolBrowserContract < matlab.unittest.TestCase
  methods (Test)
    function validateRequiredSymbolsReportsMissing(testCase)
      transport = MockAdsTransport();
      symbols = experiment.VirtualMotorSymbols.from_defaults();
      testCase.verifyError( ...
        @()twincat_ads.SymbolBrowser.validate_symbols(transport, symbols.plcRequiredProbes), ...
        "twincat_ads:symbol:notFound");
    end

    function validateRequiredSymbolsPassesWhenPresent(testCase)
      transport = MockAdsTransport();
      s = experiment.VirtualMotorSymbols.from_defaults();
      transport.scalarMap(char(s.reset)) = false;
      transport.scalarMap(char(s.experimentActive)) = false;
      transport.scalarMap(char(s.tableLen)) = uint32(0);
      transport.scalarMap(char(s.idx)) = uint32(0);
      transport.scalarMap(char(s.refValue)) = 0.0;
      transport.scalarMap(char(s.ffValue)) = 0.0;
      transport.scalarMap(char(s.distValue)) = 0.0;
      transport.scalarMap(char(s.controlInput)) = 0.0;
      transport.scalarMap(char(s.positionActLog)) = 0.0;
      transport.scalarMap(char(s.log.wrIdx)) = uint32(0);
      transport.scalarMap(char(s.log.rdIdx)) = uint32(0);
      transport.scalarMap(char(s.log.overflow)) = false;
      testCase.verifyWarningFree( ...
        @()twincat_ads.SymbolBrowser.validate_symbols(transport, s.plcRequiredProbes));
    end

    function collectSymbolsErrorsOnMissingIdentity(testCase)
      symbolMissingName = MockDotNetSymbol("TypeName", "INT", "Size", int32(4));
      symbolValid = MockDotNetSymbol("Name", "GVL.mySignal", "TypeName", "REAL", "Size", int32(4));
      symbols = MockDotNetCollection({symbolMissingName, symbolValid});

      testCase.verifyError(@()twincat_ads.SymbolBrowser.collect_symbols_for_test(symbols, false), ...
        "twincat_ads:symbolTraversal:identityUnavailable");
    end
  end
end


