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
    end

    function returnsNoneWhenNoLoggerBin(testCase)
      out = experiment.resolve_demo_log_source(struct("raw", struct()), []);
      testCase.verifyEqual(string(out.source_name), "none");
      testCase.verifyThat(string(out.diagnostics.reason), matlab.unittest.constraints.ContainsSubstring("logger bin"));
    end
  end
end
