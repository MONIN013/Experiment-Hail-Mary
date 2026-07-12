function Kpd = designpd(d, k, Kt, w)
%designpd - design PD controller for second order system P
%
% Assuming P = Kt/(s^2 + d*s + k)
% Kpd = designpd(d, k, Kt, w)
%   w       : desired pole [rad/s]
%%%%%
s = tf('s');

Mpd = [1 0 0 0;
       d 1 0 0;
       k d Kt 0;
       0 k 0 Kt];
wpd = [1; 3*w; 3*w^2; w^3];
cpd = Mpd\wpd;
a0 = cpd(2);
b1 = cpd(3); b0 = cpd(4);
Kpd = (b1*s + b0)/(s + a0);
% convert 2/2 order tf to pid type (optional)
Kpd = pid(Kpd);
end
