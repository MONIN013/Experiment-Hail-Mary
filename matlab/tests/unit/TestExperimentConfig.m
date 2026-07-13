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
      testCase.verifyFalse(cfg.external_host_heartbeat_enable);
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

    function serializedConfigRoundTripsWithTypedController(testCase)
      cfg = experiment.ExperimentConfig.defaults();
      cfg.ref_profile = [0; 1];
      cfg.ff_profile = [0; 0];
      cfg.dist_profile = [0; 0];
      cfg.controller = experiment.ControllerConfig.p_only(2.5);

      restored = experiment.ExperimentConfig.from_struct(cfg.to_struct());

      testCase.verifyTrue(isa(restored.controller, "experiment.ControllerConfig"));
      testCase.verifyEqual(restored.controller.sos, [2.5, 0, 0, 1, 0, 0], "AbsTol", 0);
    end

    function rejectsControllerSampleTimeMismatch(testCase)
      controller = experiment.controller.from_discrete_tf(tf(1, [1, -0.5], 0.001));
      testCase.verifyError(@() experiment.ExperimentConfig.from_varargin( ...
        "controller", controller, "ref_profile", [0; 1]), ...
        "experiment:controller:sampleTimeMismatch");
    end

    function rejectsWaveformLongerThanReference(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [1; 2], ...
        "dist_profile", [0; 0; 0]), "experiment:config:invalid");
    end

    function rejectsUnknownFields(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [1; 2], ...
        "typo_timeout_s", 1)), "experiment:config:invalid");
    end

    function rejectsUnknownNameValueFields(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ref_profile", [0; 1], ...
        "pid_b0", 2.5)), "experiment:config:invalid");
      testCase.verifyError(@() experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0; 1], ...
        "enable_notch", true), "MATLAB:InputParser:UnmatchedParameter");
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

  end
end
