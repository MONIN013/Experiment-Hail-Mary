classdef TestExp04TrialDashboard < matlab.unittest.TestCase
  methods (Test)
    function updatesOneThreeAxesFigureWithoutSavingImages(testCase)
      temporary_folder = testCase.applyFixture( ...
        matlab.unittest.fixtures.TemporaryFolderFixture);
      original_folder = cd(temporary_folder.Folder);
      folder_cleanup = onCleanup(@() cd(original_folder));
      original_figures = findall(0, "Type", "figure");
      figure_cleanup = onCleanup(@() close( ...
        setdiff(findall(0, "Type", "figure"), original_figures)));

      t = linspace(0, 0.1, 11)';
      reference = sin(2*pi*5*t);
      actual = 0.8 * reference;
      error_signal = reference - actual;
      feedforward = 0.1 * ones(size(t));
      feedback = 0.2 * ones(size(t));
      total_input = 0.25 * ones(size(t));

      dashboard = experiment.exp04.update_trial_dashboard( ...
        [], t, reference, actual, error_signal, feedforward, feedback, ...
        1, 10, "total_input", total_input, "visible", "off");
      first_figure = dashboard.figure;
      first_axes = dashboard.axes;

      updated_actual = 0.95 * reference;
      updated_error = reference - updated_actual;
      dashboard = experiment.exp04.update_trial_dashboard( ...
        dashboard, t, reference, updated_actual, updated_error, ...
        0.15 * ones(size(t)), 0.05 * ones(size(t)), 2, 10, ...
        "total_input", 0.3 * ones(size(t)), "visible", false);

      testCase.verifyEqual(dashboard.figure, first_figure);
      testCase.verifyEqual(dashboard.axes, first_axes);
      testCase.verifyNumElements(findall(dashboard.figure, "Type", "axes"), 3);
      testCase.verifyEqual(dashboard.lines.actual.YData(:), updated_actual);
      testCase.verifyEqual(dashboard.lines.error.YData(:), updated_error);
      testCase.verifyEqual(dashboard.lines.feedforward.YData(:), ...
        0.15 * ones(size(t)));
      testCase.verifyEqual(dashboard.lines.feedback.YData(:), ...
        0.05 * ones(size(t)));
      testCase.verifySubstring(string(dashboard.title.String), "Trial 2/10");
      testCase.verifySubstring(string(dashboard.title.String), "||e||_2");
      testCase.verifySubstring(string(dashboard.title.String), "max|FF|");
      testCase.verifySubstring(string(dashboard.title.String), "max|u|");
      testCase.verifyEqual(dashboard.metrics.errorNorm, norm(updated_error), ...
        "AbsTol", 1e-12);
      testCase.verifyEqual(dashboard.metrics.maxAbsTotalInputA, 0.3, ...
        "AbsTol", 1e-12);

      files = dir(fullfile(temporary_folder.Folder, "**", "*"));
      testCase.verifyEmpty(files(~[files.isdir]));
    end

    function rejectsMismatchedTrialSignalLengths(testCase)
      testCase.verifyError(@() experiment.exp04.update_trial_dashboard( ...
        [], (0:2)', zeros(3, 1), zeros(3, 1), zeros(2, 1), ...
        zeros(3, 1), zeros(3, 1), 1, 1, "visible", "off"), ...
        "experiment:exp04:dashboardLengthMismatch");
    end

    function checkpointsOnlyCompletedNumericHistoryToMat(testCase)
      temporary_folder = testCase.applyFixture( ...
        matlab.unittest.fixtures.TemporaryFolderFixture);
      checkpoint_path = fullfile(temporary_folder.Folder, "partial.mat");
      history = struct( ...
        "t", (0:3)', ...
        "r", reshape(1:12, 4, 3), ...
        "y", reshape(11:22, 4, 3), ...
        "e", reshape(21:32, 4, 3), ...
        "f", reshape(31:42, 4, 3), ...
        "ffApplied", reshape(36:47, 4, 3), ...
        "u", reshape(41:52, 4, 3), ...
        "eNorm", [3 2 1], ...
        "maxAbsInput", [0.1 0.2 0.3], ...
        "errorIncreased", [false false false], ...
        "convergencePeak", [0.7 0.7 0.7], ...
        "trialLoggerPaths", ["trial01.bin", "trial02.bin", "trial03.bin"], ...
        "trialLoggerRecordCount", [4 4 4], ...
        "maxSensitivity", 1.2);

      trimmed = experiment.exp04.checkpoint_partial_history( ...
        checkpoint_path, history, 2, "input_limit");
      saved = load(checkpoint_path, "history");

      testCase.verifyEqual(fieldnames(saved), {'history'});
      testCase.verifyEqual(saved.history, trimmed);
      testCase.verifySize(saved.history.r, [4 2]);
      testCase.verifySize(saved.history.y, [4 2]);
      testCase.verifyEqual(saved.history.eNorm, [3 2]);
      testCase.verifyEqual(saved.history.trialLoggerPaths, ...
        ["trial01.bin", "trial02.bin"]);
      testCase.verifyEqual(saved.history.trialLoggerRecordCount, [4 4]);
      testCase.verifyEqual(saved.history.completedTrials, 2);
      testCase.verifyEqual(saved.history.stopReason, "input_limit");
      testCase.verifyEqual(height(saved.history.trialSummary), 2);
      testCase.verifyEqual(string(saved.history.trialSummary.Properties.VariableNames), ...
        ["trial", "errorNorm", "maxAbsError", "maxAbsInputA", ...
         "maxAbsFeedforwardA", "maxAbsTotalInputA", "errorIncreased", ...
         "convergencePeak", "convergenceSatisfied"]);

      image_files = [ ...
        dir(fullfile(temporary_folder.Folder, "*.png")); ...
        dir(fullfile(temporary_folder.Folder, "*.jpg")); ...
        dir(fullfile(temporary_folder.Folder, "*.jpeg"))];
      testCase.verifyEmpty(image_files);
    end

    function archivesAndReparsesEachCompletedTrialLogger(testCase)
      temporary_folder = testCase.applyFixture( ...
        matlab.unittest.fixtures.TemporaryFolderFixture);
      source = fullfile(temporary_folder.Folder, "active.bin");
      destination = fullfile(temporary_folder.Folder, "trial01_logger.bin");
      write_logger_record(source);
      parsed = experiment.read_logger_bin(source);

      capture = experiment.exp04.archive_trial_logger(parsed, destination);
      archived = experiment.read_logger_bin(destination);

      testCase.verifyEqual(capture.path, string(destination));
      testCase.verifyEqual(capture.record_count, 1);
      testCase.verifyEqual(archived.raw, parsed.raw);
      testCase.verifyEqual(archived.table, parsed.table);
    end
  end
end

function write_logger_record(file_path)
fid = fopen(file_path, "wb", "ieee-le");
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, uint32(1), "uint32");
fwrite(fid, uint32(2), "uint32");
fwrite(fid, uint64(1000), "uint64");
fwrite(fid, 0.1:0.1:1.1, "double");
clear cleanup
end
