classdef TestRunPositionCommandDemoConfig < matlab.unittest.TestCase
  methods (Test)
    function demoUsesExperimentConfigAndSystemLoggerPath(testCase)
      script_path = fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "run_position_command_demo.m");
      source = string(fileread(script_path));

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg = experiment.ExperimentConfig.defaults();"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        'logger_dir = string(fileparts(char(sys.LOGGER_DEFAULT_FILE_PATH)));'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "out = experiment.ExperimentRunner.run(conn, cfg);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "conn = experiment.ConnectionManager.create(cfg);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "out.metrics"));
      testCase.verifyFalse(contains(source, "logger_share_dir ="));
      testCase.verifyFalse(contains(source, "experiment.send_position_command("));
      testCase.verifyFalse(contains(source, "out.eval"));
    end

    function demoAssignsPlantControllerAndRuntimeFieldsOnCfg(testCase)
      script_path = fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "run_position_command_demo.m");
      source = string(fileread(script_path));

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "vm_cfg = virtualMotor.PlantConfig();"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.controller = experiment.ControllerConfig.p_only(Kp);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.repeat_count = N_REPEAT;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.hold_seconds = per_trial_s + hold_margin_s;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.done_timeout_s = N_REPEAT * per_trial_s + hold_margin_s + 5.0;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "virtualMotor.writeParams(conn, vm_cfg);"));
      testCase.verifyFalse(contains(source, "cfg.plant ="));
    end

    function loggerDirectoryDerivesFromSystemConfig(testCase)
      logger_path = string(experiment.SystemConfig.LOGGER_DEFAULT_FILE_PATH);
      testCase.verifyEqual( ...
        string(fileparts(char(logger_path))), ...
        "\\sunnyday\ExperimentData");
    end
  end
end
