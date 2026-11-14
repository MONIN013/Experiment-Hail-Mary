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
        a.linear.i_pre_section_count,a.linear.i_post_section_count,a.linear.post_section_count],[0,1,1,0,1,0]);
      testCase.verifyEqual(size(a.linear.sos,1),5);
      testCase.verifyFalse(a.io_backend_verified);testCase.verifyEqual(a.target_label,"");
    end
    function linearModeMatchesDirectTustinComparator(testCase)
      % Packed LP/P/I bank with both H rows must equal kp*lead*(s+wi)/s*LPF discretized directly.
      path=write_design();clean=onCleanup(@()delete(path));
      a=exp05_Higs("preview","design_path",path,"plot",false);
      K=experiment.ControllerConfig.from_struct(a.linear).linear_system();
      Ts=1/16000;wi=2*pi*2;wz=2*pi*2.6666666667;wp=2*pi*24;wl=2*pi*100;
      C=.1*tf([1/wz,1],[1/wp,1])*tf([1,wi],[1,0])*tf(wl^2,[1,sqrt(2)*wl,wl^2]);
      Cd=c2d(zpk(C),Ts,"tustin");
      w=2*pi*logspace(1,log10(2000),200);
      testCase.verifyEqual(squeeze(freqresp(K,w)),squeeze(freqresp(Cd,w)),"RelTol",1e-9);
    end
    function notchAndWeightingFilterLeaveTheLinearCounterpartUnchanged(testCase)
      % Notch in Post, W_i in iPre and W_i^-1 in iPost: linear C* = Cn*kp*lead*(1+wi/s)*LPF, W_i cancels.
      extra=struct("notch_zero_hz",300,"notch_pole_hz",330,"notch_zero_beta",.02,"notch_pole_beta",.3, ...
        "wi_zero_hz",2000,"wi_pole_hz",104,"wi_zero_beta",1,"wi_pole_beta",1);
      path=write_design(extra);clean=onCleanup(@()delete(path));
      a=exp05_Higs("preview","design_path",path,"plot",false);
      testCase.verifyEqual([a.both.lp_pre_section_count,a.both.lp_post_section_count,a.both.p_section_count, ...
        a.both.i_pre_section_count,a.both.i_post_section_count,a.both.post_section_count],[0,1,1,1,2,1]);
      testCase.verifyEqual(size(a.both.sos,1),8);
      Ts=1/16000;wi=2*pi*2;wz=2*pi*2.6666666667;wp=2*pi*24;wl=2*pi*100;wnz=2*pi*300;wnp=2*pi*330;
      C=.1*tf([1/wz,1],[1/wp,1])*tf([1,wi],[1,0])*tf(wl^2,[1,sqrt(2)*wl,wl^2]) ...
        *tf([1,2*.02*wnz,wnz^2],[1,2*.3*wnp,wnp^2]);
      Cd=c2d(zpk(C),Ts,"tustin");
      w=2*pi*logspace(1,log10(2000),200);
      Kb=experiment.ControllerConfig.from_struct(a.both).linear_system();
      testCase.verifyEqual(squeeze(freqresp(Kb,w)),squeeze(freqresp(Cd,w)),"RelTol",1e-7);
      path2=write_design(struct("notch_zero_hz",300,"notch_pole_hz",330,"notch_zero_beta",.02,"notch_pole_beta",.3));
      clean2=onCleanup(@()delete(path2));
      plain=exp05_Higs("preview","design_path",path2,"plot",false);
      Kp=experiment.ControllerConfig.from_struct(plain.both).linear_system();
      testCase.verifyEqual(squeeze(freqresp(Kb,w)),squeeze(freqresp(Kp,w)),"RelTol",1e-7);
      testCase.verifyEqual([plain.both.i_pre_section_count,plain.both.i_post_section_count,plain.both.post_section_count],[0,1,1]);
    end
    function incompleteFilterFieldsAreRejected(testCase)
      path=write_design(struct("notch_zero_hz",300));clean=onCleanup(@()delete(path));
      testCase.verifyError(@()exp05_Higs("preview","design_path",path,"plot",false),"experiment:higs:invalidDesign");
      path2=write_design(struct("wi_zero_hz",2000,"wi_pole_hz",104,"wi_zero_beta",1,"wi_pole_beta",-1));clean2=onCleanup(@()delete(path2));
      testCase.verifyError(@()exp05_Higs("preview","design_path",path2,"plot",false),"experiment:higs:invalidDesign");
    end
    function labelDoesNotSelectConnection(testCase)
      path=write_design();clean=onCleanup(@()delete(path));
      a=exp05_Higs("preview","design_path",path,"plot",false,"target_label","bench-A");
      b=exp05_Higs("preview","design_path",path,"plot",false,"target_label","bench-B");
      testCase.verifyEqual(a.connection_environment,b.connection_environment);
      testCase.verifyEqual(a.target_label,"bench-A");testCase.verifyEqual(b.target_label,"bench-B");
      testCase.verifyFalse(a.io_backend_verified);testCase.verifyFalse(b.io_backend_verified);
    end
    function linearGateExcludesOnlyDc(testCase)
      [plant,controller]=example_plant();response=plant.Pd.ResponseData;response(1,1,1)=Inf;
      plant.Pd=frd(response,plant.Pd.Frequency,plant.Ts,"FrequencyUnit","Hz");
      check=experiment.higs_linear_check(plant,controller,2,false);
      testCase.verifyTrue(check.dc_excluded);testCase.verifyEqual(check.frequency_band_hz,[1,1000]);
      response(1,1,3)=NaN;plant.Pd=frd(response,plant.Pd.Frequency,plant.Ts,"FrequencyUnit","Hz");
      testCase.verifyError(@()experiment.higs_linear_check(plant,controller,2,false),"experiment:higs:invalidPositiveFrf");
    end
    function linearGateRejectsMissingBandAndPeriodMismatch(testCase)
      [plant,controller]=example_plant();f=[1;10;100];
      plant.Pd=frd(squeeze(freqresp(plant.Pdn,2*pi*f)),f,plant.Ts,"FrequencyUnit","Hz");
      testCase.verifyError(@()experiment.higs_linear_check(plant,controller,2,false),"experiment:higs:insufficientFrequencyBand");
      [plant,controller]=example_plant();plant.Pdn.Ts=1/4000;
      testCase.verifyError(@()experiment.higs_linear_check(plant,controller,2,false),"experiment:higs:plantSampleTime");
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
function path=write_design(extra)
if nargin<1,extra=struct();end
d=struct("sample_time_s",1/16000,"reference_amplitude_rad",.1,"move_time_s",.1, ...
  "dwell_time_s",.2,"settle_time_s",.4,"sensitivity_limit",2,"max_current_a",.08, ...
  "max_position_rad",.25,"max_velocity_rad_s",10,"max_twist_rad",.01, ...
  "tuning",struct("kp",.1,"integral_hz",2,"lead_zero_hz",2.6666666667, ...
  "lead_pole_hz",24,"lowpass_hz",100,"higs_lp_corner_hz",100,"higs_i_corner_hz",2, ...
  "higs_lp_gain",1,"higs_i_gain",1));
for name=string(fieldnames(extra)).',d.tuning.(name)=extra.(name);end
path=string(tempname())+".json";fid=fopen(path,"w");clean=onCleanup(@()fclose(fid));fprintf(fid,"%s",jsonencode(d));
end
function [plant,controller]=example_plant()
Ts=1/16000;Pdn=c2d(tf(1,[.01,1]),Ts);f=[0;1;10;200;500;1000];
Pd=frd(squeeze(freqresp(Pdn,2*pi*f)),f,Ts,"FrequencyUnit","Hz");
plant=struct("Pd",Pd,"Pdn",Pdn,"Ts",Ts);
controller=experiment.ControllerConfig.from_sos([.1,0,0,1,0,0],Ts);
end
