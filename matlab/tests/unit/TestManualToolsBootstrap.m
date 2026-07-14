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

    function loggerToolAcceptsRunnerConfirmedPathWithoutForcingPlots(testCase)
      tools_dir = fullfile(fileparts(fileparts(fileparts( ...
        mfilename("fullpath")))), "tools");
      source = string(fileread(fullfile(tools_dir, "run_check_logger_bin.m")));

      testCase.verifyTrue(contains(source, ...
        'if ~exist("target_file", "var")'));
      testCase.verifyTrue(contains(source, ...
        'if ~exist("render_plots", "var")'));
      testCase.verifyTrue(contains(source, ...
        "if render_plots && out.record_count > 0"));
    end

    function discoveryDefaultsToActiveRuntimePorts(testCase)
      tools_dir = fullfile(fileparts(fileparts(fileparts( ...
        mfilename("fullpath")))), "tools");
      source = string(fileread(fullfile(tools_dir, ...
        "run_ads_discovery_demo.m")));

      testCase.verifyTrue(contains(source, ...
        'if ~exist("optional_probe_ports", "var")'));
      testCase.verifyTrue(contains(source, ...
        "env.control_port, env.seq_port, env.module_port"));
      testCase.verifyFalse(contains(source, "unique([851"), ...
        "Port 851 must never be a default discovery requirement.");
    end
  end
end
