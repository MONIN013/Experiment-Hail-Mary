classdef TestVirtualMotorService < matlab.unittest.TestCase
  methods (Test)
    function profileFlowWritesExpectedSymbols(testCase)
      plc = MockAdsTransport();
      module = MockAdsTransport();
      seedPlcScalars(plc);
      seedVmScalars(module, "VirtualMotor.");
      seedControllerScalars(module, "ControllerCore.");
      svc = experiment.VirtualMotorService(plc, module);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "controller_param_symbol_prefix", "ControllerCore.", ...
        "ref_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "log_require_complete", false, ...
        "save_path", fullfile(tempdir, "ehm_test_profile_new.mat"));

      out = svc.run(cfg); %#ok<NASGU>
      joined = strjoin(plc.operations, "|");
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_array:GVL_EXP.ref_table"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_array:GVL_EXP.ff_table"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_array:GVL_EXP.dist_table"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_EXP.table_len"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_EXP.experiment_active"));
    end

    function streamingModeDrainsLogsDuringRun(testCase)
      plc = MockAdsTransport();
      module = MockAdsTransport();
      seedPlcScalars(plc);
      seedVmScalars(module, "VirtualMotor.");
      seedControllerScalars(module, "ControllerCore.");
      plc.arrayMap("GVL_EXP_LOG.log_ref_value") = [0.1; 0.2; 0.3];
      plc.arrayMap("GVL_EXP_LOG.log_ff_value") = [0.0; 0.0; 0.0];
      plc.arrayMap("GVL_EXP_LOG.log_dist_value") = [0.0; 0.0; 0.0];
      plc.arrayMap("GVL_EXP_LOG.log_control_input") = [1.0; 1.1; 1.2];
      plc.arrayMap("GVL_EXP_LOG.log_target_torque") = [1.0; 1.1; 1.2];
      plc.arrayMap("GVL_EXP_LOG.log_position_act") = [0.0; 0.01; 0.02];
      plc.arrayMap("GVL_EXP_LOG.log_t") = uint64([1000; 2000; 3000]);
      plc.arrayMap("GVL_EXP_LOG.log_idx") = uint32([0; 1; 2]);
      plc.set_scalar_read_sequence("GVL_EXP_LOG.wr_idx", [0; 0; 3; 3]);
      plc.set_scalar_read_sequence("GVL_EXP.experiment_active", [false; true; false]);
      svc = experiment.VirtualMotorService(plc, module);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "controller_param_symbol_prefix", "ControllerCore.", ...
        "ref_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", true, ...
        "done_timeout_s", 0.1, ...
        "log_poll_period_s", 1e-4, ...
        "save_path", fullfile(tempdir, "ehm_test_stream_new.mat"));

      out = svc.run(cfg);
      testCase.verifyEqual(out.raw.log_ref_value(:), [0.1; 0.2; 0.3]);
      testCase.verifyTrue(out.host.log_stream_enabled);
      testCase.verifyEqual(out.host.log_samples_captured, 3);
      joined = strjoin(plc.operations, "|");
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("read_array_slice:GVL_EXP_LOG.log_ref_value"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_EXP_LOG.rd_idx"));
    end

    function streamingFailureRaisesInStrictMode(testCase)
      plc = MockAdsTransport();
      module = MockAdsTransport();
      seedPlcScalars(plc);
      seedVmScalars(module, "VirtualMotor.");
      seedControllerScalars(module, "ControllerCore.");
      seedPlcLogArrays(plc);
      plc.set_scalar_read_sequence("GVL_EXP_LOG.wr_idx", [0; 0; 3; 3]);
      plc.set_scalar_read_sequence("GVL_EXP.experiment_active", [false; false; true; false]);
      plc.set_read_array_slice_error("GVL_EXP_LOG.log_ref_value", "mock:readArraySliceFailure", "Injected slice read failure");
      svc = experiment.VirtualMotorService(plc, module);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "controller_param_symbol_prefix", "ControllerCore.", ...
        "ref_profile", [0.1; 0.2; 0.3], ...
        "wait_for_done", true, ...
        "done_timeout_s", 0.05, ...
        "reset_timeout_s", 0.05, ...
        "log_poll_period_s", 1e-4, ...
        "log_stream_enable", true, ...
        "log_stream_require_success", true, ...
        "save_path", fullfile(tempdir, "ehm_test_stream_strict_fail_new.mat"));

      testCase.verifyError(@()svc.run(cfg), "experiment:service:logStreamFailed");
    end
  end
end

function seedPlcScalars(t)
t.scalarMap("GVL_EXP.reset_req") = false;
t.scalarMap("GVL_EXP.experiment_active") = false;
t.scalarMap("GVL_EXP.table_len") = uint32(0);
t.scalarMap("GVL_EXP.idx") = uint32(0);
t.scalarMap("GVL_EXP.ref_value") = 0.0;
t.scalarMap("GVL_EXP.ff_value") = 0.0;
t.scalarMap("GVL_EXP.control_input") = 0.0;
t.scalarMap("GVL_EXP.target_torque") = 0.0;
t.scalarMap("GVL_EXP.position_act_log") = 0.0;
t.scalarMap("GVL_EXP_LOG.wr_idx") = uint32(0);
t.scalarMap("GVL_EXP_LOG.rd_idx") = uint32(0);
t.scalarMap("GVL_EXP_LOG.overflow") = false;
t.scalarMap("GVL_EXP_LOG.LOG_N") = uint32(200000);
seedPlcLogArrays(t);
end

function seedPlcLogArrays(t)
t.arrayMap("GVL_EXP_LOG.log_seq") = uint32([]);
t.arrayMap("GVL_EXP_LOG.log_ref_value") = [];
t.arrayMap("GVL_EXP_LOG.log_ff_value") = [];
t.arrayMap("GVL_EXP_LOG.log_dist_value") = [];
t.arrayMap("GVL_EXP_LOG.log_control_input") = [];
t.arrayMap("GVL_EXP_LOG.log_target_torque") = [];
t.arrayMap("GVL_EXP_LOG.log_position_act") = [];
t.arrayMap("GVL_EXP_LOG.log_t") = uint64([]);
t.arrayMap("GVL_EXP_LOG.log_idx") = uint32([]);
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

function seedControllerScalars(t, prefix)
base = char(string(prefix));
keys = {
  'PIDParams.notch_b0','PIDParams.notch_b1','PIDParams.notch_b2','PIDParams.notch_a1','PIDParams.notch_a2', ...
  'LeadParams.notch_b0','LeadParams.notch_b1','LeadParams.notch_b2','LeadParams.notch_a1','LeadParams.notch_a2', ...
  'NotchParams.notch_b0','NotchParams.notch_b1','NotchParams.notch_b2','NotchParams.notch_a1','NotchParams.notch_a2', ...
  'ResoParams.notch_b0','ResoParams.notch_b1','ResoParams.notch_b2','ResoParams.notch_a1','ResoParams.notch_a2'};
for i = 1:numel(keys)
  t.scalarMap(strcat(base, keys{i})) = 0.0;
end
t.scalarMap(strcat(base, 'EnableParams.enable_pid')) = true;
t.scalarMap(strcat(base, 'EnableParams.enable_lead')) = false;
t.scalarMap(strcat(base, 'EnableParams.enable_notch')) = false;
t.scalarMap(strcat(base, 'EnableParams.enable_reso')) = false;
end
