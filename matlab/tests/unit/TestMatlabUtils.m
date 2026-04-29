classdef TestMatlabUtils < matlab.unittest.TestCase
  methods (Test)
    function wrapPhaseMapsToMinus180To180(testCase)
      phase_deg = [-540; -181; -180; -179; 0; 179; 180; 181; 540];
      actual = experiment.wrap_phase_at_180(phase_deg);
      expected = [-180; 179; -180; -179; 0; 179; -180; -179; -180];

      testCase.verifyEqual(actual, expected);
    end
  end
end
