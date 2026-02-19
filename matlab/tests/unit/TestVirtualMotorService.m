classdef TestVirtualMotorService < matlab.unittest.TestCase
  methods (Test)
    function profileFlowWritesExpectedSymbols(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      seedScalars(plc);
      seedVmScalars(vm, "VirtualMotor.");
      svc = experiment.VirtualMotorService(plc, vm);

      cfg = experiment.RunConfig.fromVarargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "current_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "save_path", fullfile(tempdir, "ehm_test_profile.mat"));

      out = svc.run(cfg); %#ok<NASGU>
      joined = strjoin(plc.operations, "|");
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("writeScalar:GVL_VM.cmd_len"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("writeScalar:GVL_VM.experiment_start"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("writeScalar:GVL_VM.reset_req"));
    end

    function waitForDoneTimeoutWarns(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      seedScalars(plc);
      seedVmScalars(vm, "VirtualMotor.");
      plc.forceStartTrue = true;
      svc = experiment.VirtualMotorService(plc, vm);

      cfg = experiment.RunConfig.fromVarargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "current_profile", [0.1], ...
        "wait_for_done", true, ...
        "done_timeout_s", 0.01, ...
        "hold_seconds", 0.0, ...
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

      cfg = experiment.RunConfig.fromVarargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "current_in", 0.2, ...
        "current_profile", [], ...
        "hold_seconds", 0.0, ...
        "save_path", fullfile(tempdir, "ehm_test_missing_logs.mat"));

      testCase.verifyWarning(@()svc.run(cfg), "experiment:service:logUnavailable");
      out = svc.run(cfg);
      testCase.verifyEmpty(out.raw.log_i);
      testCase.verifyEmpty(out.raw.log_x);
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
t.scalarMap("GVL_VM_LOG.overflow") = false;
t.arrayMap("GVL_VM_LOG.log_seq") = uint32([]);
t.arrayMap("GVL_VM_LOG.log_i") = [];
t.arrayMap("GVL_VM_LOG.log_x") = [];
t.arrayMap("GVL_VM_LOG.log_t") = uint64([]);
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
