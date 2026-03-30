classdef TestBuildPeriodicChirp < matlab.unittest.TestCase
  methods (Test)
    function signalLengthMatchesTendOverTs(testCase)
      out = experiment.build_periodic_chirp( ...
        "Ts", 0.01, "Tend", 1.2, "Tcycle", 0.2, "f0", 1, "f1", 10, "A", 0.5);

      testCase.verifyEqual(out.sample_count, 120);
      testCase.verifySize(out.signal, [120, 1]);
      testCase.verifyEqual(out.t(end), 1.19, "AbsTol", 1e-12);
      testCase.verifyEqual(out.cycle_samples, 20);
    end

    function rejectsFrequencyAboveNyquist(testCase)
      testCase.verifyError(@() experiment.build_periodic_chirp( ...
        "Ts", 0.01, "Tend", 1.0, "Tcycle", 0.5, "f0", 1, "f1", 60), ...
        "experiment:build_periodic_chirp:invalidConfig");
    end

    function rejectsNonPositiveStartFrequency(testCase)
      testCase.verifyError(@() experiment.build_periodic_chirp( ...
        "Ts", 0.01, "Tend", 1.0, "Tcycle", 0.5, "f0", 0, "f1", 10), ...
        "experiment:build_periodic_chirp:invalidConfig");
    end
  end
end
