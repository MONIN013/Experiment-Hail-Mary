classdef TestExp04IlcExperimentConfig < matlab.unittest.TestCase
  methods (Test)
    function studentSurfaceAndSectionsRemainStable(testCase)
      source = read_source("exp04_ILC.m");
      required = [ ...
        "STEP 1: DESIGN FEEDBACK CONTROLLER"
        "STEP 2: ILC EXPERIMENT"
        "STEP 3: Analyze the results"
        "Ntrial = 10;"
        "alpha = 0.6;"
        "q_cutoff_hz = 120;"
        "maxInput = 1.6;"
        "use_virtual_motor = true;"];
      for value = required'
        testCase.verifyTrue(contains(source, value));
      end
      testCase.verifyTrue(contains(source, "cfg.restart_virtual_motor_runtime = false;"));
      testCase.verifyFalse(contains(source, "q_cutoff_hz = 10;"));
      testCase.verifyFalse(contains(source, newline + "function "));
    end

    function scriptUsesPureHelpersAndDoesNotDeletePriorRuns(testCase)
      source = read_source("exp04_ILC.m");
      required = [ ...
        "experiment.exp0n.load_plant_data("
        "experiment.exp0n.load_trajectory("
        "experiment.exp01.assert_plant_provenance("
        "experiment.exp02.stability_check("
        "experiment.exp04.design_learning_filters("
        "experiment.exp04.learning_update("
        'fullfile(result_dir, "exp04_runs", run_stamp)'
        "history.maxAbsInput"
        "history.errorIncreased"
        "history.convergencePeak"
        "history.trialSummary"
        'save(char(ilc_result_path), "t", "history", "Kd", "stability", "learning_filters")'];
      for value = required'
        testCase.verifyTrue(contains(source, value));
      end
      testCase.verifyFalse(contains(source, "experiment.exp04.precompute_virtual_motor_plan("));
      testCase.verifyFalse(contains(source, "vm_plan ="));
      testCase.verifyFalse(contains(source, "vm_plan."));
      testCase.verifyFalse(contains(source, "virtualMotor.predict_logger("));
      testCase.verifyFalse(contains(source, "virtualMotor.compare_prediction("));
      testCase.verifyFalse(contains(source, "virtualMotor.assert_prediction("));
      testCase.verifyTrue(contains(source, "history.f(:, j + 1) = f_jplus1;"));
      testCase.verifyFalse(contains(source, 'history.stopReason = "error_increase"'));
      testCase.verifyFalse(contains(source, "delete("));
    end
  end
end

function source = read_source(file_name)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
source = string(fileread(fullfile(root, "experiment", file_name)));
end
