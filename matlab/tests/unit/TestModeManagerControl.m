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

    function resolveSymbolsFallsBackToGvlSeqModeFlags(testCase)
      t = MockAdsTransport();
      seed_plc_state(t);
      if isKey(t.scalarMap, "GVL_MODE.modeFlags")
        remove(t.scalarMap, "GVL_MODE.modeFlags");
      end
      symbols = experiment.VirtualMotorSymbols.from_defaults();

      ctrl = experiment.ModeManagerControl.resolve_symbols(t, symbols);

      testCase.verifyEqual(string(ctrl.modeFlagsSymbol), "GVL_SEQ.modeFlags");
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
  end
end

function seed_plc_state(t)
t.scalarMap("GVL_SEQ.modeFlags") = uint32(0);
t.scalarMap("GVL_SEQ.experimentActive") = false;
t.scalarMap("GVL_MODE.modeFlags") = uint32(0);
t.scalarMap("GVL_MODE.experimentActive") = false;
t.scalarMap("GVL_MODE.experimentState") = uint32(0);
t.scalarMap("GVL_SEQ.idx") = uint32(0);
t.scalarMap("GVL_SEQ_LOG.wrIdx") = uint32(0);
t.scalarMap("GVL_SEQ_LOG.overflow") = false;
t.scalarMap("GVL_SEQ_LOG.rdIdx") = uint32(0);
t.scalarMap("GVL_SEQ_LOG.LOG_N") = uint32(16);
t.scalarMap("GVL_SEQ.refValue") = 0.0;
t.scalarMap("GVL_SEQ.ffValue") = 0.0;
t.scalarMap("GVL_SEQ.distValue") = 0.0;
t.scalarMap("GVL_SEQ_LOG.controlInputTap") = 0.0;
t.scalarMap("GVL_SEQ_LOG.positionActTap") = 0.0;
end

function seed_control_state(t)
t.scalarMap("GVL_MODE.modeFlags") = uint32(0);
t.scalarMap("GVL_MODE.experimentActive") = false;
t.scalarMap("GVL_MODE.experimentState") = uint32(0);
end
