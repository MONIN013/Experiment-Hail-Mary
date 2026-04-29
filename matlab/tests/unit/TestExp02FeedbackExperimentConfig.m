classdef TestExp02FeedbackExperimentConfig < matlab.unittest.TestCase
  methods (Test)
    function scriptKeepsLiveScriptPlainTextStructure(testCase)
      source = read_exp02_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] # 概要"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 前提確認"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## セットアップ"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 制御器設計"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 軌道生成"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 実験実行"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 可視化"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 次の調整指針"));
    end

    function scriptUsesCurrentExperimentApis(testCase)
      source = read_exp02_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg = experiment.ExperimentConfig.defaults();"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "conn = experiment.ConnectionManager.create(cfg);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "run_out = experiment.ExperimentRunner.run(conn, cfg);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "latest_bin = experiment.read_latest_logger_bin(logger_dir, logger_file_glob);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.ref_profile = ref_profile(:);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg.controller = controller_cfg;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "feedback_out = struct( ..."));
    end

    function scriptRemovesLegacyDependencies(testCase)
      source = read_exp02_source();

      testCase.verifyFalse(contains(source, "obtainMeasurement"));
      testCase.verifyFalse(contains(source, "open(ModelName)"));
      testCase.verifyFalse(contains(source, 'load("./../config/data'));
      testCase.verifyFalse(contains(source, "load('./../demo1_SI"));
      testCase.verifyFalse(contains(source, 'save("data/feedback_result.mat"'));
      testCase.verifyFalse(contains(source, "%[appendix]"));
      testCase.verifyFalse(contains(source, "data:image"));
    end

    function scriptPinsInitialControllerAndHelpers(testCase)
      source = read_exp02_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Kp = 0.0007;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Ki = 0.004;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Kd = 2.5e-06;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Tf = 0.025;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("K_cont = pid(Kp, Ki, Kd, Tf);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring('Kd_z = c2d(K_cont, Ts, "tustin");'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "function controller_cfg = controller_config_from_discrete_tf(Kd_z)"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "function stage = biquad_stage_from_discrete_tf(Kd_z)"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "function ref_profile = load_reference_profile_from_mat(file_path, variable_name)"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "function ref_profile = build_step_reference(target_position_rad, pre_step_s, step_hold_s, Ts)"));
    end

    function scriptKeepsTrajectoryMatHook(testCase)
      source = read_exp02_source();

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
