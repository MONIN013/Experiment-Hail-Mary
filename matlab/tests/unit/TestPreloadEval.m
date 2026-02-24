classdef TestPreloadEval < matlab.unittest.TestCase
  methods (Test)
    function exactMatchIsClassifiedAsExact(testCase)
      ref = [0.1; 0.2; 0.3; 0.4];
      [raw, cmd, cfg] = make_case(ref, ref);

      metrics = experiment.preload_eval(raw, cmd, cfg);

      testCase.verifyTrue(metrics.acceptance.input_waveform_exact_match);
      testCase.verifyEqual(string(metrics.input_waveform.mismatch_class), "exact");
      testCase.verifyEqual(double(metrics.input_waveform.best_shift_samples), 0);
    end

    function oneSampleShiftIsDiagnosed(testCase)
      ref = [0.1; 0.2; 0.3; 0.4];
      log_i = [0.0; ref(1:end-1)];
      [raw, cmd, cfg] = make_case(ref, log_i);

      metrics = experiment.preload_eval(raw, cmd, cfg);

      testCase.verifyFalse(metrics.acceptance.input_waveform_exact_match);
      testCase.verifyTrue(metrics.acceptance.input_waveform_shift_aligned_match);
      testCase.verifyEqual(string(metrics.input_waveform.mismatch_class), "one_sample_shift");
      testCase.verifyEqual(abs(double(metrics.input_waveform.best_shift_samples)), 1);
    end

    function smallNumericDeltaIsDiagnosed(testCase)
      ref = [0.1; 0.2; 0.3; 0.4];
      log_i = ref + 1e-13;
      [raw, cmd, cfg] = make_case(ref, log_i);

      metrics = experiment.preload_eval(raw, cmd, cfg);

      testCase.verifyFalse(metrics.acceptance.input_waveform_exact_match);
      testCase.verifyTrue(metrics.acceptance.input_waveform_abs_tol_match);
      testCase.verifyEqual(string(metrics.input_waveform.mismatch_class), "small_numeric_delta");
      testCase.verifyEqual(double(metrics.input_waveform.best_shift_samples), 0);
    end

    function countMismatchIsDiagnosed(testCase)
      ref = [0.1; 0.2; 0.3; 0.4];
      log_i = [0.1; 0.2; 0.3];
      [raw, cmd, cfg] = make_case(ref, log_i);

      metrics = experiment.preload_eval(raw, cmd, cfg);

      testCase.verifyFalse(metrics.input_waveform.exact_sample_count_match);
      testCase.verifyEqual(string(metrics.input_waveform.mismatch_class), "count_mismatch");
    end

    function previewFieldsArePopulated(testCase)
      ref = (1:10)' / 10;
      log_i = [0.0; ref(1:end-1)];
      [raw, cmd, cfg] = make_case(ref, log_i);
      cfg.waveform_diag_preview_n = 3;

      metrics = experiment.preload_eval(raw, cmd, cfg);

      testCase.verifyEqual(numel(metrics.input_waveform.head_preview.cmd), 3);
      testCase.verifyEqual(numel(metrics.input_waveform.tail_preview.cmd), 3);
      testCase.verifyEqual(numel(metrics.input_waveform.head_preview.err_zero_shift), 3);
      testCase.verifyEqual(numel(metrics.input_waveform.head_preview.err_best_shift), 3);
    end
  end
end

function [raw, cmd, cfg] = make_case(ref, log_i)
cfg = struct( ...
  "task_rate_hz", 1000, ...
  "m", 1.0, ...
  "d", 0.1, ...
  "kt", 0.2, ...
  "tau_limit", 5.0, ...
  "vel_limit", 100.0, ...
  "waveform_diag_max_shift_samples", 1, ...
  "waveform_diag_abs_tol", 1e-12, ...
  "waveform_diag_preview_n", 8);

  raw = struct();
  raw.current_last = 0.0;
  raw.position_last = 0.0;
  raw.log_overflow = false;
  raw.log_seq = uint32((1:numel(log_i))');
  raw.log_i = double(log_i(:));
  raw.log_x = experiment.simulate_position(raw.log_i, cfg);
  raw.log_t = zeros(numel(log_i), 1);
  raw.log_cmd_idx = zeros(0, 1);
  raw.log_cmd_value = zeros(0, 1);

  cmd = struct();
  cmd.current_in = 0.0;
  cmd.current_profile = double(ref(:));
end
