function Kpid = designpid(d, k, Kt, w)
%designpid - design PID controller for second order system P
%
% Assuming P = Kt/(s^2 + d*s + k)
% Kpid = designpid(d, k, Kt, w)
%   w       : desired pole [rad/s]
%%%%%
s = tf("s");
Mpid = [1 0 0 0 0;
        d 1 0 0 0;
        k d Kt 0 0;
        0 k 0 Kt 0;
        0 0 0 0 Kt];
wpid = [1; 4*w; 6*w^2; 4*w^3; w^4];
cpid = Mpid\wpid;
a1 = cpid(2); b2 = cpid(3); b1 = cpid(4); b0 = cpid(5);
Kpid = (b2*s^2 + b1*s + b0)/(s^2 + a1*s);
% convert 2/2 order tf to pid type (optional)
Kpid = pid(Kpid);
end
