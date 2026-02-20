classdef TestTransportContract < matlab.unittest.TestCase
  methods (Test)
    function mockTransportRoundTripScalar(testCase)
      t = MockAdsTransport();
      t.connect("x", 1);
      t.write_scalar("X.flag", true, "System.Boolean");
      v = t.read_scalar("X.flag", "System.Boolean");
      testCase.verifyTrue(logical(v));
    end

    function mockTransportRoundTripArray(testCase)
      t = MockAdsTransport();
      t.connect("x", 1);
      x = [1; 2; 3];
      t.write_array("X.arr", x, "System.Double");
      y = t.read_array("X.arr", "System.Double", 3);
      testCase.verifyEqual(double(y(:)), x);
    end
  end
end
