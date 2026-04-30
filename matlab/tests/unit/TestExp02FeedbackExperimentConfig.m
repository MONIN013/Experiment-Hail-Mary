classdef TestExp02FeedbackExperimentConfig < matlab.unittest.TestCase
  methods (Test)
    function scriptUsesStudentFacingLiveScriptShape(testCase)
      source = read_exp02_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] # exp02 Feedback Experiment"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 安全確認"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 学生が調整するパラメータ"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 環境読み込み"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 制御器設計"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 軌道生成"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 実験実行"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 結果整理"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 可視化"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 次の調整指針"));

      testCase.verifyFalse(contains(source, "%[appendix]"));
      testCase.verifyFalse(contains(source, "data:image"));
      testCase.verifyFalse(contains(source, newline + "function "));
      testCase.verifyFalse(startsWith(source, "function "));
    end

    function scriptUsesCurrentConfigAndHelperPackages(testCase)
      source = read_exp02_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "sys = config.SystemConfig.current();"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        'logger_dir = string(fileparts(char(sys.LOGGER_HOST_FILE_PATH)));'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "controller_cfg = experiment.controller.from_discrete_tf(Kd_z);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "ref_profile = experiment.exp02.reference_profile("));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "latest_bin = experiment.io.read_latest_logger_bin(logger_dir, logger_file_glob);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "[signals, feedback_metrics] = experiment.exp02.signals_from_logger_bin(logger_bin);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "experiment.plot.feedback_result(signals, feedback_metrics);"));
    end

    function scriptKeepsStudentParametersAtTop(testCase)
      source = read_exp02_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Kp = 0.7;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Ki = 0.4;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Kd = 2.5e-03;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Tf = 0.025;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring('trajectory_mat_path = "";'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring('trajectory_variable_name = "ref_profile";'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("target_position_rad = deg2rad(2);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("pre_step_s = 1.0;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("step_hold_s = 2.0;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("repeat_count = 1;"));
    end
  end
end

function source = read_exp02_source()
script_path = fullfile( ...
  fileparts(fileparts(fileparts(mfilename("fullpath")))), ...
  "experiment", ...
  "exp02_feedback_experiment.m");
source = string(fileread(script_path));
end
