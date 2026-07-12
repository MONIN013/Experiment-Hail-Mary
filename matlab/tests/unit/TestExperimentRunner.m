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
      env = config.EnvironmentConfig.current();
      env.controller_prefix = "CustomController.";
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2; 0.3], ...
        "env", env, ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "read_logs", false, ...
        "validate_symbols", false);
      out = experiment.ExperimentRunner.run(conn, cfg);
      testCase.verifyTrue(isfield(out.raw, "ref_value"));
      testCase.verifyEqual(out.raw.ref_value, zeros(0, 1));
      testCase.verifyEmpty(out.logger_bin);
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
      testCase.verifyTrue(isfield(out.host, "startup_timing"));
      testCase.verifyTrue(isfield(out.host.startup_timing, "table_write_s"));
      testCase.verifyGreaterThanOrEqual(out.host.startup_timing.total_s, 0);
    end

    function runStopsAndResetsBeforeParametersThenPublishesTableLast(testCase)
      seq = MockAdsTransport();
      ctrl = MockAdsTransport();
      module = MockAdsTransport();
      seed_seq(seq);
      seed_ctrl(ctrl);
      events = containers.Map("KeyType", "char", "ValueType", "any");
      events("events") = strings(0, 1);
      attach_event_log(seq, events, "seq");
      attach_event_log(ctrl, events, "ctrl");
      attach_event_log(module, events, "module");
      conn = experiment.ConnectionManager.from_transports(seq, ctrl, module);
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "read_logs", false, ...
        "validate_symbols", false);

      experiment.ExperimentRunner.run(conn, cfg);

      log = string(events("events"));
      reset_writes = find(log == "ctrl:write_scalar:GVL_MODE.resetReq");
      table_len_writes = find(log == "seq:write_scalar:GVL_SEQ.tableLen");
      mode_writes = find(log == "ctrl:write_scalar:GVL_MODE.modeFlags");
      heartbeat_writes = find(log == "ctrl:write_scalar:GVL_MODE.hostHeartbeatCounter");
      controller_write = find(contains(log, "module:write_scalar:ControllerCore_Obj1 (Module1).PIDParams.pidB0"), 1);
      ref_write = find(log == "seq:write_array:GVL_SEQ.refTable", 1);
      ff_write = find(log == "seq:write_array:GVL_SEQ.ffTable", 1);
      dist_write = find(log == "seq:write_array:GVL_SEQ.distTable", 1);

      testCase.verifyNumElements(table_len_writes, 2, ...
        "tableLen must be cleared once and published once.");
      testCase.verifyGreaterThanOrEqual(numel(reset_writes), 2);
      testCase.verifyGreaterThanOrEqual(numel(mode_writes), 3);
      testCase.verifyGreaterThanOrEqual(numel(heartbeat_writes), 2);
      testCase.verifyLessThan(table_len_writes(1), reset_writes(2));
      testCase.verifyGreaterThan(controller_write, reset_writes(2));
      testCase.verifyGreaterThan(ref_write, reset_writes(2));
      testCase.verifyLessThan(ref_write, table_len_writes(2));
      testCase.verifyLessThan(ff_write, table_len_writes(2));
      testCase.verifyLessThan(dist_write, table_len_writes(2));
      testCase.verifyLessThan(table_len_writes(2), heartbeat_writes(2));
      testCase.verifyLessThan(heartbeat_writes(2), mode_writes(3));
    end

    function parameterWriteFailureLeavesRunStoppedAndTableHidden(testCase)
      seq = MockAdsTransport();
      ctrl = MockAdsTransport();
      module = MockAdsTransport();
      seed_seq(seq);
      seed_ctrl(ctrl);
      module.set_scalar_write_error( ...
        "ControllerCore_Obj1 (Module1).PIDParams.pidB0", ...
        "test:controllerWriteFailed", "injected failure");
      conn = experiment.ConnectionManager.from_transports(seq, ctrl, module);
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2], ...
        "read_logs", false, ...
        "validate_symbols", false);

      testCase.verifyError(@() experiment.ExperimentRunner.run(conn, cfg), ...
        "test:controllerWriteFailed");
      testCase.verifyEqual(ctrl.scalarMap("GVL_MODE.modeFlags"), uint16(0));
      testCase.verifyEqual(seq.scalarMap("GVL_SEQ.tableLen"), uint32(0));
    end

    function rejectsConnectionEnvironmentMismatchBeforeAdsAccess(testCase)
      seq = MockAdsTransport();
      ctrl = MockAdsTransport();
      module = MockAdsTransport();
      expected_env = config.EnvironmentConfig.current();
      expected_env.controller_prefix = "ExpectedController.";
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2], ...
        "env", expected_env, ...
        "read_logs", false, ...
        "validate_symbols", false);
      conn_env = cfg.env.to_struct();
      conn_env.controller_prefix = "ConnectedController.";
      conn = experiment.ConnectionManager.from_transports(seq, ctrl, module, conn_env);

      testCase.verifyError(@() experiment.ExperimentRunner.run(conn, cfg), ...
        "experiment:runner:connectionConfigMismatch");
      testCase.verifyEmpty(seq.operations);
      testCase.verifyEmpty(ctrl.operations);
      testCase.verifyEmpty(module.operations);
    end

    function runReturnsTheLoggerPayloadUsedForRaw(testCase)
      file_path = [tempname, '.bin'];
      cleaner = onCleanup(@() delete_if_exists(file_path)); %#ok<NASGU>
      write_logger_record(file_path);
      seq = MockAdsTransport();
      ctrl = MockAdsTransport();
      module = MockAdsTransport();
      seed_seq(seq);
      seed_ctrl(ctrl);
      conn = experiment.ConnectionManager.from_transports(seq, ctrl, module);
      env = config.EnvironmentConfig.current();
      env.logger_host_file_path = file_path;
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2], ...
        "env", env, ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "read_logs", true, ...
        "validate_symbols", false);

      out = experiment.ExperimentRunner.run(conn, cfg);

      testCase.verifyEqual(out.logger_bin.record_count, 1);
      testCase.verifyEqual(out.raw.seq, double(out.logger_bin.raw.seq));
      testCase.verifyEqual(out.raw.ref_value, out.logger_bin.raw.ref_value);
      testCase.verifyEqual(out.raw.position_act, out.logger_bin.raw.load_position);
    end

    function runWritesVirtualMotorParamsWhenRequested(testCase)
      seq = MockAdsTransport();
      ctrl = MockAdsTransport();
      module = MockAdsTransport();
      seed_seq(seq);
      seed_ctrl(ctrl);
      seed_logger_status(module, [false; true], [uint32(7); uint32(10)]);
      seed_virtual_motor(module);
      conn = experiment.ConnectionManager.from_transports(seq, ctrl, module);
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2], ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "read_logs", false, ...
        "validate_symbols", false, ...
        "write_virtual_motor_params", true, ...
        "virtual_motor_plant", experiment.exp01.nominal_overlay_plant());

      out = experiment.ExperimentRunner.run(conn, cfg);

      testCase.verifyFalse(out.host.done);
      testCase.verifyTrue(any(contains(module.operations, "write_scalar:VirtualMotorCore_Obj1 (Module1).PlantParameter.motor.inertia")));
      testCase.verifyTrue(out.config.write_virtual_motor_params);
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
      ctrl.set_scalar_read_sequence("GVL_MODE.modeState", ...
        [int16(0); int16(0); int16(20); int16(30); int16(30); int16(0)]);
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
      ctrl.set_scalar_read_sequence("GVL_MODE.modeState", ...
        [int16(0); int16(0); int16(20); int16(30); int16(40)]);
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
      ctrl.set_scalar_read_sequence("GVL_MODE.modeState", ...
        [int16(0); int16(0); int16(20); int16(30); int16(30); int16(30); int16(30)]);
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

    function missingModeStateIsRejected(testCase)
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

      testCase.verifyError(@() experiment.ExperimentRunner.run(conn, cfg), ...
        "experiment:runner:invalidConfig");
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
t.set_scalar_read_sequence("GVL_MODE.modeState", [int16(0); int16(0); int16(20)]);
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

function seed_virtual_motor(t)
symbols = virtualMotor.Symbols.from_defaults();
probes = symbols.requiredProbes;
types = twincat_ads.AdsTransport.net_types();
for k = 1:size(probes, 1)
  sym = char(string(probes{k, 1}));
  nt = char(string(probes{k, 2}));
  switch nt
    case char(string(types.u32))
      t.scalarMap(sym) = uint32(1);
    case char(string(types.u64))
      t.scalarMap(sym) = uint64(1);
    otherwise
      t.scalarMap(sym) = 1.0;
  end
end
end

function attach_event_log(transport, event_log, name)
transport.sharedEventLog = event_log;
transport.transportName = string(name);
end

function write_logger_record(file_path)
[fid, msg] = fopen(file_path, "wb", "ieee-le");
assert(fid >= 0, msg);
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, uint32(1), "uint32");
fwrite(fid, uint32(2), "uint32");
fwrite(fid, uint64(1000), "uint64");
fwrite(fid, 0.1:0.1:1.1, "double");
end

function delete_if_exists(file_path)
if isfile(file_path)
  delete(file_path);
end
end
