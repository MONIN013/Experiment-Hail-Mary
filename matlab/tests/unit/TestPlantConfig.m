classdef TestPlantConfig < matlab.unittest.TestCase
  methods (Test)
    function structRoundTrip(testCase)
      cfg = experiment.PlantConfig.from_struct(struct( ...
        "m", 1, "d", 2, "rated_current", 3, "max_permille", 4, "tau_limit", 5, "vel_limit", 6));
      out = cfg.to_struct();
      testCase.verifyEqual(out.m, 1);
      testCase.verifyEqual(out.vel_limit, 6);
    end
  end
end
