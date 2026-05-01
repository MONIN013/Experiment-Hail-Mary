classdef TestExperimentConfig < matlab.unittest.TestCase
  methods (Test)
    function defaultsUseEnvironmentConfig(testCase)
      cfg = experiment.ExperimentConfig.defaults();
      env = config.EnvironmentConfig.current();
      testCase.verifyTrue(isa(cfg.env, "config.EnvironmentConfig"));
      testCase.verifyFalse(isprop(cfg, "ams_net_id"));
      testCase.verifyFalse(isprop(cfg, "seq_port"));
      testCase.verifyFalse(isprop(cfg, "task_rate_hz"));
      testCase.verifyEqual(string(cfg.env.ams_net_id), env.ams_net_id);
      testCase.verifyEqual(cfg.env.seq_port, double(env.seq_port));
      testCase.verifyEqual(cfg.env.control_port, double(env.control_port));
      testCase.verifyEqual(cfg.env.module_port, double(env.module_port));
      testCase.verifyEqual(cfg.logger_release_timeout_s, double(env.logger_release_timeout_s));
      testCase.verifyFalse(isprop(cfg, "plant"));
    end

    function flatEnvironmentOverridesFoldIntoEnv(testCase)
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [1; 2], ...
        "ams_net_id", "9.8.7.6.5.4", ...
        "task_rate_hz", 4000, ...
        "controller_param_symbol_prefix", "ControllerX.");
      testCase.verifyEqual(cfg.env.ams_net_id, "9.8.7.6.5.4");
      testCase.verifyEqual(cfg.env.task_rate_hz, 4000);
      testCase.verifyEqual(cfg.env.controller_prefix, "ControllerX.");
    end

    function rejectsLegacyAliasesAndRemovedBridgeFiles(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ams_port", 851, ...
        "ref_profile", [1; 2])), "experiment:config:invalid");
      testCase.verifyEqual(which("experiment.RunConfig"), '');
      testCase.verifyEqual(which("experiment.PositionCommandConfig"), '');
    end

    function rejectsRemovedVmFields(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [1; 2], ...
        "vm_param_symbol_prefix", "Vm."), "MATLAB:InputParser:UnmatchedParameter");
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [1; 2], ...
        "plant", struct())), "experiment:config:invalid");
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [1; 2], ...
        "write_plant_params", true)), "experiment:config:invalid");
    end

    function rejectsWaveformLongerThanReference(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [1; 2], ...
        "dist_profile", [0; 0; 0]), "experiment:config:invalid");
    end

    function rejectsLegacyPlantAliases(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [1; 2], ...
        "m", 0.1)), "experiment:config:invalid");
    end
  end
end
