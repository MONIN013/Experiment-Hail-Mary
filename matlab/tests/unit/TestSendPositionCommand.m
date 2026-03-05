classdef TestSendPositionCommand < matlab.unittest.TestCase
  methods (Test)
    function basicFlowWritesExpectedSymbols(testCase)
      plc = MockAdsTransport();
      seed_state(plc);
      plc.set_scalar_read_sequence("GVL_MODE.experimentActive", [false; true; false]);

      out = experiment.send_position_command( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "ref_profile", [0.1; 0.2; 0.3], ...
        "plc_transport", plc, ...
        "validate_symbols", false, ...
        "done_timeout_s", 0.05, ...
        "reset_timeout_s", 0.05);

      joined = strjoin(plc.operations, "|");
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_array:GVL_SEQ.refTable"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_MODE.modeFlags"));
      testCase.verifyTrue(out.host.done);
      testCase.verifyEqual(string(out.logger.file_path), "C:\ExperimentData\experiment_logger.bin");
      testCase.verifyFalse(isfield(out.raw, "log_overflow") && logical(out.raw.log_overflow));
    end

    function defaultsFillFfAndDistProfiles(testCase)
      plc = MockAdsTransport();
      seed_state(plc);
      out = experiment.send_position_command( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "ref_profile", [0.5; 0.6], ...
        "plc_transport", plc, ...
        "validate_symbols", false, ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0);

      testCase.verifyEqual(out.cmd.ff_profile, [0; 0]);
      testCase.verifyEqual(out.cmd.dist_profile, [0; 0]);
    end
  end
end

function seed_state(t)
t.scalarMap("GVL_MODE.modeFlags") = uint16(0);
t.scalarMap("GVL_MODE.resetReq") = false;
t.scalarMap("GVL_MODE.resetAckCounter") = uint32(0);
t.scalarMap("GVL_MODE.hostHeartbeatCounter") = uint32(0);
t.scalarMap("GVL_MODE.experimentActive") = false;
t.scalarMap("GVL_SEQ.idx") = uint32(0);
t.scalarMap("GVL_DRV.positionRel") = 0.0;
t.scalarMap("GVL_DRV.controlInput") = 0.0;
end
