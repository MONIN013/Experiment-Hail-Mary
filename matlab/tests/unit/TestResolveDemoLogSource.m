classdef TestResolveDemoLogSource < matlab.unittest.TestCase
  methods (Test)
    function usesLoggerBinWhenAvailable(testCase)
      run_out = struct("cmd", struct("task_rate_hz", 1000), "raw", struct());
      logger_bin = struct( ...
        "record_count", 2, ...
        "raw", struct( ...
          "t_s", [0; 0.001], ...
          "ref_value", [0.1; 0.2], ...
          "load_position", [0.0; 0.01], ...
          "control_input", [1.0; 1.1], ...
          "current_cmd", [1.0; 1.1]));

      out = experiment.resolve_demo_log_source(run_out, logger_bin);

      testCase.verifyEqual(string(out.source_name), "experiment_logger_bin");
      testCase.verifyEqual(out.signals.position_act(:), [0.0; 0.01]);
      testCase.verifyEqual(out.signals.control_input(:), [1.0; 1.1]);
    end

    function fallsBackToGvlSeqLog(testCase)
      run_out = struct( ...
        "cmd", struct("task_rate_hz", 1000), ...
        "raw", struct( ...
          "logRefValue", [0.1; 0.2], ...
          "logPositionAct", [0.0; 0.01], ...
          "logControlInput", [1.0; 1.1], ...
          "logTargetCurrent", [1.0; 1.1]));

      out = experiment.resolve_demo_log_source(run_out, []);

      testCase.verifyEqual(string(out.source_name), "gvl_seq_log_fallback");
      testCase.verifyEqual(out.signals.time_s(:), [0; 0.001], "AbsTol", 1e-12);
      testCase.verifyEqual(out.signals.ref_value(:), [0.1; 0.2]);
    end

    function returnsNoneWhenNoLogs(testCase)
      run_out = struct("cmd", struct("task_rate_hz", 1000), "raw", struct("logPositionAct", []));

      out = experiment.resolve_demo_log_source(run_out, []);

      testCase.verifyEqual(string(out.source_name), "none");
      testCase.verifyEmpty(out.signals.position_act);
    end
  end
end
