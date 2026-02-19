classdef TestVirtualMotorSymbols < matlab.unittest.TestCase
  methods (Test)
    function fromPrefixBuildsExpectedNames(testCase)
      s = experiment.VirtualMotorSymbols.fromPrefix("VirtualMotorCore_Obj1 (Module1).");
      testCase.verifyEqual(string(s.vm_params.m), "VirtualMotorCore_Obj1 (Module1).M");
      testCase.verifyEqual(string(s.vm_params.task_dt_ns), "VirtualMotorCore_Obj1 (Module1).task_dt_ns");
      testCase.verifyEqual(string(s.start), "GVL_VM.experiment_start");
    end

    function fromDefaultsContainsRequiredProbeList(testCase)
      s = experiment.VirtualMotorSymbols.fromDefaults();
      testCase.verifyGreaterThanOrEqual(size(s.required_probes, 1), 6);
    end
  end
end
