classdef TestVirtualMotorService < matlab.unittest.TestCase
  methods (Test)
    function profileFlowWritesExpectedSymbols(testCase)
      plc = MockAdsTransport();
      module = MockAdsTransport();
      control = MockAdsTransport();
      seedPlcScalars(plc);
      seedControlScalars(control);
      seedVmScalars(module, "VirtualMotor.");
      seedControllerScalars(module, "ControllerCore.");
      svc = experiment.VirtualMotorService(plc, module, control);

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
      plc_joined = strjoin(plc.operations, "|");
      ctrl_joined = strjoin(control.operations, "|");
      testCase.verifyThat(plc_joined, matlab.unittest.constraints.ContainsSubstring("write_array:GVL_SEQ.refTable"));
      testCase.verifyThat(plc_joined, matlab.unittest.constraints.ContainsSubstring("write_array:GVL_SEQ.ffTable"));
      testCase.verifyThat(plc_joined, matlab.unittest.constraints.ContainsSubstring("write_array:GVL_SEQ.distTable"));
      testCase.verifyThat(plc_joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_SEQ.tableLen"));
      testCase.verifyFalse(contains(plc_joined, "write_scalar:GVL_SEQ.experimentActive"));
      testCase.verifyFalse(contains(plc_joined, "write_scalar:GVL_SEQ.resetReq"));
      testCase.verifyFalse(contains(plc_joined, "write_scalar:GVL_SEQ.idx"));
      testCase.verifyThat(ctrl_joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_MODE.modeFlags"));
      testCase.verifyThat(ctrl_joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_MODE.resetReq"));
      testCase.verifyThat(ctrl_joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_MODE.hostHeartbeatCounter"));
    end

    function configOverridesDriveExplicitPrefixesAndTaskDt(testCase)
      plc = MockAdsTransport();
      module = MockAdsTransport();
      control = MockAdsTransport();
      seedPlcScalars(plc);
      seedControlScalars(control);
      seedVmScalars(module, "VmOverride.");
      seedControllerScalars(module, "CtrlOverride.");
      svc = experiment.VirtualMotorService(plc, module, control);

      cfg = experiment.RunConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2], ...
        "vm_param_symbol_prefix", "VmOverride.", ...
        "controller_param_symbol_prefix", "CtrlOverride.", ...
        "task_rate_hz", 2000, ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "log_require_complete", false, ...
        "save_path", fullfile(tempdir, "ehm_test_override_contract.mat"));

      svc.run(cfg);
      testCase.verifyEqual(module.scalarMap("VmOverride.taskDtNs"), uint64(500000));
      testCase.verifyEqual(module.scalarMap("CtrlOverride.EnableParams.enablePid"), true);
    end

    function streamingModeDrainsLogsDuringRun(testCase)
      plc = MockAdsTransport();
      module = MockAdsTransport();
      control = MockAdsTransport();
      seedPlcScalars(plc);
      seedControlScalars(control);
      seedVmScalars(module, "VirtualMotor.");
      seedControllerScalars(module, "ControllerCore.");
      plc.arrayMap("GVL_SEQ_LOG.logRefValue") = [0.1; 0.2; 0.3];
      plc.arrayMap("GVL_SEQ_LOG.logFfValue") = [0.0; 0.0; 0.0];
      plc.arrayMap("GVL_SEQ_LOG.logDistValue") = [0.0; 0.0; 0.0];
      plc.arrayMap("GVL_SEQ_LOG.logControlInput") = [1.0; 1.1; 1.2];
      plc.arrayMap("GVL_SEQ_LOG.logTargetCurrent") = [1.0; 1.1; 1.2];
      plc.arrayMap("GVL_SEQ_LOG.logPositionAct") = [0.0; 0.01; 0.02];
      plc.arrayMap("GVL_SEQ_LOG.logT") = uint64([1000; 2000; 3000]);
      plc.arrayMap("GVL_SEQ_LOG.logIdx") = uint32([0; 1; 2]);
      plc.set_scalar_read_sequence("GVL_SEQ_LOG.wrIdx", [0; 0; 3; 3]);
      control.set_scalar_read_sequence("GVL_MODE.experimentActive", [false; false; true; false]);
      control.set_scalar_read_sequence("GVL_MODE.experimentState", uint32([0; 1; 2; 3]));
      svc = experiment.VirtualMotorService(plc, module, control);

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
      testCase.verifyEqual(out.raw.logRefValue(:), [0.1; 0.2; 0.3]);
      testCase.verifyFalse(isfield(out.raw, "log_i"));
      testCase.verifyFalse(isfield(out.raw, "log_x"));
      testCase.verifyTrue(out.host.log_stream_enabled);
      testCase.verifyEqual(out.host.log_samples_captured, 3);
      plc_joined = strjoin(plc.operations, "|");
      ctrl_joined = strjoin(control.operations, "|");
      testCase.verifyThat(plc_joined, matlab.unittest.constraints.ContainsSubstring("read_array_slice:GVL_SEQ_LOG.logRefValue"));
      testCase.verifyThat(plc_joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_SEQ_LOG.rdIdx"));
      testCase.verifyThat(ctrl_joined, matlab.unittest.constraints.ContainsSubstring("read_scalar:GVL_MODE.experimentState"));
    end

    function streamingFailureRaisesInStrictMode(testCase)
      plc = MockAdsTransport();
      module = MockAdsTransport();
      control = MockAdsTransport();
      seedPlcScalars(plc);
      seedControlScalars(control);
      seedVmScalars(module, "VirtualMotor.");
      seedControllerScalars(module, "ControllerCore.");
      seedPlcLogArrays(plc);
      plc.set_scalar_read_sequence("GVL_SEQ_LOG.wrIdx", [0; 0; 3; 3]);
      control.set_scalar_read_sequence("GVL_MODE.experimentActive", [false; false; true; false]);
      control.set_scalar_read_sequence("GVL_MODE.experimentState", uint32([0; 1; 2; 2]));
      plc.set_read_array_slice_error("GVL_SEQ_LOG.logRefValue", "mock:readArraySliceFailure", "Injected slice read failure");
      svc = experiment.VirtualMotorService(plc, module, control);

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

    function waitsDoneUsingExperimentActiveWhenExperimentStateUnavailable(testCase)
      plc = MockAdsTransport();
      module = MockAdsTransport();
      control = MockAdsTransport();
      seedPlcScalars(plc);
      seedControlScalars(control);
      if isKey(control.scalarMap, "GVL_MODE.experimentState")
        remove(control.scalarMap, "GVL_MODE.experimentState");
      end
      control.set_scalar_read_sequence("GVL_MODE.experimentActive", [false; false; true; true; false]);
      seedVmScalars(module, "VirtualMotor.");
      seedControllerScalars(module, "ControllerCore.");
      svc = experiment.VirtualMotorService(plc, module, control);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "controller_param_symbol_prefix", "ControllerCore.", ...
        "ref_profile", [0.1; 0.2], ...
        "wait_for_done", true, ...
        "log_stream_enable", false, ...
        "done_timeout_s", 0.05, ...
        "reset_timeout_s", 0.05, ...
        "log_require_complete", false, ...
        "save_path", fullfile(tempdir, "ehm_test_fallback_done_new.mat"));

      out = svc.run(cfg);
      testCase.verifyGreaterThanOrEqual(out.host.elapsed_s, 0);
      testCase.verifyFalse(isfield(out.raw, "log_i"));
      testCase.verifyFalse(isfield(out.raw, "log_x"));
      ctrl_joined = strjoin(control.operations, "|");
      testCase.verifyThat(ctrl_joined, matlab.unittest.constraints.ContainsSubstring("read_scalar:GVL_MODE.experimentActive"));
    end

    function resetSyncTimeoutRaisesError(testCase)
      plc = MockAdsTransport();
      module = MockAdsTransport();
      control = MockAdsTransport();
      seedPlcScalars(plc);
      seedControlScalars(control);
      seedVmScalars(module, "VirtualMotor.");
      seedControllerScalars(module, "ControllerCore.");
      plc.scalarMap("GVL_SEQ_LOG.wrIdx") = uint32(1);
      plc.scalarMap("GVL_SEQ.idx") = uint32(1);
      svc = experiment.VirtualMotorService(plc, module, control);

      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.", ...
        "controller_param_symbol_prefix", "ControllerCore.", ...
        "ref_profile", [0.1; 0.2], ...
        "wait_for_done", false, ...
        "reset_timeout_s", 0.01, ...
        "log_require_complete", false, ...
        "save_path", fullfile(tempdir, "ehm_test_reset_sync_timeout_new.mat"));

      testCase.verifyError(@()svc.run(cfg), "experiment:service:resetSyncTimeout");
    end
  end
end

function seedPlcScalars(t)
t.scalarMap("GVL_SEQ.resetReq") = false;
t.scalarMap("GVL_SEQ.experimentActive") = false;
t.scalarMap("GVL_SEQ.tableLen") = uint32(0);
t.scalarMap("GVL_SEQ.idx") = uint32(0);
t.scalarMap("GVL_SEQ.repeatCount") = uint32(1);
t.scalarMap("GVL_SEQ.trialIndex") = uint32(0);
t.scalarMap("GVL_SEQ.refValue") = 0.0;
t.scalarMap("GVL_SEQ.ffValue") = 0.0;
t.scalarMap("GVL_SEQ.distValue") = 0.0;
t.scalarMap("GVL_SEQ_LOG.controlInputTap") = 0.0;
t.scalarMap("GVL_SEQ_LOG.positionRelTap") = 0.0;
t.scalarMap("GVL_SEQ_LOG.wrIdx") = uint32(0);
t.scalarMap("GVL_SEQ_LOG.rdIdx") = uint32(0);
t.scalarMap("GVL_SEQ_LOG.overflow") = false;
t.scalarMap("GVL_SEQ_LOG.LOG_N") = uint32(200000);
seedPlcLogArrays(t);
end

function seedControlScalars(t)
t.scalarMap("GVL_MODE.modeFlags") = uint32(0);
t.scalarMap("GVL_MODE.experimentActive") = false;
t.scalarMap("GVL_MODE.experimentState") = uint32(0);
t.scalarMap("GVL_MODE.resetReq") = false;
t.scalarMap("GVL_MODE.resetAckCounter") = uint32(0);
t.scalarMap("GVL_MODE.hostHeartbeatCounter") = uint32(0);
end

function seedPlcLogArrays(t)
t.arrayMap("GVL_SEQ_LOG.logSeq") = uint32([]);
t.arrayMap("GVL_SEQ_LOG.logRefValue") = [];
t.arrayMap("GVL_SEQ_LOG.logFfValue") = [];
t.arrayMap("GVL_SEQ_LOG.logDistValue") = [];
t.arrayMap("GVL_SEQ_LOG.logControlInput") = [];
t.arrayMap("GVL_SEQ_LOG.logTargetCurrent") = [];
t.arrayMap("GVL_SEQ_LOG.logPositionAct") = [];
t.arrayMap("GVL_SEQ_LOG.logT") = uint64([]);
t.arrayMap("GVL_SEQ_LOG.logIdx") = uint32([]);
end

function seedVmScalars(t, prefix)
base = char(string(prefix));
t.scalarMap(strcat(base, 'mass')) = 1.0;
t.scalarMap(strcat(base, 'damping')) = 1.0;
t.scalarMap(strcat(base, 'ratedTorque')) = 1.0;
t.scalarMap(strcat(base, 'maxPermille')) = 0.0;
t.scalarMap(strcat(base, 'tauLimit')) = 1.0;
t.scalarMap(strcat(base, 'velLimit')) = 1.0;
t.scalarMap(strcat(base, 'taskDtNs')) = uint64(1000);
end

function seedControllerScalars(t, prefix)
base = char(string(prefix));
keys = {
  'PIDParams.pidB0','PIDParams.pidB1','PIDParams.pidB2','PIDParams.pidA1','PIDParams.pidA2', ...
  'LeadParams.leadB0','LeadParams.leadB1','LeadParams.leadB2','LeadParams.leadA1','LeadParams.leadA2', ...
  'NotchParams.notchB0','NotchParams.notchB1','NotchParams.notchB2','NotchParams.notchA1','NotchParams.notchA2', ...
  'ResoParams.resoB0','ResoParams.resoB1','ResoParams.resoB2','ResoParams.resoA1','ResoParams.resoA2'};
for i = 1:numel(keys)
  t.scalarMap(strcat(base, keys{i})) = 0.0;
end
t.scalarMap(strcat(base, 'EnableParams.enablePid')) = true;
t.scalarMap(strcat(base, 'EnableParams.enableLead')) = false;
t.scalarMap(strcat(base, 'EnableParams.enableNotch')) = false;
t.scalarMap(strcat(base, 'EnableParams.enableReso')) = false;
end
