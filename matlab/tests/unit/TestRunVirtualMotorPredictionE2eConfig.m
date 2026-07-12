classdef TestRunVirtualMotorPredictionE2eConfig < matlab.unittest.TestCase
  methods (Test)
    function toolKeepsRestartAndPredictionInTestOnlyEntrypoint(testCase)
      root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
      source = string(fileread(fullfile(root, "tools", ...
        "run_virtual_motor_prediction_e2e.m")));

      required = [ ...
        "virtualMotor.predict_logger(cfg)"
        "virtualMotor.restart_runtime(cfg.env)"
        "experiment.exp0n.run_and_collect(cfg)"
        "virtualMotor.compare_prediction(collect_out.logger_bin, prediction)"
        "virtualMotor.assert_prediction(metrics"];
      for value = required'
        testCase.verifyTrue(contains(source, value));
      end
      testCase.verifyTrue(contains(source, "cfg.restart_virtual_motor_runtime = false"));
      testCase.verifyTrue(contains(source, "cfg.external_host_heartbeat_enable = true"));
    end
  end
end
