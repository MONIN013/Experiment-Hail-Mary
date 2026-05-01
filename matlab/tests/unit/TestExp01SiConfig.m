classdef TestExp01SiConfig < matlab.unittest.TestCase
  methods (Test)
    function scriptUsesStudentFacingLiveScriptShape(testCase)
      source = read_exp01_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] # exp01 System Identification"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 安全確認"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 学生が調整するパラメータ"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 環境読み込み"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## chirp 生成"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 実験実行"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## FRF 解析"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 可視化"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## 次の調整指針"));

      testCase.verifyFalse(contains(source, "%[appendix]"));
      testCase.verifyFalse(contains(source, "data:image"));
      testCase.verifyFalse(contains(source, newline + "function "));
      testCase.verifyFalse(startsWith(source, "function "));
    end

    function scriptUsesCurrentConfigAndHelperPackages(testCase)
      source = read_exp01_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg = experiment.ExperimentConfig.defaults();"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        'logger_dir = string(fileparts(char(cfg.env.logger_host_file_path)));'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "chirp_cfg = experiment.waveform.periodic_chirp("));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "latest_bin = experiment.io.read_latest_logger_bin(logger_dir, logger_file_glob);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "vm_cfg = experiment.exp01.nominal_overlay_plant();"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "frf_nominal = experiment.analysis.nominal_two_inertia_frf("));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "experiment.plot.si_frf("));
    end

    function scriptKeepsStudentParametersAtTop(testCase)
      source = read_exp01_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Tend_s = 10;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Tcycle_s = 10;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("repeat_count = 10;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("f0_hz = 0.5;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("f1_hz = 4000;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("chirp_amplitude = 0.1;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("transient_cycles = 3;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("initial_phase_rad = 0;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("hold_margin_s = 1.0;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Kp = 0;"));
    end
  end
end

function source = read_exp01_source()
script_path = fullfile( ...
  fileparts(fileparts(fileparts(mfilename("fullpath")))), ...
  "experiment", ...
  "exp01_SI.m");
source = string(fileread(script_path));
end
