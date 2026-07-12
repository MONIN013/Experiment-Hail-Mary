classdef TestModeManagerControl < matlab.unittest.TestCase
  methods (Test)
    function modeFlagsZeroClearsServoLatchInPlcSource(testCase)
      repo_root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
      source = string(fileread(fullfile( ...
        repo_root, "StateMachineControl", "POUs", "FB_ModeManagerCore.TcPOU")));

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "IF NOT servoEnableRequest THEN"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "servoEnableLatched := FALSE;"));
    end

    function mainDelegatesModeStateBeforeDriveUpdate(testCase)
      repo_root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
      source = fileread(fullfile( ...
        repo_root, "StateMachineControl", "POUs", "MAIN.TcPOU"));
      core_call = strfind(source, "fbModeManagerCore(");
      drive_call = strfind(source, "fbMotorStateMachine(");

      testCase.verifyNotEmpty(core_call);
      testCase.verifyNotEmpty(drive_call);
      testCase.verifyLessThan(core_call(1), drive_call(1));
      testCase.verifyThat(string(source), matlab.unittest.constraints.ContainsSubstring( ...
        "modeState := fbModeManagerCore.modeState;"));
      testCase.verifyThat(string(source), matlab.unittest.constraints.ContainsSubstring( ...
        "IF fbModeManagerCore.actions.clearModeFlags THEN"));
    end

    function waitForResetIdleDoesNotRequireLogIndex(testCase)
      plc = MockAdsTransport();
      ctrl_tr = plc;
      symbols = experiment.RuntimeSymbols.from_defaults();
      plc.scalarMap("GVL_SEQ.idx") = uint32(0);
      plc.scalarMap("GVL_MODE.experimentActive") = false;
      plc.scalarMap("GVL_MODE.modeState") = int16(0);
      ctrl = struct( ...
        "experimentActiveSymbol", "GVL_MODE.experimentActive", ...
        "modeStateSymbol", "GVL_MODE.modeState", ...
        "MODESTATE_IDLE", int16(0));
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
      ctrl_tr.set_scalar_read_sequence("GVL_MODE.modeState", [int16(30); int16(0)]);
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
      ctrl_tr.scalarMap("GVL_MODE.modeState") = int16(0);
      ctrl_tr.scalarMap("GVL_MODE.loggerFileReleased") = false;
      ctrl_tr.scalarMap("GVL_MODE.loggerErrorCode") = uint32(hex2dec("E0000001"));
      ctrl_tr.scalarMap("GVL_MODE.hostHeartbeatCounter") = uint32(0);

      testCase.verifyError(@() experiment.ModeManagerControl.abort_experiment( ...
        ctrl_tr, ctrl, experiment.ModeManagerControl.init_heartbeat(ctrl_tr, ctrl, true, 0.001), ...
        struct("timeout_s", 0.05, "poll_period_s", 0.001)), ...
        "experiment:modecontrol:abortLoggerError");
    end

    function waitUntilInactiveCarriesSeenActiveAcrossCalls(testCase)
      ctrl_tr = MockAdsTransport();
      ctrl = seed_ctrl_struct();
      ctrl_tr.set_scalar_read_sequence("GVL_MODE.modeState", [int16(30); int16(40)]);
      ctrl_tr.set_scalar_read_sequence("GVL_MODE.experimentActive", [true; false]);

      [status1, ~, observer_state] = experiment.ModeManagerControl.wait_until_inactive( ...
        ctrl_tr, ctrl, 0.001, [], []);
      testCase.verifyFalse(status1.completed);
      testCase.verifyTrue(status1.seen_active);
      testCase.verifyTrue(observer_state.seen_active);

      [status2, ~, observer_state] = experiment.ModeManagerControl.wait_until_inactive( ...
        ctrl_tr, ctrl, 0.001, [], observer_state);
      testCase.verifyTrue(status2.completed);
      testCase.verifyEqual(string(status2.stop_reason), "done");
      testCase.verifyTrue(observer_state.seen_active);
    end

    function externalHeartbeatMonitorIsCheckedDuringPolling(testCase)
      ctrl_tr = MockAdsTransport();
      ctrl = seed_ctrl_struct();
      calls = containers.Map({'count'}, {0});
      heartbeat_state = experiment.ModeManagerControl.monitor_external_heartbeat( ...
        @() monitor_fails_on_second_call(calls));
      ctrl_tr.scalarMap("GVL_MODE.modeState") = int16(30);
      ctrl_tr.scalarMap("GVL_MODE.experimentActive") = true;

      testCase.verifyError(@() experiment.ModeManagerControl.wait_until_inactive( ...
        ctrl_tr, ctrl, 0.001, heartbeat_state, []), ...
        "test:externalHeartbeatExited");
      testCase.verifyEqual(calls("count"), 2);
    end
  end
end


function monitor_fails_on_second_call(calls)
calls("count") = calls("count") + 1;
if calls("count") >= 2
  error("test:externalHeartbeatExited", "injected monitor failure");
end
end

function ctrl = seed_ctrl_struct()
ctrl = struct( ...
  "modeFlagsSymbol", "GVL_MODE.modeFlags", ...
  "modeStateSymbol", "GVL_MODE.modeState", ...
  "experimentActiveSymbol", "GVL_MODE.experimentActive", ...
  "loggerFileReleasedSymbol", "GVL_MODE.loggerFileReleased", ...
  "loggerErrorCodeSymbol", "GVL_MODE.loggerErrorCode", ...
  "hostHeartbeatCounterSymbol", "GVL_MODE.hostHeartbeatCounter", ...
  "MODESTATE_IDLE", int16(0), ...
  "MODESTATE_RUNNING", int16(30), ...
  "MODESTATE_DONE", int16(40));
end
