classdef TestHigsExperiment < matlab.unittest.TestCase
  methods (Test)
    function previewBuildsFourModesAndUsesNoPlantOrAds(testCase)
      path=write_design();clean=onCleanup(@()delete(path));
      a=exp05_Higs("preview","design_path",path,"plot",false,"plant_path","missing-plant.mat");
      b=exp05_Higs("preview","design_path",path,"plot",false);
      testCase.verifyEqual(a.reference,b.reference);testCase.verifyEqual(a.reference(1),0,"AbsTol",1e-14);
      testCase.verifyEqual(a.reference(end),0,"AbsTol",1e-14);testCase.verifyEqual(max(a.reference),.1,"AbsTol",1e-14);
      testCase.verifyEqual(diff(a.t),repmat(1/16000,numel(a.t)-1,1),"AbsTol",1e-15);
      testCase.verifyFalse(a.linear.higs_lp_enabled);testCase.verifyFalse(a.linear.higs_i_enabled);
      testCase.verifyTrue(a.integrator.higs_i_enabled);testCase.verifyFalse(a.integrator.higs_lp_enabled);
      testCase.verifyTrue(a.lowpass.higs_lp_enabled);testCase.verifyFalse(a.lowpass.higs_i_enabled);
      testCase.verifyTrue(a.both.higs_lp_enabled);testCase.verifyTrue(a.both.higs_i_enabled);
      testCase.verifyFalse(isfield(a,"run"));testCase.verifyEqual([a.linear.lp_pre_section_count,a.linear.lp_post_section_count,a.linear.p_section_count, ...
        a.linear.i_pre_section_count,a.linear.i_post_section_count,a.linear.post_section_count],[0,1,1,1,2,0]);
      testCase.verifyEqual(size(a.linear.sos,1),7);testCase.verifyTrue(a.stability.passed);
      testCase.verifyFalse(a.io_backend_verified);testCase.verifyEqual(a.target_label,"");
    end
    function linearModeMatchesParallelBookComparator(testCase)
      % C* = k_p C_lp [PD + omega_i/s]; W_i and each H inverse cancel.
      path=write_design();clean=onCleanup(@()delete(path));
      a=exp05_Higs("preview","design_path",path,"plot",false);
      K=experiment.ControllerConfig.from_struct(a.linear).linear_system();
      Ts=1/16000;wi=2*pi*2;wd=2*pi*2.6666666667;wr=2*pi*4000;wl=2*pi*100;
      C=.1*tf(wl^2,[1,2*.33*wl,wl^2])*(tf([1/wd,1],[1/wr,1])+tf(wi,[1,0]));
      Cd=c2d(zpk(C),Ts,"tustin");
      w=2*pi*logspace(1,log10(2000),200);
      testCase.verifyEqual(squeeze(freqresp(K,w)),squeeze(freqresp(Cd,w)),"RelTol",1e-7);
    end
    function trueNotchesAndWeightingCancelInLinearCounterpart(testCase)
      ns=[struct("zero_hz",300,"pole_hz",300,"zero_beta",.02,"pole_beta",.3), ...
        struct("zero_hz",900,"pole_hz",900,"zero_beta",.15,"pole_beta",.45)];
      path=write_design(struct("notches",ns));clean=onCleanup(@()delete(path));
      a=exp05_Higs("preview","design_path",path,"plot",false);
      testCase.verifyEqual([a.both.lp_pre_section_count,a.both.lp_post_section_count,a.both.p_section_count, ...
        a.both.i_pre_section_count,a.both.i_post_section_count,a.both.post_section_count],[0,1,1,1,2,2]);
      testCase.verifyEqual(size(a.both.sos,1),9);
      Ts=1/16000;wi=2*pi*2;wd=2*pi*2.6666666667;wr=2*pi*4000;wl=2*pi*100;
      C=.1*tf(wl^2,[1,2*.33*wl,wl^2])*(tf([1/wd,1],[1/wr,1])+tf(wi,[1,0]));
      for n=ns
        wz=2*pi*n.zero_hz;wp=2*pi*n.pole_hz;
        C=C*tf([1,2*n.zero_beta*wz,wz^2],[1,2*n.pole_beta*wp,wp^2]);
      end
      Cd=c2d(zpk(C),Ts,"tustin");
      w=2*pi*logspace(1,log10(2000),200);
      Kb=experiment.ControllerConfig.from_struct(a.both).linear_system();
      testCase.verifyEqual(squeeze(freqresp(Kb,w)),squeeze(freqresp(Cd,w)),"RelTol",1e-6);
      path2=write_design(struct("notches",ns,"wi_zero_hz",1800,"wi_pole_hz",80));
      clean2=onCleanup(@()delete(path2));
      plain=exp05_Higs("preview","design_path",path2,"plot",false);
      Kp=experiment.ControllerConfig.from_struct(plain.both).linear_system();
      testCase.verifyEqual(squeeze(freqresp(Kb,w)),squeeze(freqresp(Kp,w)),"RelTol",1e-6);
    end
    function malformedFiltersAndVariableRollOffAreRejected(testCase)
      bad={struct("notches",struct("zero_hz",300)),struct("wi_pole_beta",-1), ...
        struct("wi_pole_hz",2100),struct("lead_pole_hz",3900),struct("lowpass_beta",0)};
      for k=1:numel(bad)
        path=write_design(bad{k});clean=onCleanup(@()delete(path));
        testCase.verifyError(@()exp05_Higs("preview","design_path",path,"plot",false),"experiment:higs:invalidDesign");
        clear clean;
      end
    end
    function labelDoesNotSelectConnection(testCase)
      path=write_design();clean=onCleanup(@()delete(path));
      a=exp05_Higs("preview","design_path",path,"plot",false,"target_label","bench-A");
      b=exp05_Higs("preview","design_path",path,"plot",false,"target_label","bench-B");
      testCase.verifyEqual(a.connection_environment,b.connection_environment);
      testCase.verifyEqual(a.target_label,"bench-A");testCase.verifyEqual(b.target_label,"bench-B");
      testCase.verifyFalse(a.io_backend_verified);testCase.verifyFalse(b.io_backend_verified);
    end
    function gainPrecedesSplitAndIntegratorHasNoPdFactor(testCase)
      path=write_design();clean=onCleanup(@()delete(path));
      path2=write_design(struct("kp",.7));clean2=onCleanup(@()delete(path2));
      a=exp05_Higs("preview","design_path",path,"plot",false);
      b=exp05_Higs("preview","design_path",path2,"plot",false);
      sa=experiment.ControllerConfig.from_struct(a.both).segments();
      sb=experiment.ControllerConfig.from_struct(b.both).segments();
      Ts=1/16000;w=2*pi*logspace(0,log10(3000),200);
      testCase.verifyEqual(sos_response(sb.lpPost,w,Ts),7*sos_response(sa.lpPost,w,Ts),"RelTol",1e-9);
      testCase.verifyEqual(sb.p,sa.p);testCase.verifyEqual(sb.iPre,sa.iPre);testCase.verifyEqual(sb.iPost,sa.iPost);
      wc=2*pi*2;wi=2*pi*2;wp=2*pi*104;wz=2*pi*2000;
      Wi=(wp^2/wz^2)*tf([1,2*wz,wz^2],[1,2*wp,wp^2]);
      Vi=(wi/wc)*tf([1,wc],[1,0])/Wi;expected=c2d(Vi,Ts,"tustin");
      testCase.verifyEqual(sos_response(sa.iPost,w,Ts),squeeze(freqresp(expected,w)),"RelTol",1e-8);
      testCase.verifyEqual(prod(sum(sa.iPre(:,1:3),2)./sum(sa.iPre(:,4:6),2)),1,"AbsTol",1e-10);
      testCase.verifyEqual(a.both.higs_lp_omega_ts,2*pi*100*Ts/sqrt(1+16/pi^2),"AbsTol",1e-15);
    end
    function gateUsesOwnHigsConstraintDespiteUnstableLinearCounterpart(testCase)
      % This record belongs to HIGS; its linear replacement is not its gate.
      path=write_design();clean=onCleanup(@()delete(path));
      a=exp05_Higs("preview","design_path",path,"plot",false,"plant_path","missing-plant.mat");
      K=experiment.ControllerConfig.from_struct(a.linear).linear_system();
      Ts=1/16000;Pdn=c2d(tf(-100,[1,0]),Ts);
      testCase.verifyFalse(isstable(feedback(K*Pdn,1)));
      testCase.verifyTrue(a.stability.passed);testCase.verifyEqual(a.stability.lambda,.4);
    end
    function gateRejectsFailedNormOrNyquistRecordBeforePlantAndAds(testCase)
      base=constraint_record("both");bad=base;bad.passed=false;
      over=base;over.per_frf.design.ws_norm=.9;over.per_frf.design.wa_sp_norm=.5;over.per_frf.design.sum=1.1;
      unstable=base;unstable.per_frf.design.stable=false;
      for record={bad,over,unstable}
        path=write_design(struct(),struct("constraint_record",record{1}));clean=onCleanup(@()delete(path));
        testCase.verifyError(@()exp05_Higs("both","design_path",path,"plot",false, ...
          "target_label","bench-A","plant_path","missing-plant.mat"),"experiment:higs:constraintFailed");
        clear clean;
      end
      inconsistent=base;inconsistent.per_frf.design.sum=.7;
      path=write_design(struct(),struct("constraint_record",inconsistent));clean=onCleanup(@()delete(path));
      testCase.verifyError(@()exp05_Higs("preview","design_path",path,"plot",false),"experiment:higs:invalidConstraint");
    end
    function informationalMs100DoesNotGateDesignPlant(testCase)
      record=constraint_record("both");record.informational_ms100=record.per_frf.design;
      record.informational_ms100.sum=1.5;record.informational_ms100.stable=false;
      path=write_design(struct(),struct("constraint_record",record));clean=onCleanup(@()delete(path));
      a=exp05_Higs("preview","design_path",path,"plot",false,"plant_path","missing-plant.mat");
      testCase.verifyTrue(a.stability.passed);testCase.verifyFalse(a.stability.informational_ms100.stable);
    end
    function linearRecordUsesZeroLambdaAndPreviewKeepsAllModes(testCase)
      path=write_design(struct(),struct("design_mode","linear","constraint_record",constraint_record("linear")));
      clean=onCleanup(@()delete(path));a=exp05_Higs("preview","design_path",path,"plot",false);
      testCase.verifyEqual(a.stability.lambda,0);testCase.verifyTrue(a.both.higs_i_enabled);
    end
    function generatedBookDesignsMatchLoadedPythonFilters(testCase)
      root=fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
      for name=["book_linear.json","book_both.json"]
        path=fullfile(root,"simulations","hardware","designs",name);
        d=jsondecode(fileread(path));a=exp05_Higs("preview","design_path",path,"plot",false);
        c=experiment.ControllerConfig.from_struct(a.(string(d.design_mode)));
        loaded=d.loaded_controller;counts=loaded.section_counts(:).';
        names=["lp_pre_section_count","lp_post_section_count","p_section_count", ...
          "i_pre_section_count","i_post_section_count","post_section_count"];
        expected=struct("sos",loaded.sos,"sample_time_s",d.sample_time_s, ...
          "higs_lp_gain",loaded.higs_lp_gain,"higs_i_gain",loaded.higs_i_gain, ...
          "higs_lp_omega_ts",loaded.higs_lp_omega_ts,"higs_i_omega_ts",loaded.higs_i_omega_ts, ...
          "higs_lp_enabled",loaded.higs_lp_enabled,"higs_i_enabled",loaded.higs_i_enabled);
        for k=1:numel(names)
          expected.(names(k))=counts(k);testCase.verifyEqual(c.(names(k)),counts(k));
        end
        python=experiment.ControllerConfig.from_struct(expected);
        cs=c.segments();ps=python.segments();w=2*pi*logspace(0,log10(7000),300);
        for field=string(fieldnames(cs)).'
          testCase.verifyEqual(sos_response(cs.(field),w,d.sample_time_s), ...
            sos_response(ps.(field),w,d.sample_time_s),"RelTol",2e-7);
        end
        testCase.verifyEqual(c.higs_lp_omega_ts,loaded.higs_lp_omega_ts,"AbsTol",1e-14);
        testCase.verifyEqual(c.higs_i_omega_ts,loaded.higs_i_omega_ts,"AbsTol",1e-14);
        testCase.verifyEqual(c.higs_lp_enabled,loaded.higs_lp_enabled);
        testCase.verifyEqual(c.higs_i_enabled,loaded.higs_i_enabled);
        testCase.verifyTrue(a.stability.passed);
      end
    end
    function repeatedLowFrequencyZerosAndUnitWeightPreserveResponse(testCase)
      Ts=1/16000;w=2*pi*logspace(0,log10(7000),300).';
      s=1i*(2/Ts)*tan(w*Ts/2);wi=2*pi*1.2;wc=2*pi*1.1306987749249564;
      for wz=2*pi*[512,4]
        wp=2*pi*4;
        path=write_design(struct("integral_hz",wi/(2*pi),"higs_i_corner_hz",wc/(2*pi), ...
          "wi_pole_hz",wp/(2*pi),"wi_zero_hz",wz/(2*pi)));
        clean=onCleanup(@()delete(path));
        a=exp05_Higs("preview","design_path",path,"plot",false);
        seg=experiment.ControllerConfig.from_struct(a.both).segments();
        weight=(wp/wz)^2*((s+wz)./(s+wp)).^2;
        expected=(wi/wc)*(s+wc)./s./weight;
        testCase.verifyEqual(sos_response(seg.iPost,w,Ts),expected,"RelTol",2e-9);
        if wz==wp
          testCase.verifyEqual(sos_response(seg.iPre,w,Ts),ones(size(w)),"AbsTol",1e-12);
        end
        clear clean;
      end
    end
    function finalBookDesignsSatisfyFixedBoundsOnDesignPlant(testCase)
      root=fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
      folder=fullfile(root,"simulations","hardware","designs");
      bundle=jsondecode(fileread(fullfile(folder,"book_design.json")));
      testCase.verifyEqual(sort(string(fieldnames(bundle.designs))),sort(["linear";"both"]));
      for mode=["linear","both"]
        d=bundle.designs.(mode);record=d.constraint_record;
        t=d.tuning;fb=d.omega_b_rad_s/(2*pi);tol=1e-8;
        testCase.verifyEqual(string(fieldnames(record.per_frf)),"design");
        testCase.verifyTrue(record.per_frf.design.stable);
        testCase.verifyLessThanOrEqual(record.per_frf.design.sum,1);
        testCase.verifyTrue(record.bounds.passed);
        testCase.verifyGreaterThan(t.kp,0);testCase.verifyEqual(t.lead_pole_hz,4000);
        ratios=[t.integral_hz/fb,t.lead_zero_hz/fb,t.lowpass_hz/fb,t.lowpass_beta, ...
          t.wi_pole_hz/t.integral_hz,t.wi_zero_hz/t.wi_pole_hz];
        testCase.verifyGreaterThanOrEqual(ratios,[1/3,.3,2,.1,1/3,1]-tol);
        testCase.verifyLessThanOrEqual(ratios,[1/2,1,4,1,3,10]+tol);
        testCase.verifyEqual([t.higs_lp_gain,t.higs_i_gain,t.wi_zero_beta,t.wi_pole_beta],[1,1,1,1]);
        testCase.verifyEqual(record.W_S,.5);testCase.verifyEqual(record.lambda,.4*(mode=="both"));
        testCase.verifyLessThanOrEqual(record.noise.command_ac_rms_a,.01);
        testCase.verifyTrue(record.notch_shape.passed);
        placements=record.notch_shape.placements;
        testCase.verifyEqual(numel(d.tuning.notches),numel(placements));
        for k=1:numel(d.tuning.notches)
          n=d.tuning.notches(k);placement=placements(k);
          testCase.verifyEqual(n.pole_hz,n.zero_hz);
          testCase.verifyGreaterThanOrEqual(n.zero_beta,.005-tol);
          testCase.verifyLessThanOrEqual(n.zero_beta,n.pole_beta/2+tol);
          testCase.verifyGreaterThanOrEqual(n.pole_beta,.2-tol);
          testCase.verifyLessThanOrEqual(n.pole_beta,1+tol);
          centreGain=n.zero_beta/n.pole_beta;
          testCase.verifyLessThanOrEqual(centreGain,10^(-6/20)+tol);
          testCase.verifyEqual(placement.gain_at_zero,centreGain,"AbsTol",tol);
          testCase.verifyEqual(placement.max_gain,1,"AbsTol",tol);
          testCase.verifyLessThanOrEqual(placement.max_gain_db,.1);
          wn=2*pi*n.zero_hz;s=2i*pi*placement.peak_hz;
          continuousGain=abs((s^2+2*n.zero_beta*wn*s+wn^2)/(s^2+2*n.pole_beta*wn*s+wn^2));
          s=1i*2/d.sample_time_s*tan(pi*placement.peak_hz*d.sample_time_s);
          loadedGain=abs((s^2+2*n.zero_beta*wn*s+wn^2)/(s^2+2*n.pole_beta*wn*s+wn^2));
          testCase.verifyEqual(placement.gain_at_peak,continuousGain,"AbsTol",tol);
          testCase.verifyEqual(placement.gain_at_peak_loaded,loadedGain,"AbsTol",tol);
          testCase.verifyLessThanOrEqual(max(continuousGain,loadedGain),10^(-6/20)+tol);
          testCase.verifyLessThanOrEqual(abs(n.zero_hz/placement.peak_hz-1),.05+tol);
          measured=d.resonance_detection.per_frf.(string(placement.measured_member)).peaks_hz;
          testCase.verifyLessThanOrEqual(min(abs(measured-placement.peak_hz)),1e-10);
        end
        box=record.higs_regime_box;
        testCase.verifyEqual(box.required,mode=="both");
        if mode=="both"
          testCase.verifyTrue(box.passed);
          c=d.loaded_controller;
          ratios=[c.higs_lp_omega_ts,c.higs_i_omega_ts]/d.sample_time_s/d.omega_b_rad_s;
          testCase.verifyGreaterThanOrEqual(ratios,[1,.3]-1e-10);
          testCase.verifyLessThanOrEqual(ratios,[2.5,.7]+1e-10);
        end
        rootRecord=d.linear_counterpart_poles_zeros;
        testCase.verifyTrue(isreal(rootRecord.real_poles_rad_s));testCase.verifyTrue(isreal(rootRecord.real_zeros_rad_s));
        testCase.verifyTrue(all(isfinite([rootRecord.real_poles_rad_s(:);rootRecord.real_zeros_rad_s(:)])));
        testCase.verifyTrue(d.controller_filter_poles_zeros.no_unintended_low_damping_poles);
        path=fullfile(folder,"book_"+mode+".json");
        testCase.verifyEqual(jsondecode(fileread(path)),d);
      end
    end
    function runRequiresExplicitTargetLabelAndPlant(testCase)
      path=write_design();clean=onCleanup(@()delete(path));
      testCase.verifyError(@()exp05_Higs("linear","design_path",path,"plot",false),"experiment:higs:targetLabelRequired");
      testCase.verifyError(@()exp05_Higs("linear","design_path",path,"plot",false, ...
        "target_label","bench-A","plant_path","missing-plant.mat"),"experiment:exp0n:plantRequired");
    end
    function oldHigsModeIsRejected(testCase)
      testCase.verifyError(@()exp05_Higs("higs","plot",false),"MATLAB:unrecognizedStringChoice");
    end
  end
end
function path=write_design(extra,overrides)
if nargin<1,extra=struct();end
if nargin<2,overrides=struct();end
d=struct("design_mode","both","constraint_record",constraint_record("both"), ...
  "sample_time_s",1/16000,"reference_amplitude_rad",.1,"move_time_s",.1, ...
  "dwell_time_s",.2,"settle_time_s",.4,"sensitivity_limit",2,"max_current_a",.08, ...
  "max_position_rad",.25,"max_velocity_rad_s",10,"max_twist_rad",.01, ...
  "tuning",struct("kp",.1,"integral_hz",2,"lead_zero_hz",2.6666666667, ...
  "lead_pole_hz",4000,"lowpass_hz",100,"lowpass_beta",.33,"higs_lp_corner_hz",100,"higs_i_corner_hz",2, ...
  "higs_lp_gain",1,"higs_i_gain",1,"wi_zero_hz",2000,"wi_pole_hz",104, ...
  "wi_zero_beta",1,"wi_pole_beta",1,"notches",[]));
for name=string(fieldnames(extra)).',d.tuning.(name)=extra.(name);end
for name=string(fieldnames(overrides)).',d.(name)=overrides.(name);end
path=string(tempname)+".json";fid=fopen(path,"w");clean=onCleanup(@()fclose(fid));fprintf(fid,"%s",jsonencode(d));
end
function out=constraint_record(mode)
lambda=0;if mode=="both",lambda=.4;end
member=struct("ws_norm",.6,"wa_sp_norm",.7,"sum",.6+lambda*.7,"stable",true,"bandwidth_hz",80);
out=struct("lambda",lambda,"W_S",.5,"passed",true, ...
  "per_frf",struct("design",member));
end
function response=sos_response(sos,w,Ts)
response=ones(numel(w),1);
for k=1:size(sos,1)
  section=tf(sos(k,1:3),sos(k,4:6),Ts,"Variable","z^-1");
  response=response.*squeeze(freqresp(section,w));
end
end
