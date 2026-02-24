classdef TestVirtualMotorSymbols < matlab.unittest.TestCase
  methods (Test)
    function fromDefaultsBuildsGvlExpContract(testCase)
      s = experiment.VirtualMotorSymbols.from_defaults();
      testCase.verifyEqual(string(s.reset), "GVL_EXP.reset_req");
      testCase.verifyEqual(string(s.ref_table), "GVL_EXP.ref_table");
      testCase.verifyEqual(string(s.log.log_ref_value), "GVL_EXP_LOG.log_ref_value");
      testCase.verifyGreaterThanOrEqual(size(s.plc_required_probes, 1), 6);
    end

    function vmAndControllerPrefixesBuildExpectedNames(testCase)
      vm = experiment.VirtualMotorSymbols.from_vm_prefix("VirtualMotorCore_Obj1 (Module1).VirtualMotorParameter.");
      cc = experiment.VirtualMotorSymbols.from_controller_prefix("ControllerCore_Obj1 (Module1).");
      testCase.verifyEqual(string(vm.vm_params.m), "VirtualMotorCore_Obj1 (Module1).VirtualMotorParameter.M");
      testCase.verifyEqual(string(cc.controller_params.pid_b0), "ControllerCore_Obj1 (Module1).PIDParams.notch_b0");
      testCase.verifyEqual(string(cc.controller_params.lead_b0), "ControllerCore_Obj1 (Module1).LeadParams.notch_b0");
      testCase.verifyEqual(string(cc.controller_params.enable_reso), "ControllerCore_Obj1 (Module1).EnableParams.enable_reso");
    end
  end
end
