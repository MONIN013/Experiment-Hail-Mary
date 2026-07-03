%[text] ## Demo3: Feedforward Control Experiment
%%
%[text] ### STEP 1: DESIGN FEEDBACK CONTROLLER
%[text] load settings for the experiment
clear; close all;
load("./../config/data/config_tunable.mat"); % assuming use of "twomass_exp_tunable_2019a.slx"
load("./../config/data/pana_param.mat"); % choose motor type (panasonic or beckhoff) %[control:dropdown:988d]{"position":[6,39]}
load("./../demo1_SI/data/plant.mat");
%[text] design FB controller
%[text] (hint: during tuning of FF input the designed FB controller in demo2 may not be optimal)
% load("./../demo2_FB/data/feedback_result.mat","Kd"); % uncomment to use FB controller designed at demo2
% Kd = ###; % digital feedback controller
%%
%[text] ### Check the stability and performance of FB Controller (Always check before experiment!!!)
%[text] use nyquist and sensitivity plot
%[text] (note: Pd is actual system, Pdn is modelled system)
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
%[text] ### STEP 2: FEEDFORWARD EXPERIMENT
%[text] set reference trajectory
load("./../config/data/trajectory.mat"); % load reference
r = ref1_struct.p; % back and forth reference
figure;
subplot(3,1,1);
plot(t,ref1_struct.p,'b');
xlabel("Time [s]"); ylabel("Position [deg]");
subplot(3,1,2);
plot(t,ref1_struct.v,'b');
xlabel("Time [s]"); ylabel("Velocity [deg/s]");
subplot(3,1,3);
plot(t,ref1_struct.a,'b');
xlabel("Time [s]"); ylabel("Acceleration [deg/s^2]");
%%
%[text] ### **Design Feedforward input**
Kfa = 0;    % Acceleration Gain %[control:editfield:1b77]{"position":[7,8]}
Kfv = 0;    % Velocity Gain %[control:editfield:7e00]{"position":[7,8]}
Kfc = 0;    % Coulomb's friction Gain %[control:editfield:2286]{"position":[7,8]}

f = Kfa*ref1_struct.a + Kfv*ref1_struct.v + Kfc*sign(ref1_struct.v); % feedforward signal
f = [f(1+Ndelay:end); repmat(f(end),[Ndelay,1])]; % delay compensation
%%
%[text] build simulink model "twomass\_exp\_**tunable**\_2019a.slx"
%[text] (unlike demo1 and demo2, changing the reference and feedforward signal **does not** require rebuild! however, be aware that using long signal length may crash matlab, e.g., N = 400,000)
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
save("data/feedforward_result.mat","t","r","y","e","u","f","Kd");
%%
%[text] ### STEP 3: Analyze the results of the experiment
%[text] download data
load('data/feedforward_result.mat');
%%
%[text] plot tracking result of feedforward control
figure;
subplot(3,1,1)
plot(t,r,t,y);
xlabel("Time [s]"); ylabel("Position [deg]");
grid on;

subplot(3,1,2)
plot(t,e);
xlabel("Time [s]"); ylabel("Tracking error [deg]");
grid on;

subplot(3,1,3)
plot(t,f); hold on; plot(t,u'-f); hold off;
xlabel("Time [s]"); ylabel("Input [A]");
legend("FF","FB");
grid on;
%%
%[text] display error norm
norm(e)
