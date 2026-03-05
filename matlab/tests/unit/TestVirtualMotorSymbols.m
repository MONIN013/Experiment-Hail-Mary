classdef TestVirtualMotorSymbols < matlab.unittest.TestCase
  methods (Test)
    function fromDefaultsUsesDriverSymbols(testCase)
      s = experiment.VirtualMotorSymbols.from_defaults();
      testCase.verifyEqual(string(s.controlInput), "GVL_DRV.controlInput");
      testCase.verifyEqual(string(s.positionActLog), "GVL_DRV.positionRel");
      testCase.verifyTrue(isstruct(s.log));
      testCase.verifyTrue(isempty(fieldnames(s.log)));
      probe_names = string(s.plcRequiredProbes(:, 1));
      testCase.verifyFalse(any(contains(probe_names, "SEQ_LOG")));
    end
  end
end
