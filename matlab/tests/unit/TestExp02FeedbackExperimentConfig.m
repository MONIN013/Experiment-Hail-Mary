classdef TestExp02FeedbackExperimentConfig < matlab.unittest.TestCase
  methods (Test)
    function studentSurfaceAndSectionsRemainStable(testCase)
      source = read_student_surface("exp02_FeedBack.m");
      required = [ ...
        "STEP 1: DESIGN FEEDBACK CONTROLLER"
        "Always check before experiment"
        "STEP 2: FEEDBACK EXPERIMENT"
        "STEP 3: Analyze the results"
        "omega = 15;"
        "Smax = 2;"];
      for value = required'
        testCase.verifyTrue(contains(source, value));
      end
      testCase.verifyFalse(contains(source, newline + "function "));
    end

    function scriptDelegatesToScenarioAndWorkflow(testCase)
      source = read_student_surface("exp02_FeedBack.m");
      required = [ ...
        "experiment.exp0n.load_plant_data("
        "experiment.exp0n.load_trajectory("
        "experiment.scenario.exp02("
        "experiment.workflow.run_exp02(scenario)"
        "experiment.plot.feedback_result("];
      for value = required'
        testCase.verifyTrue(contains(source, value));
      end
      verify_normal_flow_has_no_vm_oracle(testCase, source);
    end

    function scriptUsesNamedLiveEditorSummaries(testCase)
      source = read_student_surface("exp02_FeedBack.m");
      for required = ["stability_summary = table(", ...
          "artifact_summary = table(", "tracking_summary = table(", ...
          "VariableNames="]
        testCase.verifyTrue(contains(source, required));
      end
    end

    function workflowPreservesNumericResultContract(testCase)
      source = read_package_source("+experiment", "+workflow", "run_exp02.m");
      testCase.verifyTrue(contains(source, ...
        '"t", "r", "y", "e", "u", "Kd", "feedback_metrics", "stability"'));
      testCase.verifyTrue(contains(source, "experiment.exp0n.assert_run_contract"));
      verify_normal_flow_has_no_vm_oracle(testCase, source);
    end
  end
end

function source = read_student_surface(file_name)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
source = string(fileread(fullfile(root, "experiment", file_name)));
appendix = strfind(source, "%[appendix]");
if ~isempty(appendix), source = extractBefore(source, appendix(1)); end
end

function source = read_package_source(varargin)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
source = string(fileread(fullfile(root, varargin{:})));
end

function verify_normal_flow_has_no_vm_oracle(testCase, source)
for forbidden = [ ...
    "virtualMotor.predict_logger(", "virtualMotor.compare_prediction(", ...
    "virtualMotor.assert_prediction(", "virtualMotor.restart_runtime(", ...
    "virtualMotor.configure(", "virtualMotor.writeParams("]
  testCase.verifyFalse(contains(source, forbidden), ...
    "Normal experiment flow must not contain test-only VM operations.");
end
end
