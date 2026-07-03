%[text] ## Demo1: System Identification using chirp signal
%%
%[text] ### STEP 1: CHIRP EXCITATION
%[text] load settings for the experiment
clear; close all;
load("./../config/data/config.mat");
load("./../config/data/pana_param.mat"); % choose motor type (panasonic or beckhoff) %[control:dropdown:876a]{"position":[6,39]}

fb_flag = 0;
% Kd = tf(0); % open-loop system identification
% Ts = 1.25e-4; % sampling time (don't change)
%%
%[text] design excitation signal
Tend = 100; % simulation length
N = round(Tend/Ts);
t = Ts*(0:N-1);
Tcycle = 10; % cycle time of chirp signal
p = 0; % initial phase of chirp
f0 = 0.4; % min freq of chirp
f1 = 4000; % max freq of chirp
A = 1; % signal gain (preference: 0 < A < 1 for Pana motor, 0 < A < 2 for Beckhoff motor)
t_relative = t - floor(t/Tcycle)*Tcycle; % relative time inside chirp
k = (f1 - f0)/Tcycle;
% u = ###; % design linear chirp signal
%%
%[text] build simulink model "twomass\_exp\_2019a.slx" after executing this section
%[text] (build only needed 1 time.  rebuild required if you change the following parameters or the feedback controller Kd.)
set_ff = u;
set_ref = zeros(N,1);
%%
%[text] execute experiment via simulink
%[text] \*make sure to close all simulink files before executing this section
open(ModelName)
obtainMeasurement;
input = measurement(4,:); % control input [A]
loadpos = measurement(5,:); % loadside position [deg]
motorpos = measurement(6,:); % motorside position [deg]
%%
%[text] save experiment data
save("data/chirp_result.mat","input","*pos","Ts","Tend","Tcycle");
%%
%[text] ### STEP 2: TIME TREATMENT
%[text] download data
load('data/chirp_result.mat');
load("./../config/data/config.mat","bop");
%[text] remove transient periods
trans = 2; % number of transient periods
Nstart = trans*Tcycle/Ts+1;
N = Tend/Ts; % total sample points of data + 1 (for velocity caluculation)
nrofs = Tcycle/Ts;
input = input(Nstart:N); % control input of plant
loadvel = diff([loadpos(Nstart:end),loadpos(end)])/Ts; % calculated velocity by backward difference [deg/s]
motorvel = diff([motorpos(Nstart:end),motorpos(end)])/Ts;

nrofp = length(input)/nrofs - trans; % number of period after transient removal
%%
%[text] ### STEP 3: NON-PARAMETRIC ESTIMATION
%[text] fft data and vizualize in freq domain position data
[txy, f] = tfestimate(input,loadvel,rectwin(Tcycle/Ts),0,Tcycle/Ts,1/Ts); % fft data of loadvel
Pd_vel_load = frd(txy, f, "FrequencyUnit", "Hz"); % frf data of input->vel
Pd_vel_load.Ts = Ts;
[txy, f] = tfestimate(input,motorvel,rectwin(Tcycle/Ts),0,Tcycle/Ts,1/Ts); % fft data of motorvel
Pd_vel_motor = frd(txy, f, "FrequencyUnit", "Hz"); % frf data of input->vel
Pd_vel_motor.Ts = Ts;
%%
%[text] check coherence (good if close to 0dB)
% check the coherence (good if close to 0dB)
figure;
mscohere(input,loadvel,rectwin(Tcycle/Ts),0,Tcycle/Ts,1/Ts);
ax = gca; ax.XScale = 'log';
title("load-side coherence")
figure;
mscohere(input,motorvel,rectwin(Tcycle/Ts),0,Tcycle/Ts,1/Ts); hold off
ax = gca; ax.XScale = 'log';
title("motor-side coherence")
%%
%[text] ### Manual data fitting of system $P${"editStyle":"visual"}
%[text] True system: $P=\\frac{1}{{\\textrm{Js}}^2 +\\textrm{Ds}}${"editStyle":"visual"}
%[text] Nominal system: $P\_n =\\frac{1}{{J\_n s}^2 +D\_n s}${"editStyle":"visual"}
%[text] design $J\_n${"editStyle":"visual"} and $D\_n${"editStyle":"visual"} so $P\_n${"editStyle":"visual"} becomes close to $P${"editStyle":"visual"}.
s = tf("s");
z = tf("z",Ts);

Jn = 0.000001; %[control:editfield:1326]{"position":[6,14]}
Dn = 0.00004; %[control:editfield:7eac]{"position":[6,13]}
Ndelay = 2; % delay step of plant [int] %[control:editfield:669b]{"position":[10,11]}

Pd_load = Pd_vel_load*c2d(1/s,Ts,"tustin"); % identified frequency response function of input -> pos (load)
Pd_motor = Pd_vel_motor*c2d(1/s,Ts,"tustin"); % identified frequency response function of input -> pos (motor)
Pdn = c2d(1/(Jn*s+Dn)/s,Ts,"zoh")/z^Ndelay; % discretized nominal plant of input -> pos

bop_ = bop;
bop_.YLim = {[-80,80];[-180,180]};
figure;
bode(Pd_load,Pd_motor,Pdn,bop_);
legend(["$P_{\mathrm{load}}$","$P_{\mathrm{motor}}$","$P_{n}$"],"Interpreter","latex");
%%
%[text] save fitting data
%[text] load-side position will be the main objective of control for demo2 to demo4
Pd = Pd_load; % from demo2 to demo4 load-side pos will be control interest
save("data/plant.mat","Pd*","Jn","Dn","Ndelay","Ts");
