classdef TestVirtualMotorSymbols < matlab.unittest.TestCase
  methods (Test)
    function fromDefaultsExcludesDriverSymbols(testCase)
      s = experiment.VirtualMotorSymbols.from_defaults();
      testCase.verifyTrue(isstruct(s.log));
      testCase.verifyTrue(isempty(fieldnames(s.log)));
      probe_names = string(s.plcRequiredProbes(:, 1));
      testCase.verifyFalse(any(contains(probe_names, "SEQ_LOG")));
      testCase.verifyFalse(any(probe_names == "GVL_DRV.controlInput"));
      testCase.verifyFalse(any(probe_names == "GVL_DRV.positionRel"));
    end
  end
end
