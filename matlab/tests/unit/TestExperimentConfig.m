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
      testCase.verifyFalse(cfg.external_host_heartbeat_enable);
      testCase.verifyFalse(cfg.write_virtual_motor_params);
      testCase.verifyFalse(cfg.restart_virtual_motor_runtime);
      testCase.verifyTrue(isempty(cfg.virtual_motor_plant));
    end

    function flatEnvironmentOverridesAreRejected(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [1; 2], ...
        "ams_net_id", "9.8.7.6.5.4"), ...
        "MATLAB:InputParser:UnmatchedParameter");
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [1; 2], "task_rate_hz", 4000)), ...
        "experiment:config:invalid");
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

    function acceptsExplicitVirtualMotorPlant(testCase)
      plant = experiment.exp01.nominal_overlay_plant();
      cfg = experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [1; 2], ...
        "write_virtual_motor_params", true, ...
        "virtual_motor_plant", plant);

      testCase.verifyTrue(cfg.write_virtual_motor_params);
      testCase.verifyTrue(isa(cfg.virtual_motor_plant, "virtualMotor.PlantConfig"));
      s = cfg.to_struct();
      testCase.verifyTrue(s.write_virtual_motor_params);
      testCase.verifyEqual(s.virtual_motor_plant.motor.inertia, 7.1e-6, "AbsTol", 1e-12);
    end

    function serializedConfigRoundTripsWithTypedController(testCase)
      cfg = experiment.ExperimentConfig.defaults();
      cfg.ref_profile = [0; 1];
      cfg.ff_profile = [0; 0];
      cfg.dist_profile = [0; 0];
      cfg.controller = experiment.ControllerConfig.p_only(2.5);
      cfg.write_virtual_motor_params = true;
      cfg.restart_virtual_motor_runtime = true;
      cfg.virtual_motor_plant = virtualMotor.PlantConfig();

      restored = experiment.ExperimentConfig.from_struct(cfg.to_struct());

      testCase.verifyTrue(isa(restored.controller, "experiment.ControllerConfig"));
      testCase.verifyEqual(restored.controller.pid.b0, 2.5, "AbsTol", 0);
      testCase.verifyTrue(restored.write_virtual_motor_params);
      testCase.verifyTrue(restored.restart_virtual_motor_runtime);
      testCase.verifyTrue(isa(restored.virtual_motor_plant, "virtualMotor.PlantConfig"));
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

    function rejectsUnknownFields(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [1; 2], ...
        "typo_timeout_s", 1)), "experiment:config:invalid");
    end

    function rejectsNonFiniteWaveforms(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [0; NaN])), "experiment:config:invalid");
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [0; 1], ...
        "ff_profile", [0; Inf])), "experiment:config:invalid");
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [0; 1], ...
        "dist_profile", [0; 1i])), "experiment:config:invalid");
    end

    function rejectsInvalidTimeoutsAndDiagnostics(testCase)
      invalid = {
        "done_timeout_s", 0;
        "reset_timeout_s", Inf;
        "hold_seconds", -1;
        "abort_check_period_s", NaN;
        "waveform_diag_max_shift_samples", 1.5;
        "waveform_diag_abs_tol", -eps;
        "waveform_diag_preview_n", 0
      };
      for k = 1:size(invalid, 1)
        s = struct("ref_profile", [0; 1]);
        s.(invalid{k, 1}) = invalid{k, 2};
        testCase.verifyError(@() experiment.ExperimentConfig.from_struct(s), ...
          "experiment:config:invalid");
      end
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [0; 1], ...
        "logger_release_timeout_s", 0)), "experiment:config:invalid");
    end

    function rejectsInvalidBooleanAndHeartbeatCombination(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [0; 1], ...
        "read_logs", 2)), "experiment:config:invalid");
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [0; 1], ...
        "host_heartbeat_enable", true, ...
        "external_host_heartbeat_enable", true)), "experiment:config:invalid");
    end

    function virtualMotorWriteRequiresPlant(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [0; 1], ...
        "write_virtual_motor_params", true)), "experiment:config:invalid");
    end

    function virtualMotorRestartRequiresParameterWrites(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [0; 1], ...
        "restart_virtual_motor_runtime", true)), "experiment:config:invalid");
    end
  end
end
