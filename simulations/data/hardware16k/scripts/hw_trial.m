% workspace: DESIGN (path), MODE ("linear"|"both"|...), NAME
cd('c:/Users/Nogiku/source/repos/ExperimentHailMary/ExperimentHailMary'); addpath('matlab','matlab/experiment');
pv = exp05_Higs("preview","design_path",DESIGN,"plot",false);
try, plant = experiment.exp0n.load_plant_data('matlab/experiment/data/plant.mat'); lin = experiment.ControllerConfig.from_struct(pv.linear); experiment.higs_linear_check(plant, lin, pv.design.sensitivity_limit, false); fprintf('linear gate ok\n'); catch ge, fprintf('linear gate (info only): %s\n', ge.message); end
CTRL = experiment.ControllerConfig.from_struct(pv.(MODE)); REF = pv.reference(:); FF = zeros(size(REF)); REPEAT = 1;
if exist('FC','var'), Tsd=pv.design.sample_time_s; vr=gradient(REF)/Tsd; ar=gradient(vr)/Tsd; FF=FC*tanh(vr/0.05)+JFF*ar; fprintf('FF peak %.3f A\n',max(abs(FF))); end
run('c:/Users/Nogiku/source/repos/ExperimentHailMary/ExperimentHailMary/simulations/data/hardware16k/runs_run.m');
S=load(fullfile(HW,NAME+".mat")); r=structfun(@double,S.raw,'UniformOutput',false);
e=r.ref_value-r.load_position; Ts=pv.design.sample_time_s; n=numel(e); t=(0:n-1)'*Ts;
tw=r.motor_position-r.load_position; [b,a]=butter(4,[200 400]/(0.5/Ts)); twb=filtfilt(b,a,tw);
tail=t>=t(end)-0.2;
fprintf('RESULT %s mode=%s: errRMS %.4f mrad, errPeak %.3f mrad, tailRMS %.4f mrad, Icmd peak %.4f A, Iact peak %.4f, twist200-400 RMS %.3f urad, higsLp modes %s, higsI modes %s, logged-err-vs-mine %.2e\n', NAME, MODE, 1e3*rms(e),1e3*max(abs(e)),1e3*rms(e(tail)),max(abs(r.current_cmd)),max(abs(r.motor_current_act)),1e6*rms(twb),mat2str(unique(r.higs_lp_mode)'),mat2str(unique(r.higs_i_mode)'),max(abs(e-r.error)));
