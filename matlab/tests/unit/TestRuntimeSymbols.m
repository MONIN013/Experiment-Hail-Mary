classdef TestRuntimeSymbols < matlab.unittest.TestCase
  methods (Test)
    function defaultsExcludeDriverAndVmSymbols(testCase)
      s=experiment.RuntimeSymbols.from_defaults();names=string(s.plcRequiredProbes(:,1));
      testCase.verifyFalse(any(contains(names,"SEQ_LOG")));testCase.verifyFalse(any(startsWith(names,"GVL_MODE.")));
      testCase.verifyTrue(any(string(s.modeRequiredProbes(:,1))=="GVL_MODE.experimentActive"));
    end
    function controllerContractHasPackedCountsAndTwoHigs(testCase)
      s=experiment.RuntimeSymbols.from_controller_prefix("Controller.");p=s.controllerParams;
      testCase.verifyEqual(p.coefficients,"Controller.SosCoefficients");
      testCase.verifyEqual(p.sectionCount,"Controller.SosSectionCount");
      testCase.verifyEqual(p.higsLpEnabled,"Controller.HigsLpEnabled");
      testCase.verifyEqual(p.higsIOmegaTs,"Controller.HigsIOmegaTs");
      testCase.verifyEqual(p.iPreSectionCount,"Controller.IPreSectionCount");
      testCase.verifyEqual(p.applyRevision,"Controller.SosApplyRevision");
      testCase.verifyEqual(p.higsLpInput,"Controller.Outputs.higsLpInput");
      testCase.verifyEqual(p.higsIMode,"Controller.Outputs.higsIMode");
      names=string(s.controllerRequiredProbes(:,1));
      testCase.verifyTrue(any(names=="Controller.SosCoefficients[0]"));
      testCase.verifyFalse(any(contains(names,"HigsEnabled")));
    end
  end
end
