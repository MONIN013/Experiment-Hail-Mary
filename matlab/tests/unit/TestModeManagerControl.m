classdef TestModeManagerControl < matlab.unittest.TestCase
  methods (Test)
    function waitForResetIdleDoesNotRequireLogIndex(testCase)
      plc = MockAdsTransport();
      ctrl_tr = plc;
      symbols = experiment.VirtualMotorSymbols.from_defaults();
      plc.scalarMap("GVL_SEQ.idx") = uint32(0);
      plc.scalarMap("GVL_MODE.experimentActive") = false;
      ctrl = struct("experimentActiveSymbol", "GVL_MODE.experimentActive");
      [ready, diag, ~] = experiment.ModeManagerControl.wait_for_reset_idle(plc, ctrl_tr, symbols, ctrl, 0.02, []);
      testCase.verifyTrue(ready);
      testCase.verifyEqual(diag.idx, 0);
      testCase.verifyFalse(isfield(diag, "wr_idx"));
    end
  end
end
