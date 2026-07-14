classdef TestFullVmManifestE2eConfig < matlab.unittest.TestCase
  methods (Test)
    function registryContainsAllFourExperimentsAndElevenTools(testCase)
      registry = testoracle.entry_registry();
      testCase.verifyEqual(numel(registry), 15);
      testCase.verifyEqual(nnz(string({registry.kind}) == "experiment"), 4);
      testCase.verifyEqual(nnz(string({registry.kind}) == "tool"), 11);
      testCase.verifyEqual(numel(unique(string({registry.name}))), 15);
      exp04 = registry(string({registry.name}) == "experiment.exp04");
      benchmark = registry(string({registry.name}) == ...
        "tools.run_controller_benchmark");
      testCase.verifyEqual(exp04.restart_policy, "campaign_once");
      testCase.verifyEqual(benchmark.restart_policy, ...
        "per_controller_test_then_normal_tool");
      phases = [registry.phase];
      testCase.verifyEqual(phases, sort(phases));
      testCase.verifyTrue(all(phases(1:4) == 1));
      testCase.verifyGreaterThanOrEqual(phases(5), 2);
    end

    function orchestratorUsesConcreteCapturedFourLayerExecutor(testCase)
      root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
      source = string(fileread(fullfile(root, "tools", ...
        "run_full_vm_manifest_e2e.m")));
      required = [ ...
        "testoracle.build_default_layers()"
        "testoracle.build_manifest(layers)"
        "testoracle.freeze_manifest(manifest"
        "@testoracle.default_entry_executor"
        "testoracle.record_entry("
        "testoracle.finalize_ledger(ledger, final_state)"
        "validate_restart_policy"];
      for value = required'
        testCase.verifyTrue(contains(source, value), value);
      end
      freeze_position = strfind(source, "testoracle.freeze_manifest(manifest");
      execute_position = strfind(source, "result = executor(");
      testCase.verifyLessThan(freeze_position(1), execute_position(1));
      testCase.verifyFalse(contains(source, "skip" + "ped"));
      testCase.verifyTrue(contains(source, ...
        "double(registry_entry.phase) >= 2"));
      testCase.verifyTrue(contains(source, "testoracle.CleanupArm()"));
      testCase.verifyTrue(contains(source, "cleanup_arm.Armed = false"));
      testCase.verifyFalse(contains(source, ...
        "onCleanup(@() safe_restore(restore))"));
    end

    function childRequiresThirtyLoggersAndRunsCheckerForEach(testCase)
      source = string(fileread(which("testoracle.child_entry_worker")));
      required = ["paths = strings(30, 1)"; "for trial = 1:10"; ...
        "for prefix = [""test"", ""normal""]"; "run(checker_path)"; ...
        "campaignSetMismatch"; "checked_count"];
      for value = required'
        testCase.verifyTrue(contains(source, value), value);
      end
    end

    function predictionRestartCountComesFromValidatedToolEvidence(testCase)
      source = string(fileread(which("testoracle.child_entry_worker")));
      testCase.verifyTrue(contains(source, ...
        "testoracle.validate_restart_proof(value.restart)"));
      testCase.verifyTrue(contains(source, ...
        "capture.restart_count = capture.restart_proof.restart_count"));
      testCase.verifyFalse(contains(source, "capture.restart_count = 1"));
    end

    function liveRefreshRequiresTwoIndependentFreshnessDigests(testCase)
      worker = string(fileread(which("testoracle.child_entry_worker")));
      reports = string(fileread(which("testoracle.build_layer_reports")));
      for value = ["experiment.liveeditor.inspect(file_path)"; ...
          "testoracle.file_sha256(file_path)"; ...
          "testoracle.live_freshness_evidence"]'
        testCase.verifyTrue(contains(worker, value), value);
      end
      testCase.verifyTrue(contains(reports, ...
        "evidence.file_sha256_changed"));
      testCase.verifyTrue(contains(reports, ...
        "evidence.output_json_digest_changed"));
      pass_region = extractBetween(reports, ...
        'live = struct(', '"applicable", true, "report", live_report');
      testCase.verifyFalse(contains(pass_region, ...
        "source_timestamp_not_older"), ...
        "mtime must remain auxiliary and must not gate Live freshness.");
    end

    function loggerCaptureSourceContainsThreeDigestGate(testCase)
      source = string(fileread(which("testoracle.capture_logger_artifact")));
      for value = ["provided_digest", "source_digest", "campaign_digest", ...
          "provided_raw_digest", "source_raw_digest", "campaign_raw_digest"]
        testCase.verifyTrue(contains(source, value), value);
      end
    end

    function finalStateContractIncludesDriveStatusAndControllerRevision(testCase)
      source = string(fileread(which("testoracle.verify_final_state")));
      for value = ["modeFlags", "modeState", "experimentActive", ...
          "resetReq", "idx", "tableLen", "loggerErrorCode", ...
          "apply_revision", "processed_revision", ...
          "parameter_error_code", "motor_status", "load_status", "0060"]
        testCase.verifyTrue(contains(source, value), value);
      end
    end

    function outcomeScoringDoesNotRegenerateExpectedModelsAfterRun(testCase)
      source = string(fileread(which("testoracle.actual_outcome")));
      forbidden = ["controller_catalog"; "load_plant_data"; ...
        "load_trajectory"; "feedback_result.mat"; ...
        "virtualMotor.discrete_velocity_frf"; ...
        "virtualMotor.torsional_mode"];
      for value = forbidden'
        testCase.verifyFalse(contains(source, value), value);
      end
      required = ["expected.exact.analysis"; ...
        "expected.independent.response.exp01_workflow_frf"; ...
        "expected.exact.feedforward"; ...
        '"experiment_exp02", "run.bin"'; ...
        "expected.independent.response.si_analysis"; ...
        "expected.exact.controllers"];
      for value = required'
        testCase.verifyTrue(contains(source, value), value);
      end
      testCase.verifyTrue(contains(source, ...
        "frequency_band = full_frequency >= reference_frequency(1)"));
      testCase.verifyTrue(contains(source, ...
        "full_frequency <= reference_frequency(end)"));
    end
  end
end
