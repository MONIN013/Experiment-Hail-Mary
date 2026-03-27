classdef TestPreloadEval < matlab.unittest.TestCase
  methods (Test)
    function exactTablesAndTorqueSumPass(testCase)
      [raw, cmd, cfg] = make_case();
      metrics = experiment.preload_eval(raw, cmd, cfg);
      testCase.verifyTrue(metrics.acceptance.input_waveform_exact_match);
      testCase.verifyFalse(isfield(metrics, "comparison"));
      testCase.verifyFalse(isfield(metrics.sampling, "pre_roll_count"));
      testCase.verifyFalse(isfield(metrics.sampling, "post_roll_count"));
      testCase.verifyTrue(metrics.acceptance.ff_waveform_exact_match);
      testCase.verifyTrue(metrics.acceptance.dist_waveform_exact_match);
      testCase.verifyTrue(metrics.acceptance.torque_sum_exact_match);
      testCase.verifyTrue(metrics.acceptance.seq_no_gap);
      testCase.verifyEqual(string(metrics.input_waveform.mismatch_class), "exact");
    end

    function seqGapFailsAcceptance(testCase)
      [raw, cmd, cfg] = make_case();
      raw.seq = uint32([1; 3; 4]);
      metrics = experiment.preload_eval(raw, cmd, cfg);
      testCase.verifyFalse(isfield(metrics, "comparison"));
      testCase.verifyFalse(metrics.acceptance.seq_no_gap);
      testCase.verifyGreaterThan(metrics.seq.missing_count, 0);
    end

    function countMismatchIsDiagnosed(testCase)
      [raw, cmd, cfg] = make_case();
      raw.ref_value = raw.ref_value(1:2);
      metrics = experiment.preload_eval(raw, cmd, cfg);
      testCase.verifyFalse(isfield(metrics, "comparison"));
      testCase.verifyFalse(metrics.input_waveform.exact_sample_count_match);
      testCase.verifyEqual(string(metrics.input_waveform.mismatch_class), "count_mismatch");
      testCase.verifyFalse(metrics.sampling.all_sample_counts_match);
    end
  end
end

function [raw, cmd, cfg] = make_case()
ref = [0.1; 0.2; 0.3];
ff = [0.0; 0.0; 0.0];
dist = [0.01; 0.02; 0.03];
u = [1.0; 2.0; 3.0];
tau = u + dist;

  cfg = struct("task_rate_hz", 1000, "waveform_diag_abs_tol", 1e-12, "waveform_diag_preview_n", 8, ...
    "m", 1, "d", 0.1, "rated_current", 0.1, "max_permille", 0.0, "tau_limit", 5, "vel_limit", 100);

  raw = struct();
  raw.seq = uint32((1:3)');
  raw.ref_value = ref;
  raw.ff_value = ff;
  raw.dist_value = dist;
  raw.control_input = u;
  raw.target_current = tau;
  raw.position_act = [0.0; 0.1; 0.2];

  cmd = struct();
  cmd.ref_profile = ref;
  cmd.ff_profile = ff;
  cmd.dist_profile = dist;
cmd.use_profile = true;
end
