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

    function mockTransportReadArraySlice(testCase)
      t = MockAdsTransport();
      t.connect("x", 1);
      x = [10; 20; 30; 40];
      t.write_array("X.arr", x, "System.Double");
      y = t.read_array_slice("X.arr", "System.Double", 1, 2);
      testCase.verifyEqual(double(y(:)), [20; 30]);
    end

    function mockTransportReadArraySliceFromZero(testCase)
      t = MockAdsTransport();
      t.connect("x", 1);
      x = uint32([11; 22; 33; 44]);
      t.write_array("X.arrU32", x, "System.UInt32");
      y = t.read_array_slice("X.arrU32", "System.UInt32", 0, 4);
      testCase.verifyEqual(double(y(:)), double(x(:)));
    end

    function mockTransportReadArraySlicePastEndReturnsShort(testCase)
      t = MockAdsTransport();
      t.connect("x", 1);
      x = [10; 20; 30; 40];
      t.write_array("X.arr", x, "System.Double");
      y = t.read_array_slice("X.arr", "System.Double", 2, 10);
      testCase.verifyEqual(double(y(:)), [30; 40]);
    end

    function mockTransportRoundTripNewScalarTypes(testCase)
      t = MockAdsTransport();
      t.connect("x", 1);
      t.write_scalar("X.i16", int16(-2), "System.Int16");
      t.write_scalar("X.i32", int32(-3), "System.Int32");
      t.write_scalar("X.i64", int64(-4), "System.Int64");
      t.write_scalar("X.str", "abc", "System.String");
      testCase.verifyEqual(t.read_scalar("X.i16", "System.Int16"), int16(-2));
      testCase.verifyEqual(t.read_scalar("X.i32", "System.Int32"), int32(-3));
      testCase.verifyEqual(t.read_scalar("X.i64", "System.Int64"), int64(-4));
      testCase.verifyEqual(string(t.read_scalar("X.str", "System.String")), "abc");
    end

    function mockTransportReadWriteStruct(testCase)
      t = MockAdsTransport();
      t.connect("x", 1);
      symbol_map = struct( ...
        "gain", {{"GVL.gain", "System.Double"}}, ...
        "name", {{"GVL.name", "System.String"}});
      t.write_struct(symbol_map, struct("gain", 1.25, "name", "demo"));
      out = t.read_struct(symbol_map);
      testCase.verifyEqual(out.gain, 1.25);
      testCase.verifyEqual(string(out.name), "demo");
    end
  end
end
