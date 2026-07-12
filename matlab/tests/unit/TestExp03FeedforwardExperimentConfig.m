classdef TestExp03FeedforwardExperimentConfig < matlab.unittest.TestCase
  methods (Test)
    function studentSurfaceAndSectionsRemainStable(testCase)
      source = read_source("exp03_FeedForward.m");
      required = [ ...
        "%[text] ### STEP 1: DESIGN FEEDBACK CONTROLLER"
        "%[text] ### Check the stability and performance of FB Controller (Always check before experiment!!!)"
        "%[text] ### **Design Feedforward input**"
        "%[text] execute experiment via simulink"
        "Kfa = [];"
        "Kfv = [];"
        "Kfc = [];"
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

    function scriptUsesSharedContractsAndPreservesResult(testCase)
      source = read_source("exp03_FeedForward.m");
      required = [ ...
        "experiment.exp0n.load_plant_data("
        "experiment.exp0n.load_trajectory("
        "experiment.exp01.assert_plant_provenance("
        "experiment.exp02.stability_check("
        "experiment.exp0n.assert_run_contract("
        'save(char(feedforward_result_path), "t", "r", "y", "e", "u", "f", "Kd")'];
      for value = required'
        testCase.verifyTrue(contains(source, value));
      end
    end
  end
end

function source = read_source(file_name)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
source = string(fileread(fullfile(root, "experiment", file_name)));
end
