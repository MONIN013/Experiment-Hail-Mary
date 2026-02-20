classdef TestSymbolBrowserContract < matlab.unittest.TestCase
  methods (Test)
    function validateRequiredSymbolsReportsMissing(testCase)
      transport = MockAdsTransport();
      symbols = experiment.VirtualMotorSymbols.from_defaults();
      testCase.verifyError( ...
        @()twincat_ads.SymbolBrowser.validate_symbols(transport, symbols.required_probes), ...
        "twincat_ads:symbol:notFound");
    end

    function validateRequiredSymbolsPassesWhenPresent(testCase)
      transport = MockAdsTransport();
      s = experiment.VirtualMotorSymbols.from_defaults();
      transport.scalarMap(char(s.start)) = false;
      transport.scalarMap(char(s.reset)) = false;
      transport.scalarMap(char(s.current_in)) = 0.0;
      transport.scalarMap(char(s.position_out)) = 0.0;
      transport.scalarMap(char(s.velocity_out)) = 0.0;
      transport.scalarMap(char(s.cmd_len)) = uint32(0);
      transport.scalarMap(char(s.cmd_idx)) = uint32(0);
      transport.scalarMap(char(s.log.wr_idx)) = uint32(0);
      transport.scalarMap(char(s.log.overflow)) = false;
      testCase.verifyWarningFree( ...
        @()twincat_ads.SymbolBrowser.validate_symbols(transport, s.required_probes));
    end

    function collectSymbolsSkipsRowsWithMissingName(testCase)
      symbolMissingName = MockDotNetSymbol("TypeName", "INT", "Size", int32(4));
      symbolValid = MockDotNetSymbol("Name", "GVL.mySignal", "TypeName", "REAL", "Size", int32(4));
      symbols = MockDotNetCollection({symbolMissingName, symbolValid});

      testCase.verifyWarningFree(@()twincat_ads.SymbolBrowser.collect_symbols_for_test(symbols, false));
      [names, types, sizes] = twincat_ads.SymbolBrowser.collect_symbols_for_test(symbols, false);

      testCase.verifyEqual(names, "GVL.mySignal");
      testCase.verifyEqual(types, "REAL");
      testCase.verifyEqual(sizes, int32(4));
    end
  end
end
