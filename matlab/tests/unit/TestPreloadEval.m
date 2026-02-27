classdef TestPreloadEval < matlab.unittest.TestCase
  methods (Test)
    function exactTablesAndTorqueSumPass(testCase)
      [raw, cmd, cfg] = make_case();
      metrics = experiment.preload_eval(raw, cmd, cfg);
      testCase.verifyTrue(metrics.acceptance.input_waveform_exact_match);
      testCase.verifyFalse(isfield(metrics, "comparison"));
      testCase.verifyTrue(metrics.acceptance.ff_waveform_exact_match);
      testCase.verifyTrue(metrics.acceptance.dist_waveform_exact_match);
      testCase.verifyTrue(metrics.acceptance.torque_sum_exact_match);
      testCase.verifyTrue(metrics.acceptance.seq_no_gap);
      testCase.verifyEqual(string(metrics.input_waveform.mismatch_class), "exact");
    end

    function seqGapFailsAcceptance(testCase)
      [raw, cmd, cfg] = make_case();
      raw.logSeq = uint32([1; 3; 4]);
      metrics = experiment.preload_eval(raw, cmd, cfg);
      testCase.verifyFalse(isfield(metrics, "comparison"));
      testCase.verifyFalse(metrics.acceptance.seq_no_gap);
      testCase.verifyGreaterThan(metrics.seq.missing_count, 0);
    end

    function countMismatchIsDiagnosed(testCase)
      [raw, cmd, cfg] = make_case();
      raw.logRefValue = raw.logRefValue(1:2);
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
  "m", 1, "d", 0.1, "kt", 0.1, "tau_limit", 5, "vel_limit", 100);

raw = struct();
raw.log_overflow = false;
raw.logSeq = uint32((1:3)');
raw.logRefValue = ref;
raw.logFfValue = ff;
raw.logDistValue = dist;
raw.logControlInput = u;
raw.logTargetCurrent = tau;
raw.logPositionAct = [0.0; 0.1; 0.2];
raw.logT = zeros(3, 1);

cmd = struct();
cmd.ref_profile = ref;
cmd.ff_profile = ff;
cmd.dist_profile = dist;
cmd.use_profile = true;
end
