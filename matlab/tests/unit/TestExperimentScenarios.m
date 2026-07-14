classdef TestExperimentScenarios < matlab.unittest.TestCase
  methods (Test)
    function buildsShortSystemIdentificationScenario(testCase)
      temporary_folder = testCase.applyFixture( ...
        matlab.unittest.fixtures.TemporaryFolderFixture);

      scenario = experiment.scenario.exp01( ...
        "Tend", 0.06, "Tcycle", 0.02, "transient_cycles", 1, ...
        "f0", 20, "f1", 1000, "save_results", false, ...
        "result_dir", temporary_folder.Folder);

      testCase.verifyEqual(scenario.name, "exp01");
      testCase.verifyEqual(scenario.Ts, 1 / 8000, "AbsTol", eps);
      testCase.verifyEqual(scenario.expected_sample_count, 480);
      testCase.verifyNumElements(scenario.cfg.ref_profile, 160);
      testCase.verifyNumElements(scenario.cfg.ff_profile, 160);
      testCase.verifyEqual(scenario.cfg.repeat_count, 3);
      testCase.verifyEqual(scenario.cfg.ref_profile, zeros(160, 1));
      testCase.verifyEqual(scenario.cfg.ff_profile, ...
        scenario.chirp.signal(1:160));
      testCase.verifyEqual(mean(scenario.cfg.ff_profile), 0, ...
        "AbsTol", 32 * eps);
      testCase.verifyEqual(max(abs(scenario.cfg.ff_profile)), 0.25, ...
        "AbsTol", 32 * eps);
      testCase.verifyEqual(scenario.chirp.applied_mean_A, 0, ...
        "AbsTol", 32 * eps);
      testCase.verifyTrue(scenario.cfg.external_host_heartbeat_enable);
      testCase.verifyFalse(scenario.cfg.host_heartbeat_enable);
      testCase.verifyEqual(string(scenario.cfg.save_path), "");
      testCase.verifyFalse(scenario.save_results);
      testCase.verifyFalse(isfile(scenario.paths.chirp_result));
      testCase.verifyFalse(isfile(scenario.paths.plant));
    end

    function buildsFeedbackAndFeedforwardScenarios(testCase)
      [plant, trajectory, controller] = testCase.syntheticInputs();

      feedback = experiment.scenario.exp02(plant, trajectory, ...
        "Kd", controller, "repeat_count", 2, "save_results", false);
      feedforward = experiment.scenario.exp03(plant, trajectory, ...
        "Kd", controller, "repeat_count", 2, "save_results", false);

      sample_count = numel(trajectory.p);
      testCase.verifyEqual(feedback.name, "exp02");
      testCase.verifyEqual(feedback.expected_sample_count, 2 * sample_count);
      testCase.verifyEqual(feedback.cfg.ref_profile, trajectory.p);
      testCase.verifyEqual(feedback.cfg.ff_profile, zeros(sample_count, 1));
      testCase.verifyTrue(feedback.stability.ok);
      testCase.verifyFalse(feedback.save_results);

      unshifted = plant.Jn * trajectory.a + plant.Dn * trajectory.v;
      expected_feedforward = [ ...
        unshifted(1 + plant.Ndelay:end); ...
        repmat(unshifted(end), plant.Ndelay, 1)];
      testCase.verifyEqual(feedforward.name, "exp03");
      testCase.verifyEqual(feedforward.expected_sample_count, 2 * sample_count);
      testCase.verifyEqual(feedforward.feedforward, expected_feedforward, ...
        "AbsTol", 4 * eps(max(abs(expected_feedforward))));
      testCase.verifyEqual(feedforward.cfg.ff_profile, expected_feedforward, ...
        "AbsTol", 4 * eps(max(abs(expected_feedforward))));
      testCase.verifyEqual(feedforward.feedforward_gains.Kfa, plant.Jn);
      testCase.verifyEqual(feedforward.feedforward_gains.Kfv, plant.Dn);
      testCase.verifyEqual(feedforward.feedforward_gains.Kfc, 0);
      testCase.verifyFalse(feedforward.save_results);
    end

    function buildsIlcScenarioWithoutExecutingATrial(testCase)
      [plant, trajectory, controller] = testCase.syntheticInputs();

      scenario = experiment.scenario.exp04(plant, trajectory, ...
        "Kd", controller, "trial_count", 3, "alpha", 0.6, ...
        "noQ", true, "Npad", 0, "transient_samples", 0, ...
        "save_results", false);

      testCase.verifyEqual(scenario.name, "exp04");
      testCase.verifyEqual(scenario.trial_count, 3);
      tail_count = 9 * 8000;
      testCase.verifyEqual(scenario.expected_sample_count, ...
        numel(trajectory.p) + tail_count);
      testCase.verifyEqual(scenario.cfg.ref_profile, ...
        [trajectory.p; zeros(tail_count, 1)]);
      testCase.verifyEqual(scenario.cfg.ff_profile, ...
        zeros(numel(trajectory.p) + tail_count, 1));
      testCase.verifyEqual(scenario.settling_tail_s, 9);
      testCase.verifyEqual(scenario.settling_tail_samples, tail_count);
      testCase.verifyEqual(scenario.learning_sample_count, ...
        numel(trajectory.p));
      testCase.verifyEqual(scenario.learning_filters.max_convergence_gain, ...
        0.4, "AbsTol", 1e-12);
      testCase.verifyEqual(scenario.learning_error_quantum_rad, ...
        2*pi/8388608);
      testCase.verifyEqual(scenario.learning_filters.error_quantum_rad, ...
        scenario.learning_error_quantum_rad);
      testCase.verifyTrue(scenario.stability.ok);
      testCase.verifyFalse(scenario.save_results);
    end

    function runtimeScenariosAndWorkflowsContainNoVmOracleOrRestart(testCase)
      matlab_root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
      relative_paths = [ ...
        "+experiment/+scenario/exp01.m"
        "+experiment/+scenario/exp02.m"
        "+experiment/+scenario/exp03.m"
        "+experiment/+scenario/exp04.m"
        "+experiment/+workflow/run_exp01.m"
        "+experiment/+workflow/run_exp02.m"
        "+experiment/+workflow/run_exp03.m"
        "+experiment/+workflow/run_exp04.m"];
      source = "";
      for relative_path = relative_paths'
        source = source + newline + string(fileread( ...
          fullfile(matlab_root, relative_path)));
      end
      source = lower(source);

      testCase.verifyFalse(contains(source, "virtualmotor"));
      testCase.verifyFalse(contains(source, "predict_logger"));
      testCase.verifyFalse(contains(source, "testoracle"));
      testCase.verifyFalse(contains(source, "restart"));
    end
  end

  methods (Static, Access = private)
    function [plant, trajectory, controller] = syntheticInputs()
      Ts = 1 / 8000;
      sample_count = 64;
      t = (0:sample_count - 1)' * Ts;
      frequency_hz = 125;
      p = 0.2 * sin(2*pi*frequency_hz*t);
      v = 0.2 * 2*pi*frequency_hz * cos(2*pi*frequency_hz*t);
      a = -0.2 * (2*pi*frequency_hz)^2 * sin(2*pi*frequency_hz*t);
      trajectory = struct("t", t, "p", p, "v", v, "a", a);
      plant = struct( ...
        "Pd", tf(1, 1, Ts), "Pdn", tf(1, 1, Ts), ...
        "Jn", 7.1e-5, "Dn", 5.325e-4, "Ndelay", 4, "Ts", Ts);
      controller = tf(0, 1, Ts);
    end
  end
end
