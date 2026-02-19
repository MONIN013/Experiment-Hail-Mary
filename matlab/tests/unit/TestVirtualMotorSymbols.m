classdef TestVirtualMotorSymbols < matlab.unittest.TestCase
  methods (Test)
    function fromPrefixBuildsExpectedNames(testCase)
      s = ehm.contracts.VirtualMotorSymbols.fromPrefix("VirtualMotorCore_Obj1 (Module1).");
      testCase.verifyEqual(string(s.vmParams.M), "VirtualMotorCore_Obj1 (Module1).M");
      testCase.verifyEqual(string(s.vmParams.task_dt_ns), "VirtualMotorCore_Obj1 (Module1).task_dt_ns");
      testCase.verifyEqual(string(s.start), "GVL_VM.experiment_start");
    end

    function fromDefaultsContainsRequiredProbeList(testCase)
      s = ehm.contracts.VirtualMotorSymbols.fromDefaults();
      testCase.verifyGreaterThanOrEqual(size(s.requiredProbes, 1), 6);
    end
  end
end
