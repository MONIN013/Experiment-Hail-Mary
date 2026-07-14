classdef TestExp01SiConfig < matlab.unittest.TestCase
  methods (Test)
    function studentSurfaceAndSectionsRemainStable(testCase)
      source = read_student_surface("exp01_SysId.m");
      required = [ ...
        "%[text] ### STEP 1: CHIRP EXCITATION"
        "%[text] ### STEP 2: TIME TREATMENT"
        "%[text] ### STEP 3: NON-PARAMETRIC ESTIMATION"
        "Tend = 100;"
        "Tcycle = 10;"];
      for value = required'
        testCase.verifyTrue(contains(source, value));
      end
      testCase.verifyFalse(contains(source, newline + "function "));
    end

    function scriptDelegatesConfigurationAndExecution(testCase)
      source = read_student_surface("exp01_SysId.m");
      testCase.verifyTrue(contains(source, "experiment.scenario.exp01("));
      testCase.verifyTrue(contains(source, "experiment.workflow.run_exp01(scenario)"));
      testCase.verifyTrue(contains(source, "f0 = 0.5;"));
      testCase.verifyTrue(contains(source, "A = 0.25;"));
      testCase.verifyTrue(contains(source, "Ndelay = 4;"));
      testCase.verifyFalse(contains(source, "sweep_type"));
      verify_normal_flow_has_no_vm_oracle(testCase, source);
    end

    function scriptUsesNamedLiveEditorSummaries(testCase)
      source = read_student_surface("exp01_SysId.m");
      required = ["scenario_table = table(", "run_summary = table(", ...
        "artifact_summary = table(", "quality_summary = table(", ...
        "VariableNames="];
      for value = required
        testCase.verifyTrue(contains(source, value));
      end
    end

    function workflowPreservesPlantHandoffArtifact(testCase)
      source = read_package_source("+experiment", "+workflow", "run_exp01.m");
      required = ["experiment.exp0n.run_and_collect", ...
        "experiment.exp0n.assert_run_contract", ...
        '"ff_value"', ...
        "position_integrator = Ts*z/(z-1)", ...
        '"Pd", Pd, "Pd_motor", Pd_motor, "Pd_load", Pd_load', ...
        '"Pdn", Pdn, "Jn", Jn, "Dn", Dn, "Ndelay", Ndelay, "Ts", Ts'];
      for value = required
        testCase.verifyTrue(contains(source, value));
      end
      testCase.verifyFalse(contains(source, 'c2d(1 / s'));
      verify_normal_flow_has_no_vm_oracle(testCase, source);
    end
  end
end

function source = read_student_surface(file_name)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
source = string(fileread(fullfile(root, "experiment", file_name)));
appendix = strfind(source, "%[appendix]");
if ~isempty(appendix)
  source = extractBefore(source, appendix(1));
end
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
