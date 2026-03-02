classdef TestWriteHelpers < matlab.unittest.TestCase
  methods (Test)
    function writeRefTableSetsTableAndLen(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      ref = [0.1; 0.2; 0.3];
      experiment.write_ref_table(tr, ref, 10);
      testCase.verifyEqual(double(tr.arrayMap("GVL_SEQ.refTable")), ref);
      testCase.verifyEqual(tr.scalarMap("GVL_SEQ.tableLen"), uint32(3));
    end

    function writeRefTableRejectsTooLong(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      ref = zeros(4, 1);
      testCase.verifyError(@() experiment.write_ref_table(tr, ref, 3), ...
        "experiment:write_ref_table:tooLong");
    end

    function writeFfTableWritesArray(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      ff = [0.5; 0.6; 0.7];
      experiment.write_ff_table(tr, ff, 3);
      testCase.verifyEqual(double(tr.arrayMap("GVL_SEQ.ffTable")), ff);
    end

    function writeFfTableErrorsOnLengthMismatch(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      testCase.verifyError(@() experiment.write_ff_table(tr, [0.1; 0.2], 3), ...
        "experiment:write_ff_table:lengthMismatch");
    end

    function writeDistTableWritesArray(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      dist = [1.0; 2.0];
      experiment.write_dist_table(tr, dist, 2);
      testCase.verifyEqual(double(tr.arrayMap("GVL_SEQ.distTable")), dist);
    end

    function writeDistTableErrorsOnLengthMismatch(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      testCase.verifyError(@() experiment.write_dist_table(tr, [1.0; 2.0], 3), ...
        "experiment:write_dist_table:lengthMismatch");
    end

    function writeVmParamsWritesAllFieldsToExplicitPrefix(testCase)
      tr = MockAdsTransport();
      seedModuleDefaults(tr, "CustomVm.");
      params = struct("m", 1.0, "d", 6.0, "rated_current", 0.1, "max_permille", 750, "tau_limit", 100, "vel_limit", 10);
      experiment.write_vm_params(tr, "CustomVm.", params, uint64(1234));

      testCase.verifyEqual(tr.scalarMap("CustomVm.mass"), 1.0);
      testCase.verifyEqual(tr.scalarMap("CustomVm.damping"), 6.0);
      testCase.verifyEqual(tr.scalarMap("CustomVm.ratedTorque"), 0.1);
      testCase.verifyEqual(tr.scalarMap("CustomVm.maxPermille"), 750.0);
      testCase.verifyEqual(tr.scalarMap("CustomVm.tauLimit"), 100.0);
      testCase.verifyEqual(tr.scalarMap("CustomVm.velLimit"), 10.0);
      testCase.verifyEqual(tr.scalarMap("CustomVm.taskDtNs"), uint64(1234));
    end

    function writeControllerParamsWritesAllStagesToExplicitPrefix(testCase)
      tr = MockAdsTransport();
      seedModuleDefaults(tr, "Vm.", "CustomCtrl.");
      params = default_controller_params();
      params.pid_b0 = 180;
      params.lead_b0 = 42;
      params.notch_b0 = 99;
      params.reso_b0 = 7;
      experiment.write_controller_params(tr, "CustomCtrl.", params);

      testCase.verifyEqual(tr.scalarMap("CustomCtrl.PIDParams.pidB0"), 180.0);
      testCase.verifyEqual(tr.scalarMap("CustomCtrl.LeadParams.leadB0"), 42.0);
      testCase.verifyEqual(tr.scalarMap("CustomCtrl.NotchParams.notchB0"), 99.0);
      testCase.verifyEqual(tr.scalarMap("CustomCtrl.ResoParams.resoB0"), 7.0);
      testCase.verifyEqual(tr.scalarMap("CustomCtrl.EnableParams.enablePid"), true);
      testCase.verifyEqual(tr.scalarMap("CustomCtrl.EnableParams.enableLead"), false);
    end

    function readExperimentLogsUsesExplicitLogLimit(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      seedLogArrays(tr, 3);
      tr.scalarMap("GVL_SEQ_LOG.wrIdx") = uint32(3);
      tr.scalarMap("GVL_SEQ_LOG.overflow") = false;

      log_data = experiment.read_experiment_logs(tr, 2);
      testCase.verifyEqual(log_data.logRefValue(:), [0.1; 0.2], "AbsTol", 1e-12);
      testCase.verifyEqual(log_data.wrIdx, 3);
      testCase.verifyFalse(log_data.overflow);
    end

    function readExperimentLogsReturnsEmptyWhenNothingWritten(testCase)
      tr = MockAdsTransport();
      seedPlcDefaults(tr);
      seedLogArrays(tr, 0);
      tr.scalarMap("GVL_SEQ_LOG.wrIdx") = uint32(0);
      tr.scalarMap("GVL_SEQ_LOG.overflow") = false;

      log_data = experiment.read_experiment_logs(tr, 10);
      testCase.verifyEmpty(log_data.logRefValue);
      testCase.verifyEqual(log_data.wrIdx, 0);
    end

    function readExperimentLogsWarnsOnFailure(testCase)
      tr = MockAdsTransport();
      testCase.verifyWarning(@() experiment.read_experiment_logs(tr, 10), ...
        "experiment:read_experiment_logs:unavailable");
    end
  end
end

function seedPlcDefaults(tr)
  tr.scalarMap("GVL_SEQ.tableLen") = uint32(0);
end

function seedModuleDefaults(tr, vm_prefix, ctrl_prefix)
  if nargin < 2
    vm_prefix = "CustomVm.";
  end
  if nargin < 3
    ctrl_prefix = "CustomCtrl.";
  end
  vm_prefix = char(string(vm_prefix));
  ctrl_prefix = char(string(ctrl_prefix));
  tr.scalarMap(strcat(vm_prefix, 'mass')) = 0.0;
  tr.scalarMap(strcat(vm_prefix, 'damping')) = 0.0;
  tr.scalarMap(strcat(vm_prefix, 'ratedTorque')) = 0.0;
  tr.scalarMap(strcat(vm_prefix, 'maxPermille')) = 0.0;
  tr.scalarMap(strcat(vm_prefix, 'tauLimit')) = 0.0;
  tr.scalarMap(strcat(vm_prefix, 'velLimit')) = 0.0;
  tr.scalarMap(strcat(vm_prefix, 'taskDtNs')) = uint64(0);

  stages = {'PIDParams.pidB', 'LeadParams.leadB', 'NotchParams.notchB', 'ResoParams.resoB'};
  a_stages = {'PIDParams.pidA', 'LeadParams.leadA', 'NotchParams.notchA', 'ResoParams.resoA'};
  for s = 1:4
    for k = 0:2
      tr.scalarMap(strcat(ctrl_prefix, stages{s}, num2str(k))) = 0.0;
    end
    for k = 1:2
      tr.scalarMap(strcat(ctrl_prefix, a_stages{s}, num2str(k))) = 0.0;
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
    tr.arrayMap("GVL_SEQ_LOG.logTargetCurrent") = ones(n, 1);
    tr.arrayMap("GVL_SEQ_LOG.logPositionAct") = (0:n-1)' * 0.01;
    tr.arrayMap("GVL_SEQ_LOG.logT") = uint64((1:n)' * 1000);
    tr.arrayMap("GVL_SEQ_LOG.logIdx") = uint32((0:n-1)');
  else
    tr.arrayMap("GVL_SEQ_LOG.logSeq") = uint32([]);
    tr.arrayMap("GVL_SEQ_LOG.logRefValue") = [];
    tr.arrayMap("GVL_SEQ_LOG.logFfValue") = [];
    tr.arrayMap("GVL_SEQ_LOG.logDistValue") = [];
    tr.arrayMap("GVL_SEQ_LOG.logControlInput") = [];
    tr.arrayMap("GVL_SEQ_LOG.logTargetCurrent") = [];
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
