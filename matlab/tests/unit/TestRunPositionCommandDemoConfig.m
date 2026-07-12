classdef TestRunPositionCommandDemoConfig < matlab.unittest.TestCase
  methods (Test)
    function demoUsesExperimentConfigAndEnvironmentLoggerPath(testCase)
      script_path = fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "tools", "run_position_command_demo.m");
      source = string(fileread(script_path));

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg = experiment.ExperimentConfig.defaults();"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "collect_out = experiment.exp0n.run_and_collect(cfg);"));
      testCase.verifyFalse(contains(source, "virtualMotor.predict_logger("));
      testCase.verifyFalse(contains(source, "virtualMotor.compare_prediction("));
      testCase.verifyFalse(contains(source, "virtualMotor.assert_prediction("));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "out.metrics"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "logger_bin = collect_out.logger_bin;"));
      testCase.verifyFalse(contains(source, "read_latest_logger_bin"));
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
        "cfg.write_virtual_motor_params = true;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.restart_virtual_motor_runtime = false;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.host_heartbeat_enable = false;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.external_host_heartbeat_enable = true;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.virtual_motor_plant = vm_cfg;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "Kp = 0.02;"));
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
