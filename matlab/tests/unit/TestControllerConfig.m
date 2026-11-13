classdef TestControllerConfig < matlab.unittest.TestCase
  methods (Test)
    function emptyBankIsIdentityFeedback(testCase)
      cfg = experiment.ControllerConfig();
      payload = cfg.to_ads_payload();

      testCase.verifySize(cfg.sos, [0, 6]);
      testCase.verifyEqual(payload.section_count, uint32(0));
      rows = reshape(payload.coefficients, 5, []).';
      testCase.verifyEqual(rows, repmat([1, 0, 0, 0, 0], 10, 1));
    end

    function pOnlyCreatesOneSosSection(testCase)
      cfg = experiment.ControllerConfig.p_only(3.5);
      payload = cfg.to_ads_payload();
      testCase.verifyEqual(cfg.sos, [3.5, 0, 0, 1, 0, 0]);
      testCase.verifyEqual(payload.section_count, uint32(1));
    end

    function normalizesA0AndSerializesCanonicalSos(testCase)
      cfg = experiment.ControllerConfig.from_struct(struct( ...
        "sos", [2, 4, 6, 2, 8, 10], "sample_time_s", 1/8000));
      testCase.verifyEqual(cfg.sos, [1, 2, 3, 1, 4, 5]);
      testCase.verifyEqual(cfg.sample_time_s, 1/8000, "AbsTol", 0);

      restored = experiment.ControllerConfig.from_struct(cfg.to_struct());
      testCase.verifyEqual(restored.sos, cfg.sos);
      testCase.verifyEqual(restored.sample_time_s, cfg.sample_time_s, "AbsTol", 0);
    end

    function adsPayloadIsSectionMajorAndPadsIdentity(testCase)
      cfg = experiment.ControllerConfig.from_struct(struct( ...
        "sos", [2, 3, 4, 1, 5, 6; 7, 8, 9, 1, 10, 11]));
      payload = cfg.to_ads_payload();
      rows = reshape(payload.coefficients, 5, []).';

      testCase.verifyEqual(payload.section_count, uint32(2));
      testCase.verifyEqual(rows(1:2, :), [2, 3, 4, 5, 6; 7, 8, 9, 10, 11]);
      testCase.verifyEqual(rows(3:end, :), repmat([1, 0, 0, 0, 0], 8, 1));
    end

    function zeroControllerIsExplicitOneSection(testCase)
      cfg = experiment.ControllerConfig.p_only(0);
      testCase.verifyEqual(size(cfg.sos, 1), 1);
      testCase.verifyEqual(cfg.sos(1, 1:3), [0, 0, 0]);
    end

    function higsPayloadRetainsInsertionAndRate(testCase)
      cfg = experiment.ControllerConfig.from_struct(struct( ...
        "sos", [2, 0, 0, 1, 0, 0], "sample_time_s", 1/8000, ...
        "higs_enabled", true, "higs_gain", 1.5, ...
        "higs_omega_ts", 0.02, "higs_pre_section_count", 1));
      cfg.validate_for_task_rate(8000);
      payload = cfg.to_ads_payload();
      testCase.verifyTrue(payload.higs_enabled);
      testCase.verifyEqual(payload.higs_gain, 1.5);
      testCase.verifyEqual(payload.higs_omega_ts, 0.02);
      testCase.verifyEqual(payload.higs_pre_section_count, uint32(1));
      copy = experiment.ControllerConfig.from_struct(cfg.to_struct());
      testCase.verifyEqual(copy.to_struct(), cfg.to_struct());
    end

    function rejectsInvalidHigsAndMissingTaskPeriod(testCase)
      cfg = experiment.ControllerConfig();
      cfg.higs_enabled = true;
      testCase.verifyError(@() cfg.validate(), "experiment:controller:invalid");
      cfg.higs_omega_ts = 1.1;
      testCase.verifyError(@() cfg.validate(), "experiment:controller:invalid");
      cfg.higs_omega_ts = 0.1;
      cfg.higs_pre_section_count = 1;
      testCase.verifyError(@() cfg.validate(), "experiment:controller:invalid");
      cfg.higs_pre_section_count = 0;
      testCase.verifyError(@() cfg.validate_for_task_rate(8000), ...
        "experiment:controller:missingSampleTime");
      cfg.sample_time_s = 1/8000;
      cfg.validate_for_task_rate(8000);
    end

    function rejectsUnknownFields(testCase)
      testCase.verifyError(@() experiment.ControllerConfig.from_struct( ...
        struct("sos", zeros(0, 6), "typo", 1)), ...
        "experiment:controller:invalid");
    end

    function rejectsInvalidSos(testCase)
      testCase.verifyError(@() experiment.ControllerConfig.p_only(Inf), ...
        "experiment:controller:invalid");
      testCase.verifyError(@() experiment.ControllerConfig.from_struct( ...
        struct("sos", [1, 2, 3, 0, 4, 5])), ...
        "experiment:controller:invalid");
      testCase.verifyError(@() experiment.ControllerConfig.from_struct( ...
        struct("sos", [1, 2, NaN, 1, 4, 5])), ...
        "experiment:controller:invalid");
      testCase.verifyError(@() experiment.ControllerConfig.from_struct( ...
        struct("sos", zeros(11, 6))), ...
        "experiment:controller:tooManySections");
      testCase.verifyError(@() experiment.ControllerConfig.from_struct( ...
        struct("sos", zeros(0, 6), "sample_time_s", -1)), ...
        "experiment:controller:invalid");
    end

    function validatesDynamicControllerSampleTime(testCase)
      dynamic = experiment.ControllerConfig.from_struct(struct( ...
        "sos", [1, 0.5, 0, 1, -0.25, 0], ...
        "sample_time_s", 1/8000));
      dynamic.validate_for_task_rate(8000);
      testCase.verifyError(@() dynamic.validate_for_task_rate(1000), ...
        "experiment:controller:sampleTimeMismatch");

      missing = experiment.ControllerConfig.from_struct(struct( ...
        "sos", [1, 0.5, 0, 1, -0.25, 0]));
      testCase.verifyError(@() missing.validate_for_task_rate(8000), ...
        "experiment:controller:missingSampleTime");
      memoryless = experiment.ControllerConfig.p_only(2);
      memoryless.validate_for_task_rate(8000);
    end
  end
end
