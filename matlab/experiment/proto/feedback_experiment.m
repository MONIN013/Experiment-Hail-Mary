%[text] ## Demo2: Feedback Control Experiment
%[text] use PI/PD/PID Controller and compare the performance.
%[text] modify the P, I, D gain and (if you have time) add other filters for further analysis and performance enhancement.
%%
%[text] ### STEP 1: DESIGN FEEDBACK CONTROLLER
%[text] load settings for the experiment
clear; close all;
load("./../config/data/config.mat");
load("./../config/data/pana_param.mat"); % choose motor type (panasonic or beckhoff) %[control:dropdown:261a]{"position":[6,39]}
load('./../demo1_SI/data/plant.mat');
%[text] $K\\;＝\\;k\_p +\\frac{k\_i }{s}+k\_d \\frac{s}{1+T\_f s}${"editStyle":"visual"}
%[text] see what happens when $k\_p${"editStyle":"visual"}, $k\_i${"editStyle":"visual"}, $k\_d${"editStyle":"visual"} is changed.
omega = 20; % set by yourself [rad/s] (not [Hz])
% Kpi = designpi(Dn/Jn,0,1/Jn,omega) % uncomment to use PI controller
% Kpd = designpd(Dn/Jn,0,1/Jn,omega) % uncomment to use PD controller
Kpid = designpid(Dn/Jn,0,1/Jn,omega) % uncomment to use PID controller
% Kpid.Kp = 0 % set Kp to 0
% Kpid.Ki = 0 % set Ki to 0
% Kpid.Kd = 0 % set Kd to 0
%[text] ### (optional: Design other controllers)
%[text] (hint: change to I-PD, add leadlag filter, add notch filter)

%%
%[text] ### Check the stability and performance of FB Controller (Always check before experiment!!!)
%[text] use nyquist and sensitivity plot
%[text] (note: Pd is actual system, Pdn is modelled system)
Kd = c2d(Kpid,Ts,"tustin"); % digital feedback controller

% Maximum gain of sensitivity function
Smax = 2; % = 6dB

% Nyquist plot
figure;
nyquist(Pdn*Kd,Pd*Kd,nop); hold on;
theta = 0:0.01:2*pi;
plot(cos(theta)/Smax-1,sin(theta)/Smax,'k--'); hold off;
pbaspect([1 1 1]);
legend('nominal','frd');
title("Nyquist plot");
% Sensitivity plot
figure;
S = feedback(1,Pd*Kd);
Smax_frd = frd(Smax*ones(length(Pd.freq),1),Pd.freq,"FrequencyUnit","Hz");
bodemag(S,bop); hold on;
bodemag(Smax_frd,bop,'k--');
legend('frd');
title("Sensitivity function");
%%
%[text] ### STEP 2: FEEDBACK EXPERIMENT
%[text] set reference trajectory
load("./../config/data/trajectory.mat"); % load reference
r = ref1_struct.p; % back and forth reference
figure;
plot(t,r);
xlabel("Time [s]"); ylabel("Position [deg]");
%%
%[text] build simulink model "twomass\_exp\_2019a.slx" after executing this section
%[text] (build only needed 1 time. rebuild required if you change the following parameters or the feedback controller Kd.)
set_ff = zeros(N,1);
set_ref = r;

set_ref(:) = 0;
set_ff(0.2*N:end) = 1;
%%
%[text] execute experiment via simulink
%[text] \*make sure to close all simulink files before executing this section
open(ModelName)
obtainMeasurement;
y = measurement(5,:); % output position [deg]
e = measurement(3,:); % tracking error [deg]
u = measurement(4,:); % control input [A]
%%
%[text] save experiment data
save("data/feedback_result.mat","t","r","y","e","u","Kd");
%%
%[text] ### STEP 3: Analyze the results of the experiment
%[text] download data
load('data/feedback_result.mat');
load("./../config/data/config.mat","bop");
%%
%[text] plot tracking result of feedback control
figure;
subplot(3,1,1)
plot(t,r,t,y);
xlabel("Time [s]"); ylabel("Position [deg]");
grid on;

subplot(3,1,2)
plot(t,e);
xlabel("Time [s]"); ylabel("Tracking error [deg]")
grid on;

subplot(3,1,3)
plot(t,u);
xlabel("Time [s]"); ylabel("Input [A]");
grid on;
%%
%[text] display error norm
norm(e)
