classdef TestExp04IlcExperimentConfig < matlab.unittest.TestCase
  methods (Test)
    function studentSurfaceAndSectionsRemainStable(testCase)
      source = read_student_surface("exp04_ILC.m");
      required = [ ...
        "STEP 1: DESIGN FEEDBACK CONTROLLER"
        "STEP 2: ILC EXPERIMENT"
        "STEP 3: Analyze the results"
        "Ntrial = 10;"
        "alpha = 0.6;"
        "q_cutoff_hz = 120;"
        "maxInput = 1.6;"
        "settling_tail_s = 9.0;"];
      for value = required'
        testCase.verifyTrue(contains(source, value));
      end
      testCase.verifyFalse(contains(source, "q_cutoff_hz = 10;"));
      testCase.verifyFalse(contains(source, newline + "function "));
    end

    function scriptDelegatesToScenarioAndCampaignWorkflow(testCase)
      source = read_student_surface("exp04_ILC.m");
      required = [ ...
        "experiment.exp0n.load_plant_data("
        "experiment.exp0n.load_trajectory("
        "experiment.scenario.exp04("
        "experiment.workflow.run_exp04("
        "trial_summary = history.trialSummary"
        "campaign_summary = table("
        "artifact_summary = table("];
      for value = required'
        testCase.verifyTrue(contains(source, value));
      end
      verify_normal_flow_has_no_vm_oracle(testCase, source);
    end

    function workflowRefreshesDashboardBeforeLearningUpdate(testCase)
      source = read_package_source("+experiment", "+workflow", "run_exp04.m");
      dashboard_call = strfind(source, "experiment.exp04.update_trial_dashboard(");
      learning_call = strfind(source, "experiment.exp04.learning_update(");
      testCase.verifyNotEmpty(dashboard_call);
      testCase.verifyNotEmpty(learning_call);
      testCase.verifyLessThan(dashboard_call(1), learning_call(1), ...
        "Each completed trial must be displayed before its learning update.");
      testCase.verifyTrue(contains(source, ...
        "experiment.exp04.checkpoint_partial_history("));
      testCase.verifyTrue(contains(source, "rethrow(cause)"));
      testCase.verifyTrue(contains(source, '"image_files", strings(0, 1)'));
      verify_no_image_export(testCase, source);
      verify_normal_flow_has_no_vm_oracle(testCase, source);
    end

    function dashboardContractHasThreePanelsAndInteractiveDrawnow(testCase)
      source = read_package_source("+experiment", "+exp04", ...
        "update_trial_dashboard.m");
      required = ["tiledlayout(fig, 3, 1", ...
        "Reference vs. Actual", "Tracking Error", ...
        "Feedforward vs. Feedback Input", "drawnow limitrate", ...
        "errorNorm", "maxAbsFeedforwardA", "maxAbsTotalInputA"];
      for value = required
        testCase.verifyTrue(contains(source, value));
      end
      verify_no_image_export(testCase, source);
    end

    function checkpointContractPersistsPartialHistoryWithoutImages(testCase)
      source = read_package_source("+experiment", "+exp04", ...
        "checkpoint_partial_history.m");
      required = ["completedTrials", "stopReason", "trialSummary", ...
        'save(temporary_path, "history")', ...
        'movefile(temporary_path, file_path, "f")'];
      for value = required
        testCase.verifyTrue(contains(source, value));
      end
      verify_no_image_export(testCase, source);
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

function verify_no_image_export(testCase, source)
for forbidden = ["exportgraphics(", "saveas(", "imwrite(", ...
    ".png", ".jpg", ".jpeg"]
  testCase.verifyFalse(contains(lower(source), lower(forbidden)), ...
    "ILC trials must not write image artifacts.");
end
testCase.verifyEmpty(regexp(source, "(?m)^\s*print\s*\(", "once"), ...
  "ILC trials must not write image artifacts with print().");
end
