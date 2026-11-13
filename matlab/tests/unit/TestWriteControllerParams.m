classdef TestWriteControllerParams < matlab.unittest.TestCase
  methods (Test)
    function writesPayloadThenCountThenRevisionAndWaitsForAck(testCase)
      transport = MockAdsTransport();
      prefix = "Controller.";
      seed_status(transport, prefix, uint32(7));
      cfg = experiment.ControllerConfig.from_struct(struct( ...
        "sos", [2, 3, 4, 1, 5, 6; 7, 8, 9, 1, 10, 11]));

      applied = experiment.write_controller_params(transport, prefix, cfg);

      testCase.verifyEqual(applied, uint32(8));
      writes = transport.operations(startsWith(transport.operations, "write_"));
      testCase.verifyEqual(writes(1), "write_array:Controller.SosCoefficients");
      testCase.verifyEqual(writes(2), "write_scalar:Controller.SosSectionCount");
      testCase.verifyEqual(writes(3:7), [ ...
        "write_scalar:Controller.HigsEnabled"; "write_scalar:Controller.HigsGain"; ...
        "write_scalar:Controller.HigsOmegaTs"; "write_scalar:Controller.HigsPreSectionCount"; ...
        "write_scalar:Controller.SosApplyRevision"]);
      testCase.verifyFalse(transport.scalarMap("Controller.HigsEnabled"));
      testCase.verifyEqual(transport.scalarMap("Controller.SosSectionCount"), uint32(2));
      testCase.verifyEqual(transport.scalarMap("Controller.SosApplyRevision"), uint32(8));

      rows = reshape(transport.arrayMap("Controller.SosCoefficients"), 5, []).';
      testCase.verifyEqual(rows(1:2, :), [2, 3, 4, 5, 6; 7, 8, 9, 10, 11]);
      testCase.verifyEqual(rows(3:end, :), repmat([1, 0, 0, 0, 0], 8, 1));
    end

    function higsWritesCommitTogetherAndFailedPayloadDoesNotCommit(testCase)
      transport = MockAdsTransport();
      seed_status(transport, "Controller.", uint32(1));
      cfg = experiment.ControllerConfig.from_struct(struct( ...
        "sample_time_s", 1/8000, "higs_enabled", true, ...
        "higs_gain", 1, "higs_omega_ts", 0.01));
      experiment.write_controller_params(transport, "Controller.", cfg);
      testCase.verifyTrue(transport.scalarMap("Controller.HigsEnabled"));
      testCase.verifyEqual(transport.scalarMap("Controller.HigsOmegaTs"), 0.01);
      transport.set_scalar_write_error("Controller.HigsGain", ...
        "test:payloadFailed", "injected HIGS write failure");
      testCase.verifyError(@() experiment.write_controller_params(transport, "Controller.", cfg), ...
        "test:payloadFailed");
      testCase.verifyEqual(transport.scalarMap("Controller.SosApplyRevision"), uint32(2));
    end

    function reportsControllerRejection(testCase)
      transport = MockAdsTransport();
      transport.autoControllerApplyAck = false;
      prefix = "Controller.";
      seed_status(transport, prefix, uint32(2));
      transport.scalarMap("Controller.Outputs.processedRevision") = uint32(3);
      transport.scalarMap("Controller.Outputs.parameterErrorCode") = uint32(16);

      testCase.verifyError(@() experiment.write_controller_params( ...
        transport, prefix, experiment.ControllerConfig.p_only(1)), ...
        "experiment:controller:parameterRejected");
      testCase.verifyEqual(transport.scalarMap("Controller.Outputs.appliedRevision"), uint32(2));
    end

    function recoversFromPreviousRejectedRevision(testCase)
      transport = MockAdsTransport();
      prefix = "Controller.";
      seed_status(transport, prefix, uint32(4));
      transport.scalarMap("Controller.Outputs.parameterErrorCode") = uint32(16);

      applied = experiment.write_controller_params( ...
        transport, prefix, experiment.ControllerConfig.p_only(2));

      testCase.verifyEqual(applied, uint32(5));
      testCase.verifyEqual( ...
        transport.scalarMap("Controller.Outputs.processedRevision"), uint32(5));
      testCase.verifyEqual( ...
        transport.scalarMap("Controller.Outputs.parameterErrorCode"), uint32(0));
    end

    function revisionWrapsWithoutSaturating(testCase)
      transport = MockAdsTransport();
      prefix = "Controller.";
      seed_status(transport, prefix, uint32(intmax("uint32")));

      applied = experiment.write_controller_params( ...
        transport, prefix, experiment.ControllerConfig.p_only(1));

      testCase.verifyEqual(applied, uint32(0));
    end
  end
end

function seed_status(transport, prefix, revision)
transport.scalarMap(char(prefix + "SosApplyRevision")) = uint32(revision);
transport.scalarMap(char(prefix + "Outputs.appliedRevision")) = uint32(revision);
transport.scalarMap(char(prefix + "Outputs.processedRevision")) = uint32(revision);
transport.scalarMap(char(prefix + "Outputs.parameterErrorCode")) = uint32(0);
end
