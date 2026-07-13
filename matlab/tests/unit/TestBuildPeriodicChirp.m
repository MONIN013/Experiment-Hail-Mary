classdef TestBuildPeriodicChirp < matlab.unittest.TestCase
  methods (Test)
    function signalLengthMatchesTendOverTs(testCase)
      out = experiment.waveform.periodic_chirp( ...
        "Ts", 0.01, "Tend", 1.2, "Tcycle", 0.2, "f0", 1, "f1", 10, "A", 0.5);

      testCase.verifyEqual(out.sample_count, 120);
      testCase.verifySize(out.signal, [120, 1]);
      testCase.verifyEqual(out.t(end), 1.19, "AbsTol", 1e-12);
      testCase.verifyEqual(out.cycle_samples, 20);
    end

    function rejectsFrequencyAboveNyquist(testCase)
      testCase.verifyError(@() experiment.waveform.periodic_chirp( ...
        "Ts", 0.01, "Tend", 1.0, "Tcycle", 0.5, "f0", 1, "f1", 60), ...
        "experiment:build_periodic_chirp:invalidConfig");
    end

    function rejectsNonPositiveStartFrequency(testCase)
      testCase.verifyError(@() experiment.waveform.periodic_chirp( ...
        "Ts", 0.01, "Tend", 1.0, "Tcycle", 0.5, "f0", 0, "f1", 10), ...
        "experiment:build_periodic_chirp:invalidConfig");
    end

    function balancesQuantizedCountSumWithDeterministicMinimumError(testCase)
      quantum_A = 0.1;
      signal = [0.051; 0.06; 0.06; 0.07; -0.06; -0.06];

      [balanced, report] = ...
        experiment.waveform.balance_quantized_cycle(signal, quantum_A);
      balanced_again = ...
        experiment.waveform.balance_quantized_cycle(signal, quantum_A);
      counts = balanced / quantum_A;

      testCase.verifyEqual(sum(counts), 0);
      testCase.verifyEqual(counts, round(counts));
      testCase.verifyEqual(counts, [0; 0; 1; 1; -1; -1]);
      testCase.verifyEqual(balanced_again, balanced);
      testCase.verifyEqual( ...
        report.adjusted_sample_count, abs(report.original_count_sum));
      testCase.verifyEqual(report.original_count_sum, 2);
      testCase.verifyEqual(report.balanced_count_sum, 0);
      testCase.verifyEqual(report.quantum_A, quantum_A);
      testCase.verifyEqual( ...
        report.original_mean_A, mean(signal), "AbsTol", 1e-15);
      testCase.verifyEqual(report.balanced_mean_A, 0, "AbsTol", 1e-15);
    end

    function rejectsInvalidQuantizedCycleInputs(testCase)
      invalid_signals = {[], [1 NaN], [1+1i 2], ones(2)};
      for signal = invalid_signals
        testCase.verifyError(@() ...
          experiment.waveform.balance_quantized_cycle(signal{1}, 0.1), ...
          "experiment:waveform:invalidQuantizedCycle");
      end
      for quantum = {0, -1, Inf, 1+1i}
        testCase.verifyError(@() ...
          experiment.waveform.balance_quantized_cycle([0.1; -0.1], quantum{1}), ...
          "experiment:waveform:invalidQuantizedCycle");
      end
    end

  end
end
