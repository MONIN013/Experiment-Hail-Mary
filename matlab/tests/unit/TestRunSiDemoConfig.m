classdef TestRunSiDemoConfig < matlab.unittest.TestCase
  methods (Test)
    function demoUsesExperimentRunnerAndAnalysisHelpers(testCase)
      script_path = fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "run_si_demo.m");
      source = string(fileread(script_path));

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg = experiment.ExperimentConfig.defaults();"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        'logger_dir = string(fileparts(char(sys.LOGGER_DEFAULT_FILE_PATH)));'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "chirp_cfg = experiment.build_periodic_chirp("));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "run_out = experiment.ExperimentRunner.run(conn, cfg);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "frf_out = experiment.analyze_si_frf(logger_bin, ..."));
    end

    function demoPinsSiSpecificProfiles(testCase)
      script_path = fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "run_si_demo.m");
      source = string(fileread(script_path));

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.ref_profile = zeros(sample_n, 1);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.ff_profile = chirp_cfg.signal(:);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.dist_profile = zeros(sample_n, 1);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.repeat_count = 1;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.controller = experiment.ControllerConfig.p_only(Kp);"));
    end
  end
end
