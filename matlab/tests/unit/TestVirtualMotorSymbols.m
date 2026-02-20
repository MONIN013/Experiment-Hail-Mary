classdef TestVirtualMotorSymbols < matlab.unittest.TestCase
  methods (Test)
    function from_prefix_builds_expected_names(testCase)
      s = experiment.VirtualMotorSymbols.from_prefix("VirtualMotorCore_Obj1 (Module1).");
      testCase.verifyEqual(string(s.vm_params.m), "VirtualMotorCore_Obj1 (Module1).M");
      testCase.verifyEqual(string(s.vm_params.task_dt_ns), "VirtualMotorCore_Obj1 (Module1).task_dt_ns");
      testCase.verifyEqual(string(s.start), "GVL_VM.experiment_start");
    end

    function from_defaults_contains_required_probe_list(testCase)
      s = experiment.VirtualMotorSymbols.from_defaults();
      testCase.verifyGreaterThanOrEqual(size(s.required_probes, 1), 6);
    end
  end
end
