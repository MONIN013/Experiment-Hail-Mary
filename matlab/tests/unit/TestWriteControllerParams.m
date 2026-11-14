classdef TestWriteControllerParams < matlab.unittest.TestCase
  methods (Test)
    function writesPackedPayloadAndAllCountsBeforeRevision(testCase)
      transport=MockAdsTransport();prefix="Controller.";seed_status(transport,prefix,uint32(7));
      cfg=experiment.ControllerConfig.from_sos([2,3,4,1,5,6;7,8,9,1,10,11],1/16000);
      applied=experiment.write_controller_params(transport,prefix,cfg);
      testCase.verifyEqual(applied,uint32(8));
      writes=transport.operations(startsWith(transport.operations,"write_"));
      testCase.verifyEqual(writes(1),"write_array:Controller.SosCoefficients");
      testCase.verifyEqual(writes(2),"write_scalar:Controller.SosSectionCount");
      testCase.verifyEqual(writes(3:8),["write_scalar:Controller.LpPreSectionCount"; ...
        "write_scalar:Controller.LpPostSectionCount";"write_scalar:Controller.PSectionCount"; ...
        "write_scalar:Controller.IPreSectionCount";"write_scalar:Controller.IPostSectionCount"; ...
        "write_scalar:Controller.PostSectionCount"]);
      testCase.verifyEqual(writes(9:14),["write_scalar:Controller.HigsLpEnabled"; ...
        "write_scalar:Controller.HigsLpGain";"write_scalar:Controller.HigsLpOmegaTs"; ...
        "write_scalar:Controller.HigsIEnabled";"write_scalar:Controller.HigsIGain"; ...
        "write_scalar:Controller.HigsIOmegaTs"]);
      testCase.verifyEqual(writes(15),"write_scalar:Controller.SosApplyRevision");
      testCase.verifyEqual(transport.scalarMap("Controller.SosSectionCount"),uint32(5));
      testCase.verifyEqual(transport.scalarMap("Controller.PSectionCount"),uint32(2));
      testCase.verifyEqual(transport.scalarMap("Controller.IPreSectionCount"),uint32(1));
      testCase.verifyEqual(transport.scalarMap("Controller.SosApplyRevision"),uint32(8));
      rows=reshape(transport.arrayMap("Controller.SosCoefficients"),5,[]).';
      testCase.verifyEqual(rows(1,:),[1,0,0,0,0]);
      testCase.verifyEqual(rows(2:3,:),[2,3,4,5,6;7,8,9,10,11]);
      testCase.verifyEqual(rows(4,:),[0,0,0,0,0]);
      testCase.verifyEqual(rows(5,:),[1,0,0,0,0]);
    end
    function higsParametersCommitTogetherAndFailedPayloadDoesNotCommit(testCase)
      transport=MockAdsTransport();seed_status(transport,"Controller.",uint32(1));
      cfg=experiment.ControllerConfig();cfg.higs_lp_enabled=true;cfg.higs_lp_omega_ts=.01;cfg.sample_time_s=1/16000;
      experiment.write_controller_params(transport,"Controller.",cfg);
      testCase.verifyTrue(transport.scalarMap("Controller.HigsLpEnabled"));
      testCase.verifyEqual(transport.scalarMap("Controller.HigsLpOmegaTs"),.01);
      transport.set_scalar_write_error("Controller.HigsLpGain","test:payloadFailed","injected HIGS write failure");
      testCase.verifyError(@()experiment.write_controller_params(transport,"Controller.",cfg),"test:payloadFailed");
      testCase.verifyEqual(transport.scalarMap("Controller.SosApplyRevision"),uint32(2));
    end
    function reportsControllerRejection(testCase)
      transport=MockAdsTransport();transport.autoControllerApplyAck=false;prefix="Controller.";
      seed_status(transport,prefix,uint32(2));
      transport.scalarMap("Controller.Outputs.processedRevision")=uint32(3);
      transport.scalarMap("Controller.Outputs.parameterErrorCode")=uint32(16);
      testCase.verifyError(@()experiment.write_controller_params(transport,prefix,experiment.ControllerConfig.p_only(1)), ...
        "experiment:controller:parameterRejected");
      testCase.verifyEqual(transport.scalarMap("Controller.Outputs.appliedRevision"),uint32(2));
    end
    function recoversFromPreviousRejectedRevision(testCase)
      transport=MockAdsTransport();prefix="Controller.";seed_status(transport,prefix,uint32(4));
      transport.scalarMap("Controller.Outputs.parameterErrorCode")=uint32(16);
      applied=experiment.write_controller_params(transport,prefix,experiment.ControllerConfig.p_only(2));
      testCase.verifyEqual(applied,uint32(5));
      testCase.verifyEqual(transport.scalarMap("Controller.Outputs.processedRevision"),uint32(5));
      testCase.verifyEqual(transport.scalarMap("Controller.Outputs.parameterErrorCode"),uint32(0));
    end
    function revisionWrapsWithoutSaturating(testCase)
      transport=MockAdsTransport();prefix="Controller.";seed_status(transport,prefix,uint32(intmax("uint32")));
      applied=experiment.write_controller_params(transport,prefix,experiment.ControllerConfig.p_only(1));
      testCase.verifyEqual(applied,uint32(0));
    end
  end
end
function seed_status(transport,prefix,revision)
transport.scalarMap(char(prefix+"SosApplyRevision"))=uint32(revision);
transport.scalarMap(char(prefix+"Outputs.appliedRevision"))=uint32(revision);
transport.scalarMap(char(prefix+"Outputs.processedRevision"))=uint32(revision);
transport.scalarMap(char(prefix+"Outputs.parameterErrorCode"))=uint32(0);
end
