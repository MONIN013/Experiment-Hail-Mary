classdef TestExp02FeedbackExperimentConfig < matlab.unittest.TestCase
  methods (Test)
    function scriptUsesStudentFacingLiveScriptShape(testCase)
      source = read_exp02_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] # exp02 Feedback Experiment"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 安全確認"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 学生が調整するパラメータ"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 環境読み込み"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 制御器設計"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 安定性・性能確認"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 軌道生成"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 実験実行"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 結果整理"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 可視化"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 次の調整指針"));

      testCase.verifyFalse(contains(source, newline + "function "));
      testCase.verifyFalse(startsWith(source, "function "));
    end

    function scriptUsesCurrentConfigAndHelperPackages(testCase)
      source = read_exp02_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg = experiment.ExperimentConfig.defaults();"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "controller_cfg = experiment.controller.from_discrete_tf(Kd_z);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "ref_profile = experiment.exp02.reference_profile("));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "collect_out = experiment.exp0n.run_and_collect(cfg);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "logger_bin = collect_out.logger_bin;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "[signals, feedback_metrics] = experiment.exp02.signals_from_logger_bin(logger_bin);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "experiment.plot.feedback_result(signals, feedback_metrics);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "stability_check = experiment.exp02.stability_check(Kd_z, plant_mat_path, Smax, Ts, nominal_sample_delay);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "save(char(feedback_result_path)"));
    end

    function scriptIncludesProtoDemo2Flow(testCase)
      source = read_exp02_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "Demo2: Feedback Control Experiment"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "STEP 1 DESIGN FEEDBACK CONTROLLER"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "Always check before experiment"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "STEP 2 FEEDBACK EXPERIMENT"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "STEP 3 Analyze results"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "tracking_error_norm = norm(signals.error);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "stability_check = experiment.exp02.stability_check("));
    end

    function scriptKeepsStudentParametersAtTop(testCase)
      source = read_exp02_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Kp = 0.7;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Ki = 0.03;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Kd = 2.5e-03;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Tf = 0.025;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Smax = 2;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring('trajectory_mat_path = "";'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring('trajectory_variable_name = "ref_profile";'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("target_position_rad = deg2rad(2);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("pre_step_s = 1.0;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("step_hold_s = 2.0;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("repeat_count = 1;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("plant_mat_path = fullfile(result_dir, ""plant.mat"");"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("feedback_result_path = fullfile(result_dir, ""feedback_result.mat"");"));
    end

    function stabilityCheckMissingPlantMatReturnsStatusWithoutFigures(testCase)
      missing_path = fullfile(tempdir, "experiment_hail_mary_missing_plant.mat");
      if isfile(missing_path)
        delete(missing_path);
      end

      figures_before = findall(groot, "Type", "figure");
      out = [];
      testCase.verifyWarning(@call_stability_check, "experiment:exp02_feedback:plantMatMissing");
      figures_after = findall(groot, "Type", "figure");

      testCase.verifyFalse(out.ok);
      testCase.verifyEqual(out.plant_mat_path, string(missing_path));
      testCase.verifyEqual(out.reason, "plant_mat_missing");
      testCase.verifyEqual(numel(figures_after), numel(figures_before));

      function call_stability_check()
        out = experiment.exp02.stability_check([], missing_path, 2, 1 / 8000, 4);
      end
    end
  end
end

function source = read_exp02_source()
script_path = fullfile( ...
  fileparts(fileparts(fileparts(mfilename("fullpath")))), ...
  "experiment", ...
  "exp02_FeedBack.m");
source = string(fileread(script_path));
end
