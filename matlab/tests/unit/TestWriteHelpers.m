classdef TestWriteHelpers < matlab.unittest.TestCase
  methods (Test)
    %% write_ref_table
    function writeRefTableSetsTableAndLen(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      ref = [0.1; 0.2; 0.3];
      experiment.write_ref_table(tr, ref);
      testCase.verifyEqual(double(tr.arrayMap("GVL_SEQ.refTable")), ref);
      testCase.verifyEqual(tr.scalarMap("GVL_SEQ.tableLen"), uint32(3));
    end

    function writeRefTableRejectsTooLong(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      ref = zeros(experiment.SystemConfig.TABLE_MAX_N + 1, 1);
      testCase.verifyError(@() experiment.write_ref_table(tr, ref), ...
        "experiment:write_ref_table:tooLong");
    end

    %% write_ff_table
    function writeFfTableWritesArray(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      tr.scalarMap("GVL_SEQ.tableLen") = uint32(3);
      ff = [0.5; 0.6; 0.7];
      experiment.write_ff_table(tr, ff);
      testCase.verifyEqual(double(tr.arrayMap("GVL_SEQ.ffTable")), ff);
    end

    function writeFfTableWarnsOnLengthMismatch(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      tr.scalarMap("GVL_SEQ.tableLen") = uint32(5);
      testCase.verifyWarning(@() experiment.write_ff_table(tr, [0.1; 0.2]), ...
        "experiment:write_ff_table:lengthMismatch");
    end

    %% write_dist_table
    function writeDistTableWritesArray(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      dist = [1.0; 2.0];
      experiment.write_dist_table(tr, dist);
      testCase.verifyEqual(double(tr.arrayMap("GVL_SEQ.distTable")), dist);
    end

    %% write_vm_params
    function writeVmParamsWritesAllFields(testCase)
      tr = MockAdsTransport();
      seedModuleDefaults(tr);
      params = struct("m", 1.0, "d", 6.0, "kt", 0.1, "tau_limit", 100, "vel_limit", 10);
      experiment.write_vm_params(tr, params);

      sys = experiment.SystemConfig;
      prefix = char(sys.VM_PREFIX);
      testCase.verifyEqual(tr.scalarMap(strcat(prefix, 'mass')), 1.0);
      testCase.verifyEqual(tr.scalarMap(strcat(prefix, 'damping')), 6.0);
      testCase.verifyEqual(tr.scalarMap(strcat(prefix, 'torqueConstant')), 0.1);
      testCase.verifyEqual(tr.scalarMap(strcat(prefix, 'tauLimit')), 100.0);
      testCase.verifyEqual(tr.scalarMap(strcat(prefix, 'velLimit')), 10.0);
      testCase.verifyEqual(tr.scalarMap(strcat(prefix, 'taskDtNs')), uint64(1000000));
    end

    %% write_controller_params
    function writeControllerParamsWritesPidBiquad(testCase)
      tr = MockAdsTransport();
      seedModuleDefaults(tr);
      params = default_controller_params();
      params.pid_b0 = 180;
      experiment.write_controller_params(tr, params);

      sys = experiment.SystemConfig;
      prefix = char(sys.CTRL_PREFIX);
      testCase.verifyEqual(tr.scalarMap(strcat(prefix, 'PIDParams.pidB0')), 180.0);
      testCase.verifyEqual(tr.scalarMap(strcat(prefix, 'PIDParams.pidB1')), 0.0);
      testCase.verifyEqual(tr.scalarMap(strcat(prefix, 'EnableParams.enablePid')), true);
      testCase.verifyEqual(tr.scalarMap(strcat(prefix, 'EnableParams.enableLead')), false);
    end

    function writeControllerParamsWritesAllStages(testCase)
      tr = MockAdsTransport();
      seedModuleDefaults(tr);
      params = default_controller_params();
      params.lead_b0 = 42;
      params.notch_b0 = 99;
      params.reso_b0 = 7;
      experiment.write_controller_params(tr, params);

      sys = experiment.SystemConfig;
      prefix = char(sys.CTRL_PREFIX);
      testCase.verifyEqual(tr.scalarMap(strcat(prefix, 'LeadParams.leadB0')), 42.0);
      testCase.verifyEqual(tr.scalarMap(strcat(prefix, 'NotchParams.notchB0')), 99.0);
      testCase.verifyEqual(tr.scalarMap(strcat(prefix, 'ResoParams.resoB0')), 7.0);
    end

    %% read_experiment_logs
    function readExperimentLogsReturnsPopulatedStruct(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      seedLogArrays(tr, 3);
      tr.scalarMap("GVL_SEQ_LOG.wrIdx") = uint32(3);
      tr.scalarMap("GVL_SEQ_LOG.overflow") = false;

      log_data = experiment.read_experiment_logs(tr);
      testCase.verifyEqual(log_data.logRefValue(:), [0.1; 0.2; 0.3]);
      testCase.verifyEqual(log_data.wrIdx, 3);
      testCase.verifyFalse(log_data.overflow);
    end

    function readExperimentLogsReturnsEmptyWhenNothingWritten(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      seedLogArrays(tr, 0);
      tr.scalarMap("GVL_SEQ_LOG.wrIdx") = uint32(0);
      tr.scalarMap("GVL_SEQ_LOG.overflow") = false;

      log_data = experiment.read_experiment_logs(tr);
      testCase.verifyEmpty(log_data.logRefValue);
      testCase.verifyEqual(log_data.wrIdx, 0);
    end

    function readExperimentLogsWarnsOnFailure(testCase)
      tr = MockAdsTransport();
      % Don't seed anything — read_scalar will error
      testCase.verifyWarning(@() experiment.read_experiment_logs(tr), ...
        "experiment:read_experiment_logs:unavailable");
    end
  end
end

%% --- helper functions ---

function seedPlcDefaults(tr)
  tr.scalarMap("GVL_SEQ.tableLen") = uint32(0);
end

function seedModuleDefaults(tr)
  sys = experiment.SystemConfig;
  vm_prefix = char(sys.VM_PREFIX);
  tr.scalarMap(strcat(vm_prefix, 'mass')) = 0.0;
  tr.scalarMap(strcat(vm_prefix, 'damping')) = 0.0;
  tr.scalarMap(strcat(vm_prefix, 'torqueConstant')) = 0.0;
  tr.scalarMap(strcat(vm_prefix, 'tauLimit')) = 0.0;
  tr.scalarMap(strcat(vm_prefix, 'velLimit')) = 0.0;
  tr.scalarMap(strcat(vm_prefix, 'taskDtNs')) = uint64(0);

  ctrl_prefix = char(sys.CTRL_PREFIX);
  stages = {'PIDParams.pidB', 'LeadParams.leadB', 'NotchParams.notchB', 'ResoParams.resoB'};
  aStages = {'PIDParams.pidA', 'LeadParams.leadA', 'NotchParams.notchA', 'ResoParams.resoA'};
  for s = 1:4
    for k = 0:2
      tr.scalarMap(strcat(ctrl_prefix, stages{s}, num2str(k))) = 0.0;
    end
    for k = 1:2
      tr.scalarMap(strcat(ctrl_prefix, aStages{s}, num2str(k))) = 0.0;
    end
  end
  tr.scalarMap(strcat(ctrl_prefix, 'EnableParams.enablePid')) = false;
  tr.scalarMap(strcat(ctrl_prefix, 'EnableParams.enableLead')) = false;
  tr.scalarMap(strcat(ctrl_prefix, 'EnableParams.enableNotch')) = false;
  tr.scalarMap(strcat(ctrl_prefix, 'EnableParams.enableReso')) = false;
end

function seedLogArrays(tr, n)
  if n > 0
    tr.arrayMap("GVL_SEQ_LOG.logSeq") = uint32((1:n)');
    tr.arrayMap("GVL_SEQ_LOG.logRefValue") = (1:n)' * 0.1;
    tr.arrayMap("GVL_SEQ_LOG.logFfValue") = zeros(n, 1);
    tr.arrayMap("GVL_SEQ_LOG.logDistValue") = zeros(n, 1);
    tr.arrayMap("GVL_SEQ_LOG.logControlInput") = ones(n, 1);
    tr.arrayMap("GVL_SEQ_LOG.logTargetTorque") = ones(n, 1);
    tr.arrayMap("GVL_SEQ_LOG.logPositionAct") = (0:n-1)' * 0.01;
    tr.arrayMap("GVL_SEQ_LOG.logT") = uint64((1:n)' * 1000);
    tr.arrayMap("GVL_SEQ_LOG.logIdx") = uint32((0:n-1)');
  else
    tr.arrayMap("GVL_SEQ_LOG.logSeq") = uint32([]);
    tr.arrayMap("GVL_SEQ_LOG.logRefValue") = [];
    tr.arrayMap("GVL_SEQ_LOG.logFfValue") = [];
    tr.arrayMap("GVL_SEQ_LOG.logDistValue") = [];
    tr.arrayMap("GVL_SEQ_LOG.logControlInput") = [];
    tr.arrayMap("GVL_SEQ_LOG.logTargetTorque") = [];
    tr.arrayMap("GVL_SEQ_LOG.logPositionAct") = [];
    tr.arrayMap("GVL_SEQ_LOG.logT") = uint64([]);
    tr.arrayMap("GVL_SEQ_LOG.logIdx") = uint32([]);
  end
end

function p = default_controller_params()
  p = struct( ...
    "pid_b0", 0, "pid_b1", 0, "pid_b2", 0, "pid_a1", 0, "pid_a2", 0, ...
    "lead_b0", 0, "lead_b1", 0, "lead_b2", 0, "lead_a1", 0, "lead_a2", 0, ...
    "notch_b0", 0, "notch_b1", 0, "notch_b2", 0, "notch_a1", 0, "notch_a2", 0, ...
    "reso_b0", 0, "reso_b1", 0, "reso_b2", 0, "reso_a1", 0, "reso_a2", 0, ...
    "enable_pid", true, "enable_lead", false, "enable_notch", false, "enable_reso", false);
end
