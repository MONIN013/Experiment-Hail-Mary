classdef TestBiquadStage < matlab.unittest.TestCase
  methods (Test)
    function passthroughDefaults(testCase)
      stage = experiment.BiquadStage.passthrough();
      testCase.verifyFalse(stage.enable);
      testCase.verifyEqual(stage.b0, 1);
    end

    function flattensWithPrefix(testCase)
      stage = experiment.BiquadStage.from_struct(struct( ...
        "b0", 2, "b1", 3, "b2", 4, "a1", 5, "a2", 6, "enable", true));
      flat = stage.to_flat("pid_");
      testCase.verifyEqual(flat.pid_b0, 2);
      testCase.verifyEqual(flat.pid_a2, 6);
    end

    function rejectsUnknownField(testCase)
      testCase.verifyError(@() experiment.BiquadStage.from_struct( ...
        struct("b0", 1, "gain", 2)), "experiment:biquad:invalid");
    end

    function rejectsNonFiniteAndNonScalarCoefficients(testCase)
      testCase.verifyError(@() experiment.BiquadStage.from_struct( ...
        struct("b0", NaN)), "experiment:biquad:invalid");
      testCase.verifyError(@() experiment.BiquadStage.from_struct( ...
        struct("a1", [1, 2])), "experiment:biquad:invalid");
      testCase.verifyError(@() experiment.BiquadStage.from_struct( ...
        struct("b2", 1i)), "experiment:biquad:invalid");
    end

    function rejectsNonBooleanEnable(testCase)
      testCase.verifyError(@() experiment.BiquadStage.from_struct( ...
        struct("enable", -1)), "experiment:biquad:invalid");
    end
  end
end
