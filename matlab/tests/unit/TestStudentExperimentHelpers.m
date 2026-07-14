classdef TestStudentExperimentHelpers < matlab.unittest.TestCase
  methods (Test)
    function stepReferenceBuildsExpectedShape(testCase)
      ref = experiment.waveform.step_reference(0.25, 0.2, 0.3, 0.1);
      testCase.verifyEqual(ref, [0; 0; 0.25; 0.25; 0.25], "AbsTol", 1e-12);
    end

    function periodicChirpWrapsExistingBuilder(testCase)
      out = experiment.waveform.periodic_chirp( ...
        "Ts", 0.01, ...
        "Tend", 1.0, ...
        "Tcycle", 1.0, ...
        "f0", 1.0, ...
        "f1", 10.0, ...
        "A", 0.2);
      testCase.verifyEqual(out.sample_count, 100);
      testCase.verifySize(out.signal, [100, 1]);
    end

    function controllerConfigFromDiscreteTfUsesSosBank(testCase)
      discrete_tf = tf([2 -1], [1 -0.5], 0.001);
      cfg = experiment.controller.from_discrete_tf(discrete_tf);
      testCase.verifySize(cfg.sos, [1, 6]);
      testCase.verifyEqual(cfg.sample_time_s, 0.001, "AbsTol", 0);
      testCase.verifyEqual(cfg.sos(1, 1), 2, "AbsTol", 1e-12);
      testCase.verifyEqual(cfg.sos(1, 2), -1, "AbsTol", 1e-12);
      testCase.verifyEqual(cfg.sos(1, 5), -0.5, "AbsTol", 1e-12);
    end

    function controllerConfigFromDiscreteTfSupportsMultipleSections(testCase)
      discrete_tf = tf([1, 0.2, 0.3, 0.1, 0.05], ...
        [1, -0.4, 0.2, -0.1, 0.01], 0.001);
      cfg = experiment.controller.from_discrete_tf(discrete_tf);
      testCase.verifyEqual(size(cfg.sos, 1), 2);
      testCase.verifyEqual(cfg.sos(:, 4), ones(2, 1), "AbsTol", 1e-12);
    end

    function controllerConfigPreservesStrictlyProperDelay(testCase)
      Ts = 0.001;
      discrete_tf = tf(1, [1, -0.5], Ts);
      cfg = experiment.controller.from_discrete_tf(discrete_tf);
      x = [1; zeros(15, 1)];
      expected = lsim(discrete_tf, x, (0:numel(x)-1)' * Ts);
      actual = sosfilt(cfg.sos, x);

      testCase.verifyEqual(actual, expected, "AbsTol", 1e-12);
      testCase.verifyEqual(cfg.sos(1, 1), 0, "AbsTol", 0);
    end

    function zeroDiscreteControllerRemainsAnExplicitZeroSection(testCase)
      cfg = experiment.controller.from_discrete_tf(tf(0, 1, 0.001));
      testCase.verifyEqual(size(cfg.sos, 1), 1);
      testCase.verifyEqual(cfg.sos(1, 1:3), [0, 0, 0], "AbsTol", 0);
    end

    function controllerConfigFromDiscreteTfRejectsContinuousAndMimo(testCase)
      testCase.verifyError(@() experiment.controller.from_discrete_tf(tf(1, [1, 1])), ...
        "experiment:controller:invalidController");
      mimo = tf({1, 2}, {1, 1}, 0.001);
      testCase.verifyError(@() experiment.controller.from_discrete_tf(mimo), ...
        "experiment:controller:invalidController");
      unspecified = tf(1, [1, -0.5], -1);
      testCase.verifyError(@() experiment.controller.from_discrete_tf(unspecified), ...
        "experiment:controller:invalidController");
    end

    function loadReferenceProfileFromMatReadsColumnVector(testCase)
      temp_dir = tempname;
      mkdir(temp_dir);
      cleaner = onCleanup(@() rmdir(temp_dir, "s"));
      file_path = fullfile(temp_dir, "trajectory.mat");
      ref_profile = [1 2 3];
      save(file_path, "ref_profile");

      out = experiment.io.load_reference_profile_from_mat(file_path, "ref_profile");
      testCase.verifyEqual(out, [1; 2; 3]);
    end

    function discreteVirtualMotorFrfUsesCanonicalPlantAndDelay(testCase)
      plant = virtualMotor.PlantConfig();
      plant = virtualMotor.PlantConfig.from_struct(plant.to_struct());
      Ts = 1 / 8000;
      omega = 2*pi*[1; 200];
      frf = virtualMotor.discrete_velocity_frf( ...
        plant, omega, "Ts", Ts, "sample_delay", 4, "axis", "load");
      frf_without_delay = virtualMotor.discrete_velocity_frf( ...
        plant, omega, "Ts", Ts, "sample_delay", 0, "axis", "load");
      frf_half_torque_per_amp = virtualMotor.discrete_velocity_frf( ...
        plant, omega, "Ts", Ts, "sample_delay", 4, ...
        "rated_current_A", 3.2, "axis", "load");
      testCase.verifySize(frf, [2, 1]);
      testCase.verifyTrue(all(isfinite(real(frf))));
      testCase.verifyTrue(all(isfinite(imag(frf))));
      testCase.verifyEqual(frf, frf_without_delay .* exp(-1i * omega * Ts * 4), ...
        "RelTol", 1e-12);
      testCase.verifyEqual(frf, 2 * frf_half_torque_per_amp, "RelTol", 1e-12);
      mode = virtualMotor.torsional_mode(plant);
      testCase.verifyEqual(mode.natural_frequency_hz, 200, "RelTol", 1e-3);
      testCase.verifyLessThan(abs(mode.damped_frequency_hz - 200), 1);
    end

    function runAndCollectExistsAndRejectsNonExperimentConfig(testCase)
      helper_path = which("experiment.exp0n.run_and_collect");
      testCase.verifyNotEmpty(helper_path);

      try
        experiment.exp0n.run_and_collect(struct());
        testCase.verifyTrue(false, "run_and_collect accepted a non-ExperimentConfig input.");
      catch err
        testCase.verifyNotEmpty(err.identifier);
      end
    end

    function plotHelpersCreateFigures(testCase)
      start_figs = findall(0, "Type", "figure");
      cleaner = onCleanup(@() close(setdiff(findall(0, "Type", "figure"), start_figs)));

      freq_hz = [1; 10; 100];
      frf = [1; 0.5; 0.1] .* exp(1i * [0; -0.2; -0.5]);
      experiment.plot.si_frf(freq_hz, frf, frf, [1; 0.9; 0.8], 1);

      signals = struct( ...
        "time_s", [0; 1], ...
        "ref_value", [0; 1], ...
        "position_act", [0; 0.8], ...
        "error", [0; 0.2], ...
        "control_input", [0; 0.1], ...
        "current_cmd", [0; 0.1]);
      metrics = struct("tracking_error_l2", 0.2);
      experiment.plot.feedback_result(signals, metrics);

      new_figs = setdiff(findall(0, "Type", "figure"), start_figs);
      testCase.verifyGreaterThanOrEqual(numel(new_figs), 2);
    end

    function feedbackSignalsValidateLengthAndFiniteValues(testCase)
      raw = struct( ...
        "t_s", [0; 0.1], ...
        "ref_value", [0; 1], ...
        "ff_value", [0; 0], ...
        "dist_value", [0; 0], ...
        "load_position", [0; 0.8], ...
        "error", [0; 0.2], ...
        "control_input", [0; 0.1], ...
        "current_cmd", [0; 0.1]);
      logger = struct("raw", raw, "record_count", 2);

      [signals, metrics] = experiment.exp02.signals_from_logger_bin( ...
        logger, "expected_sample_count", 2);

      testCase.verifyEqual(signals.position_act, [0; 0.8]);
      testCase.verifyEqual(signals.applied_feedforward, [0; 0]);
      testCase.verifyEqual(signals.feedback_input, [0; 0.1]);
      testCase.verifyEqual(metrics.tracking_error_l2, 0.2, "AbsTol", 1e-12);
      testCase.verifyError(@() experiment.exp02.signals_from_logger_bin( ...
        logger, "expected_sample_count", 3), ...
        "experiment:exp02:loggerLengthMismatch");
    end

    function runContractReportsFailedAcceptanceName(testCase)
      acceptance = struct( ...
        "input_waveform_exact_match", true, ...
        "ff_waveform_exact_match", true, ...
        "dist_waveform_exact_match", true, ...
        "torque_sum_exact_match", false, ...
        "seq_no_gap", true, ...
        "total_sample_count_exact_match", true);
      run_out = struct("metrics", struct("acceptance", acceptance));

      testCase.verifyError(@() experiment.exp0n.assert_run_contract(run_out), ...
        "experiment:exp0n:runtimeContractMismatch");
    end
  end
end
