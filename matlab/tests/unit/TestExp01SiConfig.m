classdef TestExp01SiConfig < matlab.unittest.TestCase
  methods (Test)
    function studentSurfaceAndSectionsRemainStable(testCase)
      source = read_source("exp01_SysId.m");
      required = [ ...
        "%[text] ### STEP 1: CHIRP EXCITATION"
        "%[text] ### STEP 2: TIME TREATMENT"
        "%[text] ### STEP 3: NON-PARAMETRIC ESTIMATION"
        "Tend = 100;"
        "Tcycle = 10;"
        "use_virtual_motor = true;"];
      for value = required'
        testCase.verifyTrue(contains(source, value));
      end
      testCase.verifyFalse(contains(source, newline + "function "));
    end

    function scriptUsesSharedRuntimeAndChirpContracts(testCase)
      source = read_source("exp01_SysId.m");
      testCase.verifyTrue(contains(source, "experiment.waveform.periodic_chirp("));
      testCase.verifyTrue(contains(source, "f0 = 0.5;"));
      testCase.verifyTrue(contains(source, "A = 0.25;"));
      testCase.verifyTrue(contains(source, "Ndelay = 4;"));
      testCase.verifyFalse(contains(source, "sweep_type"));
      testCase.verifyTrue(contains(source, "experiment.exp0n.run_and_collect(cfg)"));
      testCase.verifyTrue(contains(source, "experiment.exp0n.assert_run_contract(run_out)"));
      testCase.verifyTrue(contains(source, "cfg.write_virtual_motor_params = use_virtual_motor"));
      testCase.verifyTrue(contains(source, "cfg.restart_virtual_motor_runtime = false"));
      testCase.verifyFalse(contains(source, "virtualMotor.predict_logger("));
      testCase.verifyFalse(contains(source, "virtualMotor.compare_prediction("));
      testCase.verifyFalse(contains(source, "virtualMotor.assert_prediction("));
      testCase.verifyTrue(contains(source, "vm_mode = virtualMotor.torsional_mode("));
    end

    function scriptPreservesPlantHandoffVariables(testCase)
      source = read_source("exp01_SysId.m");
      testCase.verifyTrue(contains(source, "'vm_plant', 'vm_mode'"));
    end
  end
end

function source = read_source(file_name)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
source = string(fileread(fullfile(root, "experiment", file_name)));
end
