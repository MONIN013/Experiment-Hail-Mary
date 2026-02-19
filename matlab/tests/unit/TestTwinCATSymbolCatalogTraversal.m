classdef TestTwinCATSymbolCatalogTraversal < matlab.unittest.TestCase
  methods (Test)
    function extractNameFallsBackWithoutInstancePath(testCase)
      symbol = MockDotNetSymbol("InstanceName", "GVL.fallbackName", "TypeName", "INT", "Size", int32(4));
      symbols = MockDotNetCollection({symbol});

      [names, types, sizes] = ehm.adapters.twincat.TwinCATSymbolCatalog.collectSymbolsForTest(symbols, false);

      testCase.verifyEqual(names, "GVL.fallbackName");
      testCase.verifyEqual(types, "INT");
      testCase.verifyEqual(sizes, int32(4));
    end

    function recursivelyCollectsSubSymbolsWhenTopLevelFalse(testCase)
      child = MockDotNetSymbol("Name", "GVL.parent.child", "TypeName", "REAL", "Size", int32(8));
      parent = MockDotNetSymbol( ...
        "Name", "GVL.parent", ...
        "TypeName", "STRUCT", ...
        "Size", int32(16), ...
        "SubSymbols", MockDotNetCollection({child}));
      symbols = MockDotNetCollection({parent});

      [names, ~, ~] = ehm.adapters.twincat.TwinCATSymbolCatalog.collectSymbolsForTest(symbols, false);

      testCase.verifyEqual(names, ["GVL.parent"; "GVL.parent.child"]);
    end

    function keepsDepthOneOnlyWhenTopLevelTrue(testCase)
      child = MockDotNetSymbol("Name", "GVL.parent.child", "TypeName", "REAL", "Size", int32(8));
      parent = MockDotNetSymbol( ...
        "Name", "GVL.parent", ...
        "TypeName", "STRUCT", ...
        "Size", int32(16), ...
        "SubSymbols", MockDotNetCollection({child}));
      symbols = MockDotNetCollection({parent});

      [names, ~, ~] = ehm.adapters.twincat.TwinCATSymbolCatalog.collectSymbolsForTest(symbols, true);

      testCase.verifyEqual(names, "GVL.parent");
    end

    function removesDuplicateNamesInStableOrder(testCase)
      first = MockDotNetSymbol("Name", "GVL.dup", "TypeName", "INT", "Size", int32(4));
      duplicate = MockDotNetSymbol("Name", "GVL.dup", "TypeName", "REAL", "Size", int32(8));
      third = MockDotNetSymbol("Name", "GVL.unique", "TypeName", "BOOL", "Size", int32(1));
      symbols = MockDotNetCollection({first, duplicate, third});

      [names, types, sizes] = ehm.adapters.twincat.TwinCATSymbolCatalog.collectSymbolsForTest(symbols, false);

      testCase.verifyEqual(names, ["GVL.dup"; "GVL.unique"]);
      testCase.verifyEqual(types, ["INT"; "BOOL"]);
      testCase.verifyEqual(sizes, int32([4; 1]));
    end
  end
end
