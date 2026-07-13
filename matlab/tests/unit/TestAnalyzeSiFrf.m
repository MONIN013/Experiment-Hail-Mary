classdef TestAnalyzeSiFrf < matlab.unittest.TestCase
  methods (Test)
    function trimsTransientCyclesAndReturnsAlignedVectors(testCase)
      Ts = 0.01;
      Tcycle = 0.5;
      cycle_samples = round(Tcycle / Ts);
      total_cycles = 5;
      t = Ts * (0:cycle_samples * total_cycles - 1)';
      input_signal = sin(2 * pi * 2 * t);
      output_signal = 0.7 * sin(2 * pi * 2 * t - 0.2);
      logger_raw = struct( ...
        "t_s", t, ...
        "ff_value", input_signal, ...
        "load_velocity", output_signal, ...
        "control_input", input_signal, ...
        "current_cmd", input_signal);

      out = experiment.analyze_si_frf(logger_raw, ...
        "Tcycle", Tcycle, ...
        "transient_cycles", 2);

      testCase.verifyEqual(out.input_signal_name, "ff_value");
      testCase.verifyEqual(out.output_signal_name, "load_velocity");
      testCase.verifyEqual(out.window_samples, cycle_samples);
      testCase.verifyEqual(out.trim_info.start_index, 2 * cycle_samples + 1);
      testCase.verifyEqual(out.trim_info.usable_period_count, 3);
      testCase.verifyEqual(numel(out.signals.input), 3 * cycle_samples);
      testCase.verifyEqual(numel(out.freq_hz), numel(out.frf));
      testCase.verifyEqual(numel(out.freq_hz), numel(out.coherence));
      positive_frequency = out.freq_hz > 0;
      expected_integrator = Ts ./ ...
        (1 - exp(-1i * 2 * pi * out.freq_hz(positive_frequency) * Ts));
      testCase.verifyEqual(out.position_freq_hz, out.freq_hz(positive_frequency));
      testCase.verifyEqual(out.position_frf, ...
        out.frf(positive_frequency) .* expected_integrator, "AbsTol", 1e-12);
      testCase.verifyEqual(out.frd_velocity.Ts, Ts, "AbsTol", 1e-12);
      testCase.verifyClass(out.frd_position, "frd");
      testCase.verifyEqual(out.frd_position.Ts, Ts, "AbsTol", 1e-12);
      testCase.verifyEqual(numel(out.signals.control_input), 3 * cycle_samples);
      testCase.verifyEqual(numel(out.signals.current_cmd), 3 * cycle_samples);
    end

    function prefersRawSignalsFromLoggerBinStruct(testCase)
      Ts = 0.01;
      Tcycle = 0.2;
      t = Ts * (0:79)';
      u = sin(2 * pi * 5 * t);
      logger_bin = struct( ...
        "raw", struct( ...
          "t_s", t, ...
          "ff_value", u, ...
          "load_velocity", 2 * u), ...
        "record_count", numel(t));

      out = experiment.analyze_si_frf(logger_bin, "Tcycle", Tcycle);

      testCase.verifyEqual(out.Ts, Ts, "AbsTol", 1e-12);
      testCase.verifyEqual(out.trim_info.total_samples, 80);
    end

    function rejectsEmptySignals(testCase)
      logger_raw = struct("ff_value", zeros(0, 1), "load_velocity", zeros(0, 1));

      testCase.verifyError(@() experiment.analyze_si_frf(logger_raw, "Ts", 0.01, "Tcycle", 0.5), ...
        "experiment:analyze_si_frf:emptySignal");
    end
  end
end
