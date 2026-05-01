classdef TestExperimentRunner < matlab.unittest.TestCase
  methods (Test)
    function runOrchestratesAndReturnsSnakeCaseRaw(testCase)
      seq = MockAdsTransport();
      ctrl = MockAdsTransport();
      module = MockAdsTransport();
      seed_seq(seq);
      seed_ctrl(ctrl);
      seed_logger_status(module, [false; true], [uint32(7); uint32(10)]);
      conn = experiment.ConnectionManager.from_transports(seq, ctrl, module);
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2; 0.3], ...
        "controller_prefix", "CustomController.", ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "read_logs", false, ...
        "validate_symbols", false);
      out = experiment.ExperimentRunner.run(conn, cfg);
      testCase.verifyTrue(isfield(out.raw, "ref_value"));
      testCase.verifyEqual(out.raw.ref_value, zeros(0, 1));
      testCase.verifyFalse(isfield(out, "eval"));
      testCase.verifyTrue(out.logger.file_released);
      testCase.verifyTrue(out.logger.status_available);
      testCase.verifyFalse(out.logger.ready_before);
      testCase.verifyTrue(out.logger.ready_after);
      testCase.verifyEqual(out.logger.records_before, uint32(7));
      testCase.verifyEqual(out.logger.records_after, uint32(10));
      testCase.verifyTrue(any(contains(seq.operations, "write_array:GVL_SEQ.refTable")));
      testCase.verifyTrue(any(contains(module.operations, "write_scalar:CustomController.PIDParams.pidB0")));
      testCase.verifyFalse(any(contains(module.operations, "PlantParameter.")));
    end

    function runsWithoutModuleWhenControllerWritesDisabled(testCase)
      seq = MockAdsTransport();
      ctrl = MockAdsTransport();
      seed_seq(seq);
      seed_ctrl(ctrl);
      conn = experiment.ConnectionManager.from_transports(seq, ctrl);
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2], ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "read_logs", false, ...
        "validate_symbols", false, ...
        "write_controller_params", false);
      out = experiment.ExperimentRunner.run(conn, cfg);
      testCase.verifyFalse(out.host.done);
      testCase.verifyEqual(out.metrics.sample_count, 0);
      testCase.verifyFalse(out.logger.status_available);
      testCase.verifyFalse(out.logger.ready_before);
      testCase.verifyEqual(out.logger.records_before, uint32(0));
    end

    function abortConditionStopsRunWithoutError(testCase)
      seq = MockAdsTransport();
      ctrl = MockAdsTransport();
      module = MockAdsTransport();
      seed_seq(seq);
      seed_ctrl(ctrl);
      ctrl.set_scalar_read_sequence("GVL_MODE.experimentState", [uint32(1); uint32(1); uint32(2); uint32(2); uint32(0)]);
      ctrl.set_scalar_read_sequence("GVL_MODE.experimentActive", [false; true; true; false]);
      ctrl.set_scalar_read_sequence("GVL_MODE.loggerFileReleased", [false; true]);
      conn = experiment.ConnectionManager.from_transports(seq, ctrl, module);
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", true, ...
        "done_timeout_s", 0.05, ...
        "abort_check_period_s", 0.001, ...
        "read_logs", false, ...
        "validate_symbols", false);

      out = experiment.ExperimentRunner.run(conn, cfg, ...
        "abort_condition", @(context) context.elapsed_s >= 0);

      testCase.verifyFalse(out.host.done);
      testCase.verifyTrue(out.host.abort_requested);
      testCase.verifyEqual(string(out.host.stop_reason), "abort");
      testCase.verifyTrue(any(contains(ctrl.operations, "write_scalar:GVL_MODE.modeFlags")));
    end

    function naturalCompletionAcrossPollingWindowsReturnsDone(testCase)
      seq = MockAdsTransport();
      ctrl = MockAdsTransport();
      module = MockAdsTransport();
      seed_seq(seq);
      seed_ctrl(ctrl);
      ctrl.set_scalar_read_sequence("GVL_MODE.experimentState", [uint32(1); uint32(1); uint32(2); uint32(0)]);
      ctrl.set_scalar_read_sequence("GVL_MODE.experimentActive", [false; true; false]);
      ctrl.scalarMap("GVL_MODE.loggerFileReleased") = true;
      conn = experiment.ConnectionManager.from_transports(seq, ctrl, module);
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2], ...
        "wait_for_done", true, ...
        "done_timeout_s", 0.05, ...
        "abort_check_period_s", 0.001, ...
        "read_logs", false, ...
        "validate_symbols", false);

      out = experiment.ExperimentRunner.run(conn, cfg);

      testCase.verifyTrue(out.host.done);
      testCase.verifyFalse(out.host.timed_out);
      testCase.verifyEqual(string(out.host.stop_reason), "done");
    end

    function timeoutStillErrors(testCase)
      seq = MockAdsTransport();
      ctrl = MockAdsTransport();
      module = MockAdsTransport();
      seed_seq(seq);
      seed_ctrl(ctrl);
      ctrl.set_scalar_read_sequence("GVL_MODE.experimentState", [uint32(1); uint32(1); uint32(2); uint32(2); uint32(2); uint32(2)]);
      ctrl.set_scalar_read_sequence("GVL_MODE.experimentActive", [false; true; true; true; true]);
      ctrl.scalarMap("GVL_MODE.loggerFileReleased") = false;
      conn = experiment.ConnectionManager.from_transports(seq, ctrl, module);
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2], ...
        "wait_for_done", true, ...
        "done_timeout_s", 0.02, ...
        "abort_check_period_s", 0.005, ...
        "read_logs", false, ...
        "validate_symbols", false);

      testCase.verifyError(@() experiment.ExperimentRunner.run(conn, cfg), ...
        "experiment:runner:doneTimeout");
      testCase.verifyEqual(ctrl.scalarMap("GVL_MODE.modeFlags"), uint16(0));
    end

    function errorsWhenControllerWritesNeedModuleTransport(testCase)
      seq = MockAdsTransport();
      ctrl = MockAdsTransport();
      seed_seq(seq);
      seed_ctrl(ctrl);
      conn = experiment.ConnectionManager.from_transports(seq, ctrl);
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2], ...
        "read_logs", false, ...
        "validate_symbols", false, ...
        "write_controller_params", true);

      testCase.verifyError(@() experiment.ExperimentRunner.run(conn, cfg), ...
        "experiment:runner:invalidConfig");
    end

    function missingExperimentStateFallsBackToExperimentActive(testCase)
      seq = MockAdsTransport();
      ctrl = MockAdsTransport();
      module = MockAdsTransport();
      seed_seq(seq);
      seed_ctrl_without_state(ctrl);
      conn = experiment.ConnectionManager.from_transports(seq, ctrl, module);
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2], ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "read_logs", false, ...
        "validate_symbols", false);

      out = experiment.ExperimentRunner.run(conn, cfg);

      testCase.verifyFalse(out.host.done);
      testCase.verifyEqual(string(out.host.control_experiment_state_symbol), "");
      testCase.verifyTrue(out.logger.file_released);
    end
  end
end

function seed_seq(t)
t.scalarMap("GVL_SEQ.idx") = uint32(0);
t.scalarMap("GVL_MODE.experimentActive") = false;
end

function seed_ctrl(t)
  t.scalarMap("GVL_MODE.modeFlags") = uint16(0);
  t.scalarMap("GVL_MODE.resetReq") = false;
  t.scalarMap("GVL_MODE.resetAckCounter") = uint32(0);
t.scalarMap("GVL_MODE.hostHeartbeatCounter") = uint32(0);
t.scalarMap("GVL_MODE.experimentActive") = false;
t.scalarMap("GVL_MODE.experimentState") = uint32(1);
  t.scalarMap("GVL_MODE.loggerFileReleased") = true;
  t.scalarMap("GVL_MODE.loggerErrorCode") = uint32(0);
end

function seed_ctrl_without_state(t)
  t.scalarMap("GVL_MODE.modeFlags") = uint16(0);
  t.scalarMap("GVL_MODE.resetReq") = false;
  t.scalarMap("GVL_MODE.resetAckCounter") = uint32(0);
  t.scalarMap("GVL_MODE.hostHeartbeatCounter") = uint32(0);
  t.scalarMap("GVL_MODE.experimentActive") = false;
  t.scalarMap("GVL_MODE.loggerFileReleased") = true;
  t.scalarMap("GVL_MODE.loggerErrorCode") = uint32(0);
end

function seed_logger_status(t, ready_values, record_values)
t.set_scalar_read_sequence("ExperimentLogger_Obj1 (Module1).Outputs.status.loggerReady", ready_values);
t.set_scalar_read_sequence("ExperimentLogger_Obj1 (Module1).Outputs.status.recordsWritten", record_values);
end
