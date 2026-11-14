classdef TestControllerConfig < matlab.unittest.TestCase
  methods (Test)
    function identityAndPOnlyUseFixedHSlots(testCase)
      cfg=experiment.ControllerConfig();payload=cfg.to_ads_payload();
      testCase.verifySize(cfg.sos,[4,6]);testCase.verifyEqual(payload.section_count,uint32(4));
      testCase.verifyEqual(payload.section_counts,uint32([0,0,1,1,0,0]));
      p=experiment.ControllerConfig.p_only(3.5);
      testCase.verifyEqual(p.sos(2,:),[3.5,0,0,1,0,0]);
      testCase.verifyEqual(p.sos(3,:),[0,0,0,1,0,0]);
      testCase.verifyEqual(p.to_ads_payload().section_count,uint32(4));
    end
    function fromSosMapsGenericCascadeToP(testCase)
      cfg=experiment.ControllerConfig.from_sos([2,4,6,2,8,10],1/16000);
      testCase.verifyError(@()experiment.ControllerConfig.from_struct(struct("sos",[2,4,6,2,8,10],"sample_time_s",1/16000)), ...
        "experiment:controller:invalid");
      testCase.verifyEqual(cfg.sos(2,:),[1,2,3,1,4,5]);
      testCase.verifyEqual(cfg.to_ads_payload().section_counts,uint32([0,0,1,1,0,0]));
      cfg.validate_for_task_rate(16000);
      restored=experiment.ControllerConfig.from_struct(cfg.to_struct());
      testCase.verifyEqual(restored.to_struct(),cfg.to_struct());
    end
    function packsSegmentsAndEnforcesTenRows(testCase)
      counts=struct("lp_pre_section_count",1,"lp_post_section_count",1,"p_section_count",2, ...
        "i_pre_section_count",0,"i_post_section_count",1,"post_section_count",1);
      s=ones(8,6);s(:,2:3)=0;s(:,5:6)=0;
      fields=counts;fields.sos=s;fields.sample_time_s=1/16000;
      fields.higs_lp_enabled=true;fields.higs_lp_gain=1;fields.higs_lp_omega_ts=.01;
      fields.higs_i_gain=1;fields.higs_i_omega_ts=.02;
      cfg=experiment.ControllerConfig.from_struct(fields);
      testCase.verifyEqual(cfg.to_ads_payload().section_count,uint32(8));
      fields.post_section_count=3;
      testCase.verifyError(@()experiment.ControllerConfig.from_struct(fields),"experiment:controller:invalid");
    end
    function enabledHigsRequiresPositiveCorner(testCase)
      cfg=experiment.ControllerConfig();cfg.higs_lp_enabled=true;
      testCase.verifyError(@()cfg.validate(),"experiment:controller:invalid");
      cfg=experiment.ControllerConfig();cfg.higs_i_enabled=true;
      testCase.verifyError(@()cfg.validate(),"experiment:controller:invalid");
    end
    function rejectsInvalidFieldsAndTiming(testCase)
      testCase.verifyError(@()experiment.ControllerConfig.from_struct(struct("sos",zeros(0,6),"higs_enabled",true)), ...
        "experiment:controller:invalid");
      testCase.verifyError(@()experiment.ControllerConfig.from_sos(ones(8,6),1/16000),"experiment:controller:tooManySections");
      cfg=experiment.ControllerConfig.from_sos([1,0.5,0,1,-0.25,0],1/16000);
      testCase.verifyError(@()cfg.validate_for_task_rate(4000),"experiment:controller:sampleTimeMismatch");
      testCase.verifyError(@()experiment.ControllerConfig.from_struct(struct("sos",[1,0,0,0,0,0])), ...
        "experiment:controller:invalid");
    end
  end
end
