classdef TestExp02FeedbackExperimentConfig < matlab.unittest.TestCase
  methods (Test)
    function studentSurfaceAndSectionsRemainStable(testCase)
      source = read_source("exp02_FeedBack.m");
      required = [ ...
        "STEP 1: DESIGN FEEDBACK CONTROLLER"
        "Always check before experiment"
        "STEP 2: FEEDBACK EXPERIMENT"
        "STEP 3: Analyze the results"
        "omega = 15;"
        "Smax = 2;"
        "use_virtual_motor = true;"];
      for value = required'
        testCase.verifyTrue(contains(source, value));
      end
      testCase.verifyTrue(contains(source, "cfg.restart_virtual_motor_runtime = false"));
      testCase.verifyFalse(contains(source, "virtualMotor.predict_logger("));
      testCase.verifyFalse(contains(source, "virtualMotor.compare_prediction("));
      testCase.verifyFalse(contains(source, "virtualMotor.assert_prediction("));
      testCase.verifyFalse(contains(source, newline + "function "));
    end

    function scriptUsesStrictSharedHelpers(testCase)
      source = read_source("exp02_FeedBack.m");
      required = [ ...
        "experiment.exp0n.load_plant_data("
        "experiment.exp0n.load_trajectory("
        "experiment.exp01.assert_plant_provenance("
        "experiment.exp02.stability_check("
        "experiment.exp02.signals_from_logger_bin("
        "experiment.exp0n.assert_run_contract("
        "experiment.plot.feedback_result("];
      for value = required'
        testCase.verifyTrue(contains(source, value));
      end
    end

    function scriptPreservesResultContract(testCase)
      source = read_source("exp02_FeedBack.m");
      testCase.verifyTrue(contains(source, ...
        'save(char(feedback_result_path), "t", "r", "y", "e", "u", "Kd")'));
    end
  end
end

function source = read_source(file_name)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
source = string(fileread(fullfile(root, "experiment", file_name)));
end
