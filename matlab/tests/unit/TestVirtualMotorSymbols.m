classdef TestVirtualMotorSymbols < matlab.unittest.TestCase
  methods (Test)
    function fromDefaultsBuildsGvlExpContract(testCase)
      s = experiment.VirtualMotorSymbols.from_defaults();
      testCase.verifyEqual(string(s.reset), "GVL_SEQ.resetReq");
      testCase.verifyEqual(string(s.modeResetReq), "GVL_MODE.resetReq");
      testCase.verifyEqual(string(s.modeResetAckCounter), "GVL_MODE.resetAckCounter");
      testCase.verifyEqual(string(s.experimentState), "GVL_MODE.experimentState");
      testCase.verifyEqual(string(s.modeFlagsCandidates(:)), ["GVL_MODE.modeFlags"]);
      testCase.verifyEqual(string(s.refTable), "GVL_SEQ.refTable");
      testCase.verifyEqual(string(s.log.logRefValue), "GVL_SEQ_LOG.logRefValue");
      testCase.verifyGreaterThanOrEqual(size(s.plcRequiredProbes, 1), 6);
    end

    function vmAndControllerPrefixesBuildExpectedNames(testCase)
      vm = experiment.VirtualMotorSymbols.from_vm_prefix("VirtualMotorCore_Obj1 (Module1).VirtualMotorParameter.");
      cc = experiment.VirtualMotorSymbols.from_controller_prefix("ControllerCore_Obj1 (Module1).");
      testCase.verifyEqual(string(vm.vmParams.m), "VirtualMotorCore_Obj1 (Module1).VirtualMotorParameter.mass");
      testCase.verifyEqual(string(cc.controllerParams.pidB0), "ControllerCore_Obj1 (Module1).PIDParams.pidB0");
      testCase.verifyEqual(string(cc.controllerParams.leadB0), "ControllerCore_Obj1 (Module1).LeadParams.leadB0");
      testCase.verifyEqual(string(cc.controllerParams.enableReso), "ControllerCore_Obj1 (Module1).EnableParams.enableReso");
    end
  end
end


