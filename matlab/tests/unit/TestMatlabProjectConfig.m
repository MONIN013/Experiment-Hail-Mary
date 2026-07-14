classdef TestMatlabProjectConfig < matlab.unittest.TestCase
  methods (Test)
    function projectMetadataMatchesRepositoryContract(testCase)
      test_dir = fileparts(mfilename("fullpath"));
      matlab_root = fileparts(fileparts(test_dir));
      tools_dir = fullfile(matlab_root, "tools");
      original_path = path;
      testCase.addTeardown(@() path(original_path));
      addpath(tools_dir);

      project_file = fullfile(matlab_root, "ExperimentHailMary.prj");
      report = update_matlab_project(project_file, VerifyOnly=true);

      testCase.verifyTrue(report.valid);
      testCase.verifyEqual(report.project_paths, ["."; "experiment"]);
      testCase.verifyEqual(report.startup_file_count, 0);
      testCase.verifyEqual(report.shutdown_file_count, 0);
      testCase.verifyGreaterThan(report.classification_counts.design, 0);
      testCase.verifyGreaterThan(report.classification_counts.test, 0);
      testCase.verifyGreaterThan(report.classification_counts.convenience, 0);
      testCase.verifyTrue(isfile(fullfile(matlab_root, ...
        "+testoracle", "build_manifest.m")));
    end
  end
end
