classdef TestVirtualMotorService < matlab.unittest.TestCase
  methods (Test)
    function profileFlowWritesExpectedSymbols(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      seedScalars(plc);
      seedVmScalars(vm, "VirtualMotor.");
      svc = experiment.VirtualMotorService(plc, vm);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "current_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "log_require_complete", false, ...
        "save_path", fullfile(tempdir, "ehm_test_profile.mat"));

      out = svc.run(cfg); %#ok<NASGU>
      joined = strjoin(plc.operations, "|");
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_VM.cmd_len"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_VM.experiment_start"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_VM.reset_req"));
    end

    function waitForDoneTimeoutWarns(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      seedScalars(plc);
      seedVmScalars(vm, "VirtualMotor.");
      plc.forceStartTrue = true;
      svc = experiment.VirtualMotorService(plc, vm);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "current_profile", [0.1], ...
        "wait_for_done", true, ...
        "done_timeout_s", 0.01, ...
        "hold_seconds", 0.0, ...
        "log_require_complete", false, ...
        "save_path", fullfile(tempdir, "ehm_test_timeout.mat"));

      testCase.verifyWarning(@()svc.run(cfg), "experiment:service:timeout");
    end

    function missingLogsReturnsEmptyArrays(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      seedScalars(plc);
      remove(plc.scalarMap, "GVL_VM_LOG.wr_idx");
      remove(plc.scalarMap, "GVL_VM_LOG.overflow");
      seedVmScalars(vm, "VirtualMotor.");
      svc = experiment.VirtualMotorService(plc, vm);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "current_in", 0.2, ...
        "current_profile", [], ...
        "hold_seconds", 0.0, ...
        "log_require_complete", false, ...
        "save_path", fullfile(tempdir, "ehm_test_missing_logs.mat"));

      testCase.verifyWarning(@()svc.run(cfg), "experiment:service:logUnavailable");
      out = svc.run(cfg);
      testCase.verifyEmpty(out.raw.log_i);
      testCase.verifyEmpty(out.raw.log_x);
    end

    function streamingModeDrainsLogsDuringRun(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      seedScalars(plc);
      seedVmScalars(vm, "VirtualMotor.");
      plc.arrayMap("GVL_VM_LOG.log_seq") = uint32([1; 2; 3]);
      plc.arrayMap("GVL_VM_LOG.log_i") = [0.1; 0.2; 0.3];
      plc.arrayMap("GVL_VM_LOG.log_x") = [1.0; 1.1; 1.2];
      plc.arrayMap("GVL_VM_LOG.log_t") = uint64([1000; 2000; 3000]);
      plc.set_scalar_read_sequence("GVL_VM_LOG.wr_idx", [0; 0; 3; 3]);
      plc.set_scalar_read_sequence("GVL_VM.experiment_start", [false; true; false]);
      svc = experiment.VirtualMotorService(plc, vm);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "current_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", true, ...
        "done_timeout_s", 0.1, ...
        "log_poll_period_s", 0.0 + 1e-4, ...
        "save_path", fullfile(tempdir, "ehm_test_stream.mat"));

      out = svc.run(cfg);
      testCase.verifyEqual(out.raw.log_seq(:), [1; 2; 3]);
      testCase.verifyEqual(out.raw.log_i(:), [0.1; 0.2; 0.3], "AbsTol", 1e-12);
      testCase.verifyTrue(out.host.log_stream_enabled);
      testCase.verifyEqual(out.host.log_samples_captured, 3);
      joined = strjoin(plc.operations, "|");
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("read_array_slice:GVL_VM_LOG.log_i"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_VM_LOG.rd_idx"));
    end

    function legacyNonStreamingPathStillWorks(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      seedScalars(plc);
      seedVmScalars(vm, "VirtualMotor.");
      plc.set_scalar_read_sequence("GVL_VM_LOG.wr_idx", [0; 3]);
      plc.arrayMap("GVL_VM_LOG.log_seq") = uint32([1; 2; 3]);
      plc.arrayMap("GVL_VM_LOG.log_i") = [0.1; 0.2; 0.3];
      plc.arrayMap("GVL_VM_LOG.log_x") = [1.0; 1.1; 1.2];
      plc.arrayMap("GVL_VM_LOG.log_t") = uint64([1000; 2000; 3000]);
      svc = experiment.VirtualMotorService(plc, vm);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "current_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "log_stream_enable", false, ...
        "log_require_complete", false, ...
        "save_path", fullfile(tempdir, "ehm_test_legacy.mat"));

      out = svc.run(cfg);
      testCase.verifyEqual(out.raw.log_seq(:), [1; 2; 3]);
      joined = strjoin(plc.operations, "|");
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("read_array:GVL_VM_LOG.log_i"));
    end

    function streamingFailureRaisesInStrictMode(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      seedScalars(plc);
      seedVmScalars(vm, "VirtualMotor.");
      plc.arrayMap("GVL_VM_LOG.log_seq") = uint32([1; 2; 3]);
      plc.arrayMap("GVL_VM_LOG.log_i") = [0.1; 0.2; 0.3];
      plc.arrayMap("GVL_VM_LOG.log_x") = [1.0; 1.1; 1.2];
      plc.arrayMap("GVL_VM_LOG.log_t") = uint64([1000; 2000; 3000]);
      plc.set_scalar_read_sequence("GVL_VM_LOG.wr_idx", [0; 0; 3; 3]);
      plc.set_scalar_read_sequence("GVL_VM.experiment_start", [false; false; true; false]);
      plc.set_read_array_slice_error("GVL_VM_LOG.log_i", ...
        "mock:readArraySliceFailure", "Injected slice read failure");
      svc = experiment.VirtualMotorService(plc, vm);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "current_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", true, ...
        "done_timeout_s", 0.05, ...
        "reset_timeout_s", 0.05, ...
        "log_poll_period_s", 1e-4, ...
        "log_stream_enable", true, ...
        "log_stream_require_success", true, ...
        "save_path", fullfile(tempdir, "ehm_test_stream_strict_fail.mat"));

      testCase.verifyError(@()svc.run(cfg), "experiment:service:logStreamFailed");
    end

    function streamingFailureFallsBackInNonStrictMode(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      seedScalars(plc);
      seedVmScalars(vm, "VirtualMotor.");
      plc.arrayMap("GVL_VM_LOG.log_seq") = uint32([1; 2; 3]);
      plc.arrayMap("GVL_VM_LOG.log_i") = [0.1; 0.2; 0.3];
      plc.arrayMap("GVL_VM_LOG.log_x") = [1.0; 1.1; 1.2];
      plc.arrayMap("GVL_VM_LOG.log_t") = uint64([1000; 2000; 3000]);
      plc.set_scalar_read_sequence("GVL_VM_LOG.wr_idx", [0; 0; 3; 3]);
      plc.set_scalar_read_sequence("GVL_VM.experiment_start", [false; false; true; false]);
      plc.set_read_array_slice_error("GVL_VM_LOG.log_i", ...
        "mock:readArraySliceFailure", "Injected slice read failure");
      svc = experiment.VirtualMotorService(plc, vm);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "current_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", true, ...
        "done_timeout_s", 0.05, ...
        "reset_timeout_s", 0.05, ...
        "log_poll_period_s", 1e-4, ...
        "log_stream_enable", true, ...
        "log_stream_require_success", false, ...
        "log_require_complete", false, ...
        "save_path", fullfile(tempdir, "ehm_test_stream_fallback.mat"));

      out = svc.run(cfg);
      testCase.verifyFalse(out.host.log_stream_enabled);
      testCase.verifyTrue(out.host.log_stream_fallback_used);
      testCase.verifyEqual(out.host.log_stream_error_identifier, char("mock:readArraySliceFailure"));
      testCase.verifyEqual(out.raw.log_seq(:), [1; 2; 3]);
    end

    function incompleteLogRaisesWhenRequireComplete(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      seedScalars(plc);
      seedVmScalars(vm, "VirtualMotor.");
      plc.set_scalar_read_sequence("GVL_VM_LOG.wr_idx", [0; 2]);
      plc.arrayMap("GVL_VM_LOG.log_seq") = uint32([1; 2]);
      plc.arrayMap("GVL_VM_LOG.log_i") = [0.1; 0.2];
      plc.arrayMap("GVL_VM_LOG.log_x") = [1.0; 1.1];
      plc.arrayMap("GVL_VM_LOG.log_t") = uint64([1000; 2000]);
      svc = experiment.VirtualMotorService(plc, vm);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "current_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "log_stream_enable", false, ...
        "log_require_complete", true, ...
        "save_path", fullfile(tempdir, "ehm_test_incomplete_log.mat"));

      testCase.verifyError(@()svc.run(cfg), "experiment:service:incompleteLog");
    end

    function waveformMismatchCanContinueWhenExactDisabled(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      seedScalars(plc);
      seedVmScalars(vm, "VirtualMotor.");
      plc.set_scalar_read_sequence("GVL_VM_LOG.wr_idx", [0; 3]);
      plc.arrayMap("GVL_VM_LOG.log_seq") = uint32([1; 2; 3]);
      plc.arrayMap("GVL_VM_LOG.log_i") = [0.0; 0.1; 0.2]; % one-sample shift vs command
      plc.arrayMap("GVL_VM_LOG.log_x") = [0.0; 0.0; 0.0];
      plc.arrayMap("GVL_VM_LOG.log_t") = uint64([1000; 2000; 3000]);
      svc = experiment.VirtualMotorService(plc, vm);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "current_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", true, ...
        "done_timeout_s", 0.01, ...
        "log_stream_enable", false, ...
        "log_require_complete", true, ...
        "log_require_waveform_exact", false, ...
        "waveform_diag_max_shift_samples", 1, ...
        "save_path", fullfile(tempdir, "ehm_test_waveform_diag_continue.mat"));

      out = svc.run(cfg);
      testCase.verifyFalse(out.metrics.acceptance.input_waveform_exact_match);
      testCase.verifyTrue(out.metrics.acceptance.input_waveform_shift_aligned_match);
      testCase.verifyEqual(string(out.metrics.input_waveform.mismatch_class), "one_sample_shift");
    end

    function waveformMismatchStillRaisesWhenExactEnabled(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      seedScalars(plc);
      seedVmScalars(vm, "VirtualMotor.");
      plc.set_scalar_read_sequence("GVL_VM_LOG.wr_idx", [0; 3]);
      plc.arrayMap("GVL_VM_LOG.log_seq") = uint32([1; 2; 3]);
      plc.arrayMap("GVL_VM_LOG.log_i") = [0.0; 0.1; 0.2];
      plc.arrayMap("GVL_VM_LOG.log_x") = [0.0; 0.0; 0.0];
      plc.arrayMap("GVL_VM_LOG.log_t") = uint64([1000; 2000; 3000]);
      svc = experiment.VirtualMotorService(plc, vm);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "current_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", true, ...
        "done_timeout_s", 0.01, ...
        "log_stream_enable", false, ...
        "log_require_complete", true, ...
        "log_require_waveform_exact", true, ...
        "waveform_diag_max_shift_samples", 1, ...
        "save_path", fullfile(tempdir, "ehm_test_waveform_diag_strict.mat"));

      testCase.verifyError(@()svc.run(cfg), "experiment:service:incompleteLog");
      try
        svc.run(cfg);
      catch e
        testCase.verifyThat(string(e.message), matlab.unittest.constraints.ContainsSubstring("class=one_sample_shift"));
        testCase.verifyThat(string(e.message), matlab.unittest.constraints.ContainsSubstring("best_shift="));
      end
    end
  end
end

function seedScalars(t)
t.scalarMap("GVL_VM.experiment_start") = false;
t.scalarMap("GVL_VM.reset_req") = false;
t.scalarMap("GVL_VM.current_in") = 0.0;
t.scalarMap("GVL_VM.position_out") = 0.0;
t.scalarMap("GVL_VM.velocity_out") = 0.0;
t.scalarMap("GVL_VM.cmd_len") = uint32(0);
t.scalarMap("GVL_VM.cmd_idx") = uint32(0);
t.scalarMap("GVL_VM_LOG.wr_idx") = uint32(0);
t.scalarMap("GVL_VM_LOG.rd_idx") = uint32(0);
t.scalarMap("GVL_VM_LOG.overflow") = false;
t.scalarMap("GVL_VM_LOG.LOG_N") = uint32(200000);
t.arrayMap("GVL_VM_LOG.log_seq") = uint32([]);
t.arrayMap("GVL_VM_LOG.log_i") = [];
t.arrayMap("GVL_VM_LOG.log_x") = [];
t.arrayMap("GVL_VM_LOG.log_t") = uint64([]);
t.arrayMap("GVL_VM_LOG.log_cmd_idx") = uint32([]);
t.arrayMap("GVL_VM_LOG.log_cmd_value") = [];
end

function seedVmScalars(t, prefix)
base = char(string(prefix));
t.scalarMap(strcat(base, 'M')) = 1.0;
t.scalarMap(strcat(base, 'D')) = 1.0;
t.scalarMap(strcat(base, 'Kt')) = 1.0;
t.scalarMap(strcat(base, 'tau_limit')) = 1.0;
t.scalarMap(strcat(base, 'vel_limit')) = 1.0;
t.scalarMap(strcat(base, 'task_dt_ns')) = uint64(1000);
end
