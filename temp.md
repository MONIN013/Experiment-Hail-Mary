```
Tend = 100; % simulation length
N = round(Tend/Ts);
t = Ts*(0:N-1);
Tcycle = 10; % cycle time of chirp signal
p = 0; % initial phase of chirp
f0 = 0.1; % min freq of chirp
f1 = 4000; % max freq of chirp
A = 1; % signal gain (preference: 0 < A < 1 for Pana motor, 0 < A < 2 for Beckhoff motor)
t_relative = t - floor(t/Tcycle)*Tcycle; % relative time inside chirp
k = (f1 - f0)/Tcycle; 
u = A*sin(p+(2*pi*(f0*t_relative + k/2 * t_relative.^2)));

trans = 2; % number of transient periods
Nstart = trans*Tcycle/Ts+1;
N = Tend/Ts; % total sample points of data + 1 (for velocity caluculation)
nrofs = Tcycle/Ts;
input = input(Nstart:N); % control input of plant
loadvel = diff([loadpos(Nstart:end),loadpos(end)])/Ts; % calculated velocity by backward difference [deg/s]
motorvel = diff([motorpos(Nstart:end),motorpos(end)])/Ts;

nrofp = length(input)/nrofs - trans; % number of period after transient removal


[txy, f] = tfestimate(input,loadvel,rectwin(Tcycle/Ts),0,Tcycle/Ts,1/Ts); % fft data of loadvel
Pd_vel_load = frd(txy, f, "FrequencyUnit", "Hz"); % frf data of input->vel
Pd_vel_load.Ts = Ts;
[txy, f] = tfestimate(input,motorvel,rectwin(Tcycle/Ts),0,Tcycle/Ts,1/Ts); % fft data of motorvel
Pd_vel_motor = frd(txy, f, "FrequencyUnit", "Hz"); % frf data of input->vel
Pd_vel_motor.Ts = Ts;[17:55]% check the coherence (good if close to 0dB)
figure;
mscohere(input,loadvel,rectwin(Tcycle/Ts),0,Tcycle/Ts,1/Ts); 
ax = gca; ax.XScale = 'log';
title("load-side coherence")

figure;
mscohere(input,motorvel,rectwin(Tcycle/Ts),0,Tcycle/Ts,1/Ts); hold off
ax = gca; ax.XScale = 'log';
title("motor-side coherence")[17:55]s = tf("s");
z = tf("z",Ts);

omega = 2.46e4;
Dn = 0.0005;
Jn = Dn/omega;
Ndelay = 3; % delay step of plant [int]

Pd_load = Pd_vel_load*c2d(1/s,Ts,"tustin"); % identified frequency response function of input -> pos (load)
Pd_motor = Pd_vel_motor*c2d(1/s,Ts,"tustin"); % identified frequency response function of input -> pos (motor)
Pdn = c2d(1/(Jn*s+Dn)/s,Ts,"zoh")/z^Ndelay; % discretized nominal plant of input -> pos

bop_ = bop;
bop_.YLim = {[-80,80];[-180,180]};
figure;
bode(Pd_load,Pd_motor,Pdn, bop_);
legend(["$P_{\mathrm{load}}$","$P_{\mathrm{motor}}$","$P_{n}$"],"Interpreter","latex");
```