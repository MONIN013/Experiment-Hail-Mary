function pulse_reset(client, pulseSeconds, resetSymbol)
if nargin < 3 || strlength(string(resetSymbol)) == 0
    error("resetSymbol is required in the current architecture.");
end

adsutils.write_scalar(client, resetSymbol, true, "System.Boolean");
pause(pulseSeconds);
adsutils.write_scalar(client, resetSymbol, false, "System.Boolean");
end
