classdef TestWriteHelpers < matlab.unittest.TestCase
  methods (Test)
    function writeRefTableWritesInputLength(testCase)
      tr = MockAdsTransport();
      experiment.write_ref_table(tr, [1; 2; 3], 5);
      v = tr.arrayMap("GVL_SEQ.refTable");
      testCase.verifyEqual(double(v(:)), [1; 2; 3]);
    end

    function writeFfAndDistRespectLength(testCase)
      tr = MockAdsTransport();
      experiment.write_ff_table(tr, [0.1; 0.2], 2);
      experiment.write_dist_table(tr, [0.0; 0.0], 2);
      testCase.verifyEqual(double(tr.arrayMap("GVL_SEQ.ffTable")), [0.1; 0.2]);
      testCase.verifyEqual(double(tr.arrayMap("GVL_SEQ.distTable")), [0.0; 0.0]);
    end
  end
end
