function y = filtfilt_clean(B,A,x,Npad)
%filtfilt_clean - filtfilt with no transient response
%
% y = filtfilt_clean(B,A,x,Npad)
% B       : numerator list of digital filter [z^n z^(n-1) ... 1]
% A       : denominator list of digital filter [z^n z^(n-1) ... 1]
% x       : signal to be filtered
% Npad    : additional padding before and after signal for transient removal (optional)
%
% Author  : Kentaro Tsurumoto, The University of Tokyo, 2023
narginchk(3,4);
if nargin < 4; Npad = 100; end
% signal padding
x_pad = [repmat(x(1,:),Npad,1); x; repmat(x(end,:),Npad,1)];
% forward filtering
y_tmp = filter(B,A,x_pad); % filtering with transient
x_offset = x_pad - x_pad(1); % offset signal so x_offset(1) = 0
y_pad = filter(B,A,x_offset); % filtering without transient
y_pad = y_pad + y_tmp(end) - y_pad(end); % offset recovery
% backward filtering
y_tmp = flipud(filter(B,A,flipud(y_pad))); % backward filtering with transient
y_offset = y_pad - y_pad(end); % offset signal so y_offset(end) = 0
y_pad = flipud(filter(B,A,flipud(y_offset))); % backward filtering without transient
y_pad = y_pad + y_tmp(1) - y_pad(1); % offset recovery
% remove padding
y = y_pad(1+Npad:end-Npad,:);
end
