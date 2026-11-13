classdef TestHigsCurrentAcceptance < matlab.unittest.TestCase
  methods (Test)
    function acceptsFinitePeaksBelowLimit(testCase)
      testCase.verifyTrue(experiment.higs_current_accepted(valid_metrics(), 0.08));
    end

    function rejectsActualOvercurrentDespiteSmallCommands(testCase)
      m = valid_metrics();
      m.measured_current_peak_a = 0.081;
      testCase.verifyFalse(experiment.higs_current_accepted(m, 0.08));
    end

    function rejectsEveryPeakAtOrAboveLimit(testCase)
      names = ["current_peak_a", "command_peak_a", "measured_current_peak_a"];
      for name = names
        for peak = [0.08, 0.081]
          m = valid_metrics(); m.(name) = peak;
          testCase.verifyFalse(experiment.higs_current_accepted(m, 0.08));
        end
      end
    end

    function rejectsInvalidAndMissingPeaks(testCase)
      names = ["current_peak_a", "command_peak_a", "measured_current_peak_a"];
      bad = {NaN, Inf, -0.001, [], [0.01, 0.02], 0.01+1i, "0.01"};
      for name = names
        for k = 1:numel(bad)
          m = valid_metrics(); m.(name) = bad{k};
          testCase.verifyFalse(experiment.higs_current_accepted(m, 0.08));
        end
        testCase.verifyFalse(experiment.higs_current_accepted( ...
          rmfield(valid_metrics(), char(name)), 0.08));
      end
    end

    function rejectsInvalidLimitsAndRecords(testCase)
      bad = {NaN, Inf, 0, -1, [], [0.08, 0.09], 0.08+1i, "0.08"};
      for k = 1:numel(bad)
        testCase.verifyFalse(experiment.higs_current_accepted(valid_metrics(), bad{k}));
      end
      testCase.verifyFalse(experiment.higs_current_accepted([], 0.08));
      testCase.verifyFalse(experiment.higs_current_accepted(repmat(valid_metrics(), 1, 2), 0.08));
    end

    function runnerUsesTheAcceptanceGate(testCase)
      text = fileread(which("exp05_Higs"));
      testCase.verifyTrue(contains(text, ...
        "result.accepted = experiment.higs_current_accepted(metrics, design.max_current_a);"));
    end
  end
end

function m = valid_metrics()
m = struct("current_peak_a", 0.02, "command_peak_a", 0.021, ...
  "measured_current_peak_a", 0.022);
end
