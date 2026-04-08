classdef TestVirtualMotorSymbols < matlab.unittest.TestCase
  methods (Test)
    function fromDefaultsOwnsVmSymbolsOnly(testCase)
      s = virtualMotor.Symbols.from_defaults();
      probe_names = string(s.requiredProbes(:, 1));
      testCase.verifyTrue(all(startsWith(probe_names, "VirtualMotorCore_Obj1 (Module1).PlantParameter.")));
      testCase.verifyFalse(any(contains(probe_names, "GVL_SEQ")));
      testCase.verifyFalse(any(contains(probe_names, "GVL_MODE")));
    end
  end
end
