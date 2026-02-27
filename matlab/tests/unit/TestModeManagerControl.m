classdef TestModeManagerControl < matlab.unittest.TestCase
  methods (Test)
    function resolveSymbolsPrefersGvlMode(testCase)
      t = MockAdsTransport();
      seed_plc_state(t);
      symbols = experiment.VirtualMotorSymbols.from_defaults();

      ctrl = experiment.ModeManagerControl.resolve_symbols(t, symbols);

      testCase.verifyEqual(string(ctrl.modeFlagsSymbol), "GVL_MODE.modeFlags");
      testCase.verifyEqual(string(ctrl.experimentStateSymbol), "GVL_MODE.experimentState");
    end

    function resolveSymbolsErrorsWhenGvlModeModeFlagsMissing(testCase)
      t = MockAdsTransport();
      seed_plc_state(t);
      if isKey(t.scalarMap, "GVL_MODE.modeFlags")
        remove(t.scalarMap, "GVL_MODE.modeFlags");
      end
      symbols = experiment.VirtualMotorSymbols.from_defaults();

      testCase.verifyError(@() experiment.ModeManagerControl.resolve_symbols(t, symbols), ...
        "experiment:modecontrol:invalidConfig");
    end

    function modeflagsTypeFallsBackToU32(testCase)
      s = struct("u32", "System.UInt32");
      actual = experiment.ModeManagerControl.modeflags_type(s);
      testCase.verifyEqual(string(actual), "System.UInt32");
    end

    function waitUntilDoneUsesExperimentState(testCase)
      plc = MockAdsTransport();
      ctrl_t = MockAdsTransport();
      seed_plc_state(plc);
      seed_control_state(ctrl_t);
      symbols = experiment.VirtualMotorSymbols.from_defaults();
      ctrl = experiment.ModeManagerControl.resolve_symbols(ctrl_t, symbols);
      ctrl_t.set_scalar_read_sequence("GVL_MODE.experimentState", uint32([0; 1; 2; 3]));

      done = experiment.ModeManagerControl.wait_until_done(ctrl_t, plc, symbols, ctrl, 0.05);

      joined = strjoin(ctrl_t.operations, "|");
      testCase.verifyTrue(done);
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("read_scalar:GVL_MODE.experimentState"));
    end

    function waitUntilDoneFallsBackToExperimentActive(testCase)
      plc = MockAdsTransport();
      ctrl_t = MockAdsTransport();
      seed_plc_state(plc);
      seed_control_state(ctrl_t);
      remove(ctrl_t.scalarMap, "GVL_MODE.experimentState");
      symbols = experiment.VirtualMotorSymbols.from_defaults();
      ctrl = experiment.ModeManagerControl.resolve_symbols(ctrl_t, symbols);
      ctrl_t.set_scalar_read_sequence("GVL_MODE.experimentActive", [false; false; true; false]);

      done = experiment.ModeManagerControl.wait_until_done(ctrl_t, plc, symbols, ctrl, 0.05);

      testCase.verifyTrue(done);
    end

    function waitForResetIdlePrefersControlExperimentActive(testCase)
      plc = MockAdsTransport();
      ctrl_t = MockAdsTransport();
      seed_plc_state(plc);
      seed_control_state(ctrl_t);
      symbols = experiment.VirtualMotorSymbols.from_defaults();
      ctrl = experiment.ModeManagerControl.resolve_symbols(ctrl_t, symbols);
      plc.scalarMap("GVL_SEQ_LOG.wrIdx") = uint32(0);
      plc.scalarMap("GVL_SEQ.idx") = uint32(0);
      ctrl_t.set_scalar_read_sequence("GVL_MODE.experimentActive", [true; false]);

      [ready, diag] = experiment.ModeManagerControl.wait_for_reset_idle(plc, ctrl_t, symbols, ctrl, 0.05);

      testCase.verifyTrue(ready);
      testCase.verifyFalse(diag.experiment_active);
    end

    function waitUntilDoneTicksHeartbeat(testCase)
      plc = MockAdsTransport();
      ctrl_t = MockAdsTransport();
      seed_plc_state(plc);
      seed_control_state(ctrl_t);
      symbols = experiment.VirtualMotorSymbols.from_defaults();
      ctrl = experiment.ModeManagerControl.resolve_symbols(ctrl_t, symbols);
      ctrl_t.set_scalar_read_sequence("GVL_MODE.experimentState", uint32([0; 1; 2; 3]));
      hb = experiment.ModeManagerControl.init_heartbeat(ctrl_t, ctrl, true, 1e-6);

      [done, ~] = experiment.ModeManagerControl.wait_until_done( ...
        ctrl_t, plc, symbols, ctrl, 0.05, hb);

      testCase.verifyTrue(done);
      joined = strjoin(ctrl_t.operations, "|");
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_MODE.hostHeartbeatCounter"));
    end

    function requestResetAndWaitAckSucceeds(testCase)
      ctrl_t = MockAdsTransport();
      seed_control_state(ctrl_t);
      symbols = experiment.VirtualMotorSymbols.from_defaults();
      ctrl = experiment.ModeManagerControl.resolve_symbols(ctrl_t, symbols);

      [acked, diag] = experiment.ModeManagerControl.request_reset_and_wait_ack(ctrl_t, ctrl, 0.05);

      testCase.verifyTrue(acked);
      testCase.verifyGreaterThan(diag.counter_after, diag.counter_before);
    end

    function requestResetAndWaitAckTimesOutWithoutAck(testCase)
      ctrl_t = MockAdsTransport();
      seed_control_state(ctrl_t);
      ctrl_t.autoResetAck = false;
      symbols = experiment.VirtualMotorSymbols.from_defaults();
      ctrl = experiment.ModeManagerControl.resolve_symbols(ctrl_t, symbols);

      [acked, diag] = experiment.ModeManagerControl.request_reset_and_wait_ack(ctrl_t, ctrl, 0.01);

      testCase.verifyFalse(acked);
      testCase.verifyEqual(diag.counter_after, diag.counter_before);
    end
  end
end

function seed_plc_state(t)
t.scalarMap("GVL_SEQ.experimentActive") = false;
t.scalarMap("GVL_MODE.modeFlags") = uint32(0);
t.scalarMap("GVL_MODE.experimentActive") = false;
t.scalarMap("GVL_MODE.experimentState") = uint32(0);
t.scalarMap("GVL_MODE.resetReq") = false;
t.scalarMap("GVL_MODE.resetAckCounter") = uint32(0);
t.scalarMap("GVL_MODE.hostHeartbeatCounter") = uint32(0);
t.scalarMap("GVL_SEQ.idx") = uint32(0);
t.scalarMap("GVL_SEQ_LOG.wrIdx") = uint32(0);
t.scalarMap("GVL_SEQ_LOG.overflow") = false;
t.scalarMap("GVL_SEQ_LOG.rdIdx") = uint32(0);
t.scalarMap("GVL_SEQ_LOG.LOG_N") = uint32(16);
t.scalarMap("GVL_SEQ.refValue") = 0.0;
t.scalarMap("GVL_SEQ.ffValue") = 0.0;
t.scalarMap("GVL_SEQ.distValue") = 0.0;
t.scalarMap("GVL_SEQ_LOG.controlInputTap") = 0.0;
t.scalarMap("GVL_SEQ_LOG.positionRelTap") = 0.0;
end

function seed_control_state(t)
t.scalarMap("GVL_MODE.modeFlags") = uint32(0);
t.scalarMap("GVL_MODE.experimentActive") = false;
t.scalarMap("GVL_MODE.experimentState") = uint32(0);
t.scalarMap("GVL_MODE.resetReq") = false;
t.scalarMap("GVL_MODE.resetAckCounter") = uint32(0);
t.scalarMap("GVL_MODE.hostHeartbeatCounter") = uint32(0);
end


