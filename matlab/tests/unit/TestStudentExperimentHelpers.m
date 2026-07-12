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

    function controllerConfigFromDiscreteTfUsesBiquadStage(testCase)
      discrete_tf = tf([2 -1], [1 -0.5], 0.001);
      cfg = experiment.controller.from_discrete_tf(discrete_tf);
      flat = cfg.to_flat_struct();
      testCase.verifyTrue(flat.enable_pid);
      testCase.verifyEqual(flat.pid_b0, 2, "AbsTol", 1e-12);
      testCase.verifyEqual(flat.pid_b1, -1, "AbsTol", 1e-12);
      testCase.verifyEqual(flat.pid_a1, -0.5, "AbsTol", 1e-12);
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

    function nominalTwoInertiaFrfReturnsFiniteVector(testCase)
      plant = experiment.exp01.nominal_overlay_plant();
      frf = experiment.analysis.nominal_two_inertia_frf(plant, 2*pi*[1; 10], "Ts", 0.001, "sample_delay", 1);
      frf_half_torque_per_amp = experiment.analysis.nominal_two_inertia_frf( ...
        plant, 2*pi*[1; 10], "Ts", 0.001, "sample_delay", 1, "rated_current_A", 3.2);
      testCase.verifySize(frf, [2, 1]);
      testCase.verifyTrue(all(isfinite(real(frf))));
      testCase.verifyTrue(all(isfinite(imag(frf))));
      testCase.verifyEqual(frf, 2 * frf_half_torque_per_amp, "RelTol", 1e-12);
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
        "load_position", [0; 0.8], ...
        "error", [0; 0.2], ...
        "control_input", [0; 0.1], ...
        "current_cmd", [0; 0.1]);
      logger = struct("raw", raw, "record_count", 2);

      [signals, metrics] = experiment.exp02.signals_from_logger_bin( ...
        logger, "expected_sample_count", 2);

      testCase.verifyEqual(signals.position_act, [0; 0.8]);
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
