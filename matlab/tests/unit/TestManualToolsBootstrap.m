classdef TestManualToolsBootstrap < matlab.unittest.TestCase
  methods (Test)
    function toolsAddExactMatlabPaths(testCase)
      tools_dir = fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "tools");
      files = dir(fullfile(tools_dir, "*.m"));

      testCase.verifyNotEmpty(files);
      for k = 1:numel(files)
        source = string(fileread(fullfile(files(k).folder, files(k).name)));

        testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
          'matlab_root = fileparts(fileparts(tool_file));'), files(k).name);
        testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
          'addpath(matlab_root, fullfile(matlab_root, "experiment"));'), files(k).name);
        testCase.verifyFalse(contains(source, "addpath(genpath("), files(k).name);
        testCase.verifyFalse(contains(source, "restoredefaultpath;"), files(k).name);
      end
    end
  end
end
