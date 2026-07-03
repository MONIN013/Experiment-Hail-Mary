classdef TestExp01SiConfig < matlab.unittest.TestCase
  methods (Test)
    function scriptUsesStudentFacingLiveScriptShape(testCase)
      source = read_exp01_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ## Demo1: System Identification using chirp signal"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ### STEP 1: LOAD CONFIGURATION"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ### STEP2 DESIGN EXCITATION SIGNAL"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ### STEP3: GENERATE CHIRP SIGNAL"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ### STEP4: RUN EXPERIMENT"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ### STEP5: ANALYZE FRF"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("%[text] ### STEP6: PLOT AND SAVE RESULTS"));

      testCase.verifyFalse(contains(source, newline + "function "));
      testCase.verifyFalse(startsWith(source, "function "));
    end

    function scriptUsesCurrentConfigAndHelperPackages(testCase)
      source = read_exp01_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "cfg = experiment.ExperimentConfig.defaults();"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "chirp_cfg = experiment.waveform.periodic_chirp("));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "collect_out = experiment.exp0n.run_and_collect(cfg);"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "logger_bin = collect_out.logger_bin;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "vm_cfg = experiment.exp01.nominal_overlay_plant();"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "frf_nominal = experiment.analysis.nominal_two_inertia_frf("));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "experiment.plot.si_frf("));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "save(""exp01_SI_results.mat"", ""si_out"", ""-v7.3"");"));
    end

    function scriptIncludesProtoDemo1Flow(testCase)
      source = read_exp01_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "Demo1: System Identification using chirp signal"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "STEP 1: LOAD CONFIGURATION"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "STEP2 DESIGN EXCITATION SIGNAL"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "STEP3: GENERATE CHIRP SIGNAL"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "STEP4: RUN EXPERIMENT"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        "STEP5: ANALYZE FRF"));
    end

    function scriptKeepsStudentParametersAtTop(testCase)
      source = read_exp01_source();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Tcycle_s = 10;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("repeat_count = 10;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("f0_hz = 0.5;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("f1_hz = 4000;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("chirp_amplitude = 0.1;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("transient_cycles = 3;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("initial_phase_rad = 0;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("hold_margin_s = 1.0;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("Kp = 0;"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("nominal_sample_delay = 4;"));
    end
  end
end

function source = read_exp01_source()
script_path = fullfile( ...
  fileparts(fileparts(fileparts(mfilename("fullpath")))), ...
  "experiment", ...
  "exp01_SysId.m");
source = string(fileread(script_path));
end
