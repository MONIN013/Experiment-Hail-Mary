classdef TestSymbolBrowserContract < matlab.unittest.TestCase
  methods (Test)
    function validateRequiredSymbolsReportsMissing(testCase)
      transport = MockAdsTransport();
      symbols = experiment.RuntimeSymbols.from_defaults();
      testCase.verifyError( ...
        @()twincat_ads.SymbolBrowser.validate_symbols(transport, symbols.plcRequiredProbes), ...
        "twincat_ads:symbol:notFound");
    end

    function validateRequiredSymbolsPassesWhenPresent(testCase)
      transport = MockAdsTransport();
      s = experiment.RuntimeSymbols.from_defaults();
      transport.scalarMap(char(s.reset)) = false;
      transport.scalarMap(char(s.tableLen)) = uint32(0);
      transport.scalarMap(char(s.idx)) = uint32(0);
      transport.scalarMap(char(s.repeatCount)) = uint32(1);
      transport.scalarMap(char(s.trialIndex)) = uint32(0);
      transport.scalarMap(char(s.refValue)) = 0.0;
      transport.scalarMap(char(s.ffValue)) = 0.0;
      transport.scalarMap(char(s.distValue)) = 0.0;
      testCase.verifyWarningFree( ...
        @()twincat_ads.SymbolBrowser.validate_symbols(transport, s.plcRequiredProbes));
    end

    function validateModeSymbolsPassesWhenPresent(testCase)
      transport = MockAdsTransport();
      s = experiment.RuntimeSymbols.from_defaults();
      transport.scalarMap(char(s.modeResetReq)) = false;
      transport.scalarMap(char(s.modeResetAckCounter)) = uint32(0);
      transport.scalarMap(char(s.hostHeartbeatCounter)) = uint32(0);
      transport.scalarMap(char(s.experimentActive)) = false;
      transport.scalarMap(char(s.loggerFileReleased)) = true;
      transport.scalarMap(char(s.loggerErrorCode)) = uint32(0);
      testCase.verifyWarningFree( ...
        @()twincat_ads.SymbolBrowser.validate_symbols(transport, s.modeRequiredProbes));
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


