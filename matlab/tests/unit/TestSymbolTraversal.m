classdef TestSymbolTraversal < matlab.unittest.TestCase
  methods (Test)
    function extract_name_falls_back_without_instance_path(testCase)
      symbol = MockDotNetSymbol("InstanceName", "GVL.fallbackName", "TypeName", "INT", "Size", int32(4));
      symbols = MockDotNetCollection({symbol});

      [names, types, sizes] = twincat_ads.SymbolBrowser.collect_symbols_for_test(symbols, false);

      testCase.verifyEqual(names, "GVL.fallbackName");
      testCase.verifyEqual(types, "INT");
      testCase.verifyEqual(sizes, int32(4));
    end

    function keepsAllRowsWhenTopLevelFalse(testCase)
      nested = MockDotNetSymbol("Name", "GVL_PARENT.child", "TypeName", "REAL", "Size", int32(8));
      topLevel = MockDotNetSymbol( ...
        "Name", "GVL_PARENT", ...
        "TypeName", "STRUCT", ...
        "Size", int32(16), ...
        "SubSymbols", MockDotNetCollection({nested}));
      symbols = MockDotNetCollection({topLevel});

      [names, ~, ~] = twincat_ads.SymbolBrowser.collect_symbols_for_test(symbols, false);

      testCase.verifyEqual(names, ["GVL_PARENT"; "GVL_PARENT.child"]);
    end

    function excludesDottedNamesWhenTopLevelTrue(testCase)
      nested = MockDotNetSymbol("Name", "GVL_PARENT.child", "TypeName", "REAL", "Size", int32(8));
      topLevel = MockDotNetSymbol( ...
        "Name", "GVL_PARENT", ...
        "TypeName", "STRUCT", ...
        "Size", int32(16), ...
        "SubSymbols", MockDotNetCollection({nested}));
      symbols = MockDotNetCollection({topLevel});

      [names, ~, ~] = twincat_ads.SymbolBrowser.collect_symbols_for_test(symbols, true);

      testCase.verifyEqual(names, "GVL_PARENT");
    end

    function removesDuplicateNamesInStableOrder(testCase)
      first = MockDotNetSymbol("Name", "GVL.dup", "TypeName", "INT", "Size", int32(4));
      duplicate = MockDotNetSymbol("Name", "GVL.dup", "TypeName", "REAL", "Size", int32(8));
      third = MockDotNetSymbol("Name", "GVL.unique", "TypeName", "BOOL", "Size", int32(1));
      symbols = MockDotNetCollection({first, duplicate, third});

      [names, types, sizes] = twincat_ads.SymbolBrowser.collect_symbols_for_test(symbols, false);

      testCase.verifyEqual(names, ["GVL.dup"; "GVL.unique"]);
      testCase.verifyEqual(types, ["INT"; "BOOL"]);
      testCase.verifyEqual(sizes, int32([4; 1]));
    end

    function doesNotExpandArrayElementsWhenTopLevelFalse(testCase)
      elem0 = MockDotNetSymbol("Name", "GVL.arr[0]", "TypeName", "LREAL", "Size", int32(8));
      elem1 = MockDotNetSymbol("Name", "GVL.arr[1]", "TypeName", "LREAL", "Size", int32(8));
      arraySymbol = MockDotNetSymbol( ...
        "Name", "GVL.arr", ...
        "TypeName", "ARRAY [0..1] OF LREAL", ...
        "Size", int32(16), ...
        "SubSymbols", MockDotNetCollection({elem0, elem1}));
      symbols = MockDotNetCollection({arraySymbol});

      [names, types, sizes] = twincat_ads.SymbolBrowser.collect_symbols_for_test(symbols, false);

      testCase.verifyEqual(names, "GVL.arr");
      testCase.verifyEqual(types, "ARRAY [0..1] OF LREAL");
      testCase.verifyEqual(sizes, int32(16));
    end
  end
end
