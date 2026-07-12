classdef TestControllerConfig < matlab.unittest.TestCase
  methods (Test)
    function pOnlyEnablesPid(testCase)
      cfg = experiment.ControllerConfig.p_only(3.5);
      testCase.verifyTrue(cfg.pid.enable);
      testCase.verifyEqual(cfg.pid.b0, 3.5);
      testCase.verifyFalse(cfg.lead.enable);
    end

    function flatRoundTrip(testCase)
      flat = struct( ...
        "pid_b0", 1, "pid_b1", 2, "pid_b2", 3, "pid_a1", 4, "pid_a2", 5, ...
        "lead_b0", 6, "lead_b1", 7, "lead_b2", 8, "lead_a1", 9, "lead_a2", 10, ...
        "notch_b0", 11, "notch_b1", 12, "notch_b2", 13, "notch_a1", 14, "notch_a2", 15, ...
        "reso_b0", 16, "reso_b1", 17, "reso_b2", 18, "reso_a1", 19, "reso_a2", 20, ...
        "enable_pid", true, "enable_lead", true, "enable_notch", false, "enable_reso", true);
      cfg = experiment.ControllerConfig.from_flat_struct(flat);
      out = cfg.to_flat_struct();
      testCase.verifyEqual(out.pid_b1, 2);
      testCase.verifyEqual(out.reso_a2, 20);
      testCase.verifyTrue(out.enable_lead);
    end

    function rejectsUnknownFlatField(testCase)
      testCase.verifyError(@() experiment.ControllerConfig.from_flat_struct( ...
        struct("pid_b0", 1, "pid_typo", 2)), ...
        "experiment:controller:invalid");
    end

    function rejectsInvalidGainAndStageValues(testCase)
      testCase.verifyError(@() experiment.ControllerConfig.p_only(Inf), ...
        "experiment:controller:invalid");
      testCase.verifyError(@() experiment.ControllerConfig.from_flat_struct( ...
        struct("pid_b0", NaN)), "experiment:biquad:invalid");
      testCase.verifyError(@() experiment.ControllerConfig.from_flat_struct( ...
        struct("enable_pid", 2)), "experiment:biquad:invalid");
    end
  end
end
