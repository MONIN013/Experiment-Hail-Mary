function uff = srinv(P,ref,Npad)
%srinv - stable inversion with no transient response
%Perform a stable inversion of a non-minimum phase discrete time SISO
%state space model P, and filter a signal ref with the resulting
%non-causal filter Pinv = P^-1.
%
% uff = srinv_inv(P,ref)
% P       : discrete-time nominal plant (ss)
% ref     : signal to filter
% Npad    : additional padding before and after signal for transient removal (optional)
%
% Author  : Kentaro Tsurumoto, The University of Tokyo, 2023
narginchk(2,3);
if nargin < 3; Npad = 100; end
if isa(P,'tf')
    [Pnum,Pden] = tfdata(P,'v');
elseif isa(P,'ss')
    [Pnum,Pden] = ss2tf(P.A,P.B,P.C,P.D);
else
    error('P is not a system');
end
Ts = P.Ts;
%% Check properness of P and add delays if necessary
phd = order(tf(1,Pden,Ts)) - order(tf(1,Pnum,Ts)); % relative degree of P
z = tf("z",Ts);

if phd ~= 0
    P_tf = z^phd * tf(Pnum,Pden,Ts); % proper transfer function of P
else
    P_tf = tf(Pnum,Pden,Ts);
end
%% Invert P to determine Pinv
[PA, PB, PC, PD] = tf2ss(P_tf.num{:},P_tf.den{:});

PinvA = PA - PB/PD*PC;
PinvB = PB/PD;
PinvC = -PD\PC;
PinvD = inv(PD);

Pinv = ss(PinvA,PinvB,PinvC,PinvD,Ts);
[PinvS,PinvNS] = stabsep(Pinv,'Offset',-1e-5); % stable/unstable decomposition of Pinv

ref = reshape(ref,[length(ref),1]);
ref = [repmat(ref(1,:),Npad,1); ref; repmat(ref(end,:),Npad,1)]; % add padding
ref = [ref(phd+1:end); ref(end)*ones(phd,1)]; % Phase compensation: shift signal ref back over phd samples
%% Solve stable part forward in time
PinvS = tf(PinvS); % stable part of Pinv
uff_S_tmp = filter(PinvS.num{:},PinvS.den{:},ref); % filtering with transient
ref_offset_f = ref - ref(1); % offset signal ref so ref_offset_f(1) = 0
uff_S = filter(PinvS.num{:},PinvS.den{:},ref_offset_f); % filtering with no transient
uff_S = uff_S + uff_S_tmp(end) - uff_S(end); % offset recovery
%% Solve filtering of e through unstable part of Pinv backward in time
[numNS,denNS] = tfdata(PinvNS,'v'); % unstable part of Pinv

PinvNC = tf(fliplr(numNS),fliplr(denNS),1,'Variable','z^-1');

uff_NS_tmp = flipud(filter(PinvNC.num{:},PinvNC.den{:},flipud(ref))); % backwards filtering with transient
ref_offset_b = ref - ref(end); % offset signal ref so ref_offset_b(end) = 0
uff_NS = flipud(filter(PinvNC.num{:},PinvNC.den{:},flipud(ref_offset_b))); % filtering with no transient
uff_NS = uff_NS + uff_NS_tmp(1) - uff_NS(1); % offset recovery
%% Combination of stable and unstable part and phase compensation
uff = uff_S + uff_NS;
uff = uff(1+Npad:end-Npad,:);
end
