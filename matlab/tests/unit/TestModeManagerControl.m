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

    function abortExperimentClearsModeFlagsAndWaitsRelease(testCase)
      ctrl_tr = MockAdsTransport();
      ctrl = seed_ctrl_struct();
      ctrl_tr.scalarMap("GVL_MODE.modeFlags") = uint16(3);
      ctrl_tr.set_scalar_read_sequence("GVL_MODE.experimentActive", [true; false]);
      ctrl_tr.set_scalar_read_sequence("GVL_MODE.loggerFileReleased", [false; true]);
      ctrl_tr.scalarMap("GVL_MODE.loggerErrorCode") = uint32(0);
      ctrl_tr.scalarMap("GVL_MODE.hostHeartbeatCounter") = uint32(0);

      [aborted, diag, ~] = experiment.ModeManagerControl.abort_experiment( ...
        ctrl_tr, ctrl, experiment.ModeManagerControl.init_heartbeat(ctrl_tr, ctrl, true, 0.001), ...
        struct("timeout_s", 0.05, "poll_period_s", 0.001));

      testCase.verifyTrue(aborted);
      testCase.verifyEqual(ctrl_tr.scalarMap("GVL_MODE.modeFlags"), uint16(0));
      testCase.verifyTrue(diag.stop_confirmed);
      testCase.verifyTrue(diag.file_released);
    end

    function abortExperimentErrorsOnLoggerFailure(testCase)
      ctrl_tr = MockAdsTransport();
      ctrl = seed_ctrl_struct();
      ctrl_tr.scalarMap("GVL_MODE.modeFlags") = uint16(3);
      ctrl_tr.scalarMap("GVL_MODE.experimentActive") = false;
      ctrl_tr.scalarMap("GVL_MODE.loggerFileReleased") = false;
      ctrl_tr.scalarMap("GVL_MODE.loggerErrorCode") = uint32(hex2dec("E0000001"));
      ctrl_tr.scalarMap("GVL_MODE.hostHeartbeatCounter") = uint32(0);

      testCase.verifyError(@() experiment.ModeManagerControl.abort_experiment( ...
        ctrl_tr, ctrl, experiment.ModeManagerControl.init_heartbeat(ctrl_tr, ctrl, true, 0.001), ...
        struct("timeout_s", 0.05, "poll_period_s", 0.001)), ...
        "experiment:modecontrol:abortLoggerError");
    end
  end
end

function ctrl = seed_ctrl_struct()
ctrl = struct( ...
  "modeFlagsSymbol", "GVL_MODE.modeFlags", ...
  "experimentActiveSymbol", "GVL_MODE.experimentActive", ...
  "loggerFileReleasedSymbol", "GVL_MODE.loggerFileReleased", ...
  "loggerErrorCodeSymbol", "GVL_MODE.loggerErrorCode", ...
  "hostHeartbeatCounterSymbol", "GVL_MODE.hostHeartbeatCounter", ...
  "MODEF_RESET_REQ", uint32(hex2dec("0004")));
end
