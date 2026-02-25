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
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_array:GVL_SEQ.refTable"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_array:GVL_SEQ.ffTable"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_array:GVL_SEQ.distTable"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_SEQ.tableLen"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_SEQ.experimentActive"));
    end

    function streamingModeDrainsLogsDuringRun(testCase)
      plc = MockAdsTransport();
      module = MockAdsTransport();
      seedPlcScalars(plc);
      seedVmScalars(module, "VirtualMotor.");
      seedControllerScalars(module, "ControllerCore.");
      plc.arrayMap("GVL_SEQ_LOG.logRefValue") = [0.1; 0.2; 0.3];
      plc.arrayMap("GVL_SEQ_LOG.logFfValue") = [0.0; 0.0; 0.0];
      plc.arrayMap("GVL_SEQ_LOG.logDistValue") = [0.0; 0.0; 0.0];
      plc.arrayMap("GVL_SEQ_LOG.logControlInput") = [1.0; 1.1; 1.2];
      plc.arrayMap("GVL_SEQ_LOG.logTargetTorque") = [1.0; 1.1; 1.2];
      plc.arrayMap("GVL_SEQ_LOG.logPositionAct") = [0.0; 0.01; 0.02];
      plc.arrayMap("GVL_SEQ_LOG.logT") = uint64([1000; 2000; 3000]);
      plc.arrayMap("GVL_SEQ_LOG.logIdx") = uint32([0; 1; 2]);
      plc.set_scalar_read_sequence("GVL_SEQ_LOG.wrIdx", [0; 0; 3; 3]);
      plc.set_scalar_read_sequence("GVL_SEQ.experimentActive", [false; true; false]);
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
      testCase.verifyEqual(out.raw.logRefValue(:), [0.1; 0.2; 0.3]);
      testCase.verifyTrue(out.host.log_stream_enabled);
      testCase.verifyEqual(out.host.log_samples_captured, 3);
      joined = strjoin(plc.operations, "|");
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("read_array_slice:GVL_SEQ_LOG.logRefValue"));
      testCase.verifyThat(joined, matlab.unittest.constraints.ContainsSubstring("write_scalar:GVL_SEQ_LOG.rdIdx"));
    end

    function streamingFailureRaisesInStrictMode(testCase)
      plc = MockAdsTransport();
      module = MockAdsTransport();
      seedPlcScalars(plc);
      seedVmScalars(module, "VirtualMotor.");
      seedControllerScalars(module, "ControllerCore.");
      seedPlcLogArrays(plc);
      plc.set_scalar_read_sequence("GVL_SEQ_LOG.wrIdx", [0; 0; 3; 3]);
      plc.set_scalar_read_sequence("GVL_SEQ.experimentActive", [false; false; true; false]);
      plc.set_read_array_slice_error("GVL_SEQ_LOG.logRefValue", "mock:readArraySliceFailure", "Injected slice read failure");
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
t.scalarMap("GVL_SEQ.resetReq") = false;
t.scalarMap("GVL_SEQ.experimentActive") = false;
t.scalarMap("GVL_SEQ.tableLen") = uint32(0);
t.scalarMap("GVL_SEQ.idx") = uint32(0);
t.scalarMap("GVL_SEQ.refValue") = 0.0;
t.scalarMap("GVL_SEQ.ffValue") = 0.0;
t.scalarMap("GVL_SEQ.distValue") = 0.0;
t.scalarMap("GVL_SEQ_LOG.controlInputTap") = 0.0;
t.scalarMap("GVL_SEQ_LOG.positionActTap") = 0.0;
t.scalarMap("GVL_SEQ_LOG.wrIdx") = uint32(0);
t.scalarMap("GVL_SEQ_LOG.rdIdx") = uint32(0);
t.scalarMap("GVL_SEQ_LOG.overflow") = false;
t.scalarMap("GVL_SEQ_LOG.LOG_N") = uint32(200000);
seedPlcLogArrays(t);
end

function seedPlcLogArrays(t)
t.arrayMap("GVL_SEQ_LOG.logSeq") = uint32([]);
t.arrayMap("GVL_SEQ_LOG.logRefValue") = [];
t.arrayMap("GVL_SEQ_LOG.logFfValue") = [];
t.arrayMap("GVL_SEQ_LOG.logDistValue") = [];
t.arrayMap("GVL_SEQ_LOG.logControlInput") = [];
t.arrayMap("GVL_SEQ_LOG.logTargetTorque") = [];
t.arrayMap("GVL_SEQ_LOG.logPositionAct") = [];
t.arrayMap("GVL_SEQ_LOG.logT") = uint64([]);
t.arrayMap("GVL_SEQ_LOG.logIdx") = uint32([]);
end

function seedVmScalars(t, prefix)
base = char(string(prefix));
t.scalarMap(strcat(base, 'M')) = 1.0;
t.scalarMap(strcat(base, 'D')) = 1.0;
t.scalarMap(strcat(base, 'Kt')) = 1.0;
t.scalarMap(strcat(base, 'tauLimit')) = 1.0;
t.scalarMap(strcat(base, 'velLimit')) = 1.0;
t.scalarMap(strcat(base, 'taskDtNs')) = uint64(1000);
end

function seedControllerScalars(t, prefix)
base = char(string(prefix));
keys = {
  'PIDParams.notchB0','PIDParams.notchB1','PIDParams.notchB2','PIDParams.notchA1','PIDParams.notchA2', ...
  'LeadParams.notchB0','LeadParams.notchB1','LeadParams.notchB2','LeadParams.notchA1','LeadParams.notchA2', ...
  'NotchParams.notchB0','NotchParams.notchB1','NotchParams.notchB2','NotchParams.notchA1','NotchParams.notchA2', ...
  'ResoParams.notchB0','ResoParams.notchB1','ResoParams.notchB2','ResoParams.notchA1','ResoParams.notchA2'};
for i = 1:numel(keys)
  t.scalarMap(strcat(base, keys{i})) = 0.0;
end
t.scalarMap(strcat(base, 'EnableParams.enablePid')) = true;
t.scalarMap(strcat(base, 'EnableParams.enableLead')) = false;
t.scalarMap(strcat(base, 'EnableParams.enableNotch')) = false;
t.scalarMap(strcat(base, 'EnableParams.enableReso')) = false;
end


