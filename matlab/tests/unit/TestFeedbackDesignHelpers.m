classdef TestFeedbackDesignHelpers < matlab.unittest.TestCase
  methods (Test)
    function piAndPdPlaceRepeatedPoles(testCase)
      s = tf("s");
      d = 0.42;
      k = 0.3;
      Kt = 3.7;
      w = 20;
      plant = Kt / (s^2 + d*s + k);

      verify_characteristic(testCase, plant, ...
        experiment.exp02.designpi(d, k, Kt, w), [1 d 3*w^2 w^3]);
      verify_characteristic(testCase, plant, ...
        experiment.exp02.designpd(d, k, Kt, w), [1 3*w 3*w^2 w^3]);
    end

    function stabilityCheckReturnsMeasuredPeakWithoutPlot(testCase)
      Ts = 1e-3;
      freq_hz = [1; 10; 100];
      Pd = frd(0.1 * ones(size(freq_hz)), freq_hz, "FrequencyUnit", "Hz");
      Pdn = tf(0.1, 1, Ts);
      Kd = tf(0.5, 1, Ts);

      out = experiment.exp02.stability_check(Pd, Pdn, Kd, 2, "plot", false);

      testCase.verifyTrue(out.ok);
      testCase.verifyLessThan(out.max_sensitivity, 2);
    end

    function stabilityCheckWarnsAndReturnsDiagnosticsOnSensitivityLimit(testCase)
      Ts = 1e-3;
      freq_hz = [1; 10; 100];
      Pd = frd(-0.75 * ones(size(freq_hz)), freq_hz, "FrequencyUnit", "Hz");
      Pdn = tf(0.1, 1, Ts);
      Kd = tf(1, 1, Ts);

      testCase.verifyWarning(@() experiment.exp02.stability_check( ...
        Pd, Pdn, Kd, 2, "plot", false), ...
        "experiment:exp02:sensitivityLimitExceeded");
      warning_state = warning("off", "experiment:exp02:sensitivityLimitExceeded");
      cleanup = onCleanup(@() warning(warning_state));
      out = experiment.exp02.stability_check(Pd, Pdn, Kd, 2, "plot", false);
      testCase.verifyFalse(out.ok);
      testCase.verifyTrue(out.limit_exceeded);
      testCase.verifyGreaterThan(out.max_sensitivity, 2);
      clear cleanup
    end
  end
end

function verify_characteristic(testCase, plant, controller, expected)
[plant_num, plant_den] = tfdata(tf(plant), "v");
[controller_num, controller_den] = tfdata(tf(controller), "v");
actual = add_polynomials( ...
  conv(plant_den, controller_den), conv(plant_num, controller_num));
actual = actual / actual(1);
testCase.verifyEqual(actual, expected, "RelTol", 1e-10, "AbsTol", 1e-10);
end

function out = add_polynomials(a, b)
width = max(numel(a), numel(b));
out = [zeros(1, width - numel(a)) a(:).'] + [zeros(1, width - numel(b)) b(:).'];
first = find(abs(out) > 1e-12, 1, "first");
out = out(first:end);
end
