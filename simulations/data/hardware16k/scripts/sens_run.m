% workspace: MODE, DESIGNF, NAME. Closed-loop sensitivity on a constant-velocity ramp.
cd('c:/Users/Nogiku/source/repos/ExperimentHailMary/ExperimentHailMary'); addpath('matlab','matlab/experiment');
pv = exp05_Higs("preview","design_path",DESIGNF,"plot",false); CTRL = experiment.ControllerConfig.from_struct(pv.(MODE));
Ts=6.25e-5; P=16000; nper=6; N=P*nper; t=(0:N-1)'*Ts; v=2; ta=0.5;
REF = v*(t - ta/pi*sin(pi*min(t,ta)/ta)).*(t>=ta) + v*(t.^2/(2*ta) - ta/pi^2*(1-cos(pi*t/ta)))*0; % placeholder
REF = cumsum(v*min(1,t/ta))*Ts;                                     % ramp to 2 rad/s over 0.5 s
rng(3); k=(5:2:1000)'; U=zeros(P,1); U(k+1)=exp(1j*2*pi*rand(numel(k),1)); u=real(ifft(U))*P; u=0.05*u/max(abs(u));
DISTV = repmat(u,nper,1); vr=gradient(REF)/Ts; FF = 0.10*tanh(vr/0.05); REPEAT=1;
save(fullfile('c:/Users/Nogiku/source/repos/ExperimentHailMary/ExperimentHailMary/simulations/data/hardware16k/runs',NAME+"_dist.mat"),'k','u','P');
run('c:/Users/Nogiku/source/repos/ExperimentHailMary/ExperimentHailMary/simulations/data/hardware16k/runs_run.m');
