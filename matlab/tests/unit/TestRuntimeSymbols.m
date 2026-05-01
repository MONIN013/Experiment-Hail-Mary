classdef TestRuntimeSymbols < matlab.unittest.TestCase
  methods (Test)
    function fromDefaultsExcludesDriverAndVmSymbols(testCase)
      s = experiment.RuntimeSymbols.from_defaults();
      testCase.verifyTrue(isstruct(s.log));
      testCase.verifyTrue(isempty(fieldnames(s.log)));
      probe_names = string(s.plcRequiredProbes(:, 1));
      testCase.verifyFalse(any(contains(probe_names, "SEQ_LOG")));
      testCase.verifyFalse(any(probe_names == "GVL_DRV.controlInput"));
      testCase.verifyFalse(any(probe_names == "GVL_DRV.positionRel"));
      testCase.verifyFalse(any(contains(probe_names, "VirtualMotorCore_Obj1")));
      testCase.verifyFalse(any(startsWith(probe_names, "GVL_MODE.")));

      mode_probe_names = string(s.modeRequiredProbes(:, 1));
      testCase.verifyTrue(any(mode_probe_names == "GVL_MODE.experimentActive"));
    end
  end
end
