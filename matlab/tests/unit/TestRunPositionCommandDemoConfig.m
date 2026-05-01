classdef TestRunPositionCommandDemoConfig < matlab.unittest.TestCase
  methods (Test)
    function demoUsesExperimentConfigAndEnvironmentLoggerPath(testCase)
      script_path = fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "tools", "run_position_command_demo.m");
      source = string(fileread(script_path));

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg = experiment.ExperimentConfig.defaults();"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        'logger_dir = string(fileparts(char(cfg.env.logger_host_file_path)));'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "out = experiment.ExperimentRunner.run(conn, cfg);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "conn = experiment.ConnectionManager.create(cfg);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "out.metrics"));
      testCase.verifyFalse(contains(source, "logger_share_dir ="));
      testCase.verifyFalse(contains(source, "experiment.send_position_command("));
      testCase.verifyFalse(contains(source, "out.eval"));
      testCase.verifyFalse(contains(source, "restoredefaultpath;"));
      testCase.verifyFalse(contains(source, "addpath(genpath("));
    end

    function demoAssignsPlantControllerAndRuntimeFieldsOnCfg(testCase)
      script_path = fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "tools", "run_position_command_demo.m");
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

    function loggerDirectoryDerivesFromEnvironmentConfig(testCase)
      env = config.EnvironmentConfig.defaults();
      logger_path = string(env.logger_host_file_path);
      testCase.verifyEqual( ...
        string(fileparts(char(logger_path))), ...
        string(fileparts(char(config.EnvironmentConfig.DEFAULT_LOGGER_HOST_FILE_PATH))));
    end
  end
end
