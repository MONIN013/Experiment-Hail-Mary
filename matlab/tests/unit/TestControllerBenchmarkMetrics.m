classdef TestControllerBenchmarkMetrics < matlab.unittest.TestCase
  methods (Test)
    function summarizesMeasuredSignalsInOneTableRow(testCase)
      entry = sample_entry();
      signals = struct( ...
        "time_s", (0:4)' * 0.1, ...
        "ref_value", [0; 1; 1; 1; 1], ...
        "position_act", [0; 0.8; 1.1; 1.01; 1], ...
        "error", [0; 0.2; -0.1; -0.01; 0], ...
        "control_input", [0; 0.4; -0.2; -0.02; 0], ...
        "current_cmd", [0; 0.39; -0.19; -0.02; 0]);

      row = experiment.exp02.controller_benchmark_metrics(entry, signals);

      testCase.verifyEqual(height(row), 1);
      testCase.verifyEqual(row.controller, "test controller");
      testCase.verifyEqual(row.trackingErrorL2, norm(signals.error), "AbsTol", 1e-12);
      testCase.verifyEqual(row.trackingErrorRms, rms(signals.error), "AbsTol", 1e-12);
      testCase.verifyEqual(row.trackingErrorPeak, 0.2, "AbsTol", 1e-12);
      testCase.verifyEqual(row.IAE, trapz(signals.time_s, abs(signals.error)), "AbsTol", 1e-12);
      testCase.verifyEqual(row.overshootRad, 0.1, "AbsTol", 1e-12);
      testCase.verifyEqual(row.settlingTimeS, 0.3, "AbsTol", 1e-12);
      testCase.verifyEqual(row.maxControlInputA, 0.4, "AbsTol", 1e-12);
      testCase.verifyEqual(row.maxCurrentCmdA, 0.39, "AbsTol", 1e-12);
      testCase.verifyTrue(row.gatePassed);
    end

    function rejectsMismatchedSignalLengths(testCase)
      entry = sample_entry();
      signals = struct( ...
        "time_s", [0; 1], "ref_value", [0; 1], ...
        "position_act", [0; 1], "error", [0; 1], ...
        "control_input", 0, "current_cmd", [0; 1]);

      testCase.verifyError(@() ...
        experiment.exp02.controller_benchmark_metrics(entry, signals), ...
        "experiment:exp02:invalidControllerBenchmarkSignals");
    end

    function normalToolDoesNotOwnVmOrOracleOperations(testCase)
      matlab_root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
      source = string(fileread(fullfile(matlab_root, "tools", "run_controller_benchmark.m")));

      testCase.verifyTrue(contains(source, "experiment.exp02.controller_catalog("));
      testCase.verifyTrue(contains(source, "experiment.exp0n.run_and_collect(cfg)"));
      testCase.verifyTrue(contains(source, "experiment.exp0n.archive_logger("));
      testCase.verifyTrue(contains(source, "logger_archive_path"));
      testCase.verifyTrue(contains(source, "virtualMotor.wait_for_settle("));
      testCase.verifyTrue(contains(source, "settle_motor_velocity_count"));
      testCase.verifyTrue(contains(source, "results_table = vertcat(rows{:});"));
      forbidden = ["virtualMotor.predict_logger(", "virtualMotor.compare_prediction(", ...
        "virtualMotor.restart_runtime(", "virtualMotor.configure("];
      for token = forbidden
        testCase.verifyFalse(contains(source, token), token);
      end
    end
  end
end

function entry = sample_entry()
Ts = 0.1;
controller_cfg = experiment.ControllerConfig.p_only(0.5);
design = struct( ...
  "max_sensitivity", 1.25, ...
  "controller_gain_200_hz", 0.5, ...
  "sos_section_count", 1, ...
  "gate_ok", true);
entry = struct( ...
  "name", "test controller", ...
  "family", "test", ...
  "K", tf(0.5), ...
  "Kd", tf(0.5, 1, Ts), ...
  "controller_cfg", controller_cfg, ...
  "design", design);
end
