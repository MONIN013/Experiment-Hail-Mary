function Kpi = designpi(d, k, Kt, w)
%designpi - design PI controller for second order system P
%
% Assuming P = Kt/(s^2 + d*s + k)
% Kpi = designpi(d, k, Kt, w)
%   w       : desired pole [rad/s]
%%%%%
validateattributes(d, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
validateattributes(k, {'numeric'}, {'scalar', 'finite'});
validateattributes(Kt, {'numeric'}, {'scalar', 'finite', 'nonzero'});
validateattributes(w, {'numeric'}, {'scalar', 'finite', 'positive'});

% A PI controller cannot independently move the plant's s^2 coefficient d.
% Match the remaining coefficients to s^3 + d*s^2 + 3*w^2*s + w^3.
Kp = (3*w^2 - k) / Kt;
Ki = w^3 / Kt;
% convert 2/2 order tf to pid type (optional)
Kpi = pid(Kp,Ki);
end
