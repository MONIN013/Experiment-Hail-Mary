classdef TestSymbolBrowserContract < matlab.unittest.TestCase
  methods (Test)
    function validateRequiredSymbolsReportsMissing(testCase)
      transport = MockAdsTransport();
      symbols = experiment.VirtualMotorSymbols.from_defaults();
      testCase.verifyError( ...
        @()twincat_ads.SymbolBrowser.validate_symbols(transport, symbols.plc_required_probes), ...
        "twincat_ads:symbol:notFound");
    end

    function validateRequiredSymbolsPassesWhenPresent(testCase)
      transport = MockAdsTransport();
      s = experiment.VirtualMotorSymbols.from_defaults();
      transport.scalarMap(char(s.reset)) = false;
      transport.scalarMap(char(s.experiment_active)) = false;
      transport.scalarMap(char(s.table_len)) = uint32(0);
      transport.scalarMap(char(s.idx)) = uint32(0);
      transport.scalarMap(char(s.ref_value)) = 0.0;
      transport.scalarMap(char(s.ff_value)) = 0.0;
      transport.scalarMap(char(s.control_input)) = 0.0;
      transport.scalarMap(char(s.target_torque)) = 0.0;
      transport.scalarMap(char(s.position_act_log)) = 0.0;
      transport.scalarMap(char(s.log.wr_idx)) = uint32(0);
      transport.scalarMap(char(s.log.rd_idx)) = uint32(0);
      transport.scalarMap(char(s.log.overflow)) = false;
      testCase.verifyWarningFree( ...
        @()twincat_ads.SymbolBrowser.validate_symbols(transport, s.plc_required_probes));
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
