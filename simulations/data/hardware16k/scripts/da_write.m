% Writes DriverAdapter scaling + limits. Requires IDLE (checked).
cd('c:/Users/Nogiku/source/repos/ExperimentHailMary/ExperimentHailMary');
addpath('matlab','matlab/experiment');
c = twincat_ads.AdsTransport(); c.connect('192.168.10.3.1.1', 852);
assert(c.read_scalar("GVL_MODE.modeFlags","System.UInt16")==0 && c.read_scalar("GVL_MODE.modeState","System.Int16")==0 && ~c.read_scalar("GVL_MODE.experimentActive","System.Boolean"), 'not idle');
tr = twincat_ads.AdsTransport(); tr.connect('192.168.10.3.1.1', 351);
P="DriverAdapter_Obj1 (Module1).";
if ~exist('LIM','var'), LIM=[3 20 0.05]; end
if ~exist('IMAX','var'), IMAX=0.3; end
w = {"MotorParams.encoderResolution",uint32(1048576),"System.UInt32"; "LoadParams.encoderResolution",uint32(1048576),"System.UInt32";
     "MotorParams.ratedCurrentA",2.71,"System.Double"; "LoadParams.ratedCurrentA",1.0,"System.Double";
     "MotorParams.maxCurrentA",IMAX,"System.Double"; "LoadParams.maxCurrentA",IMAX,"System.Double";
     "SafetyLimits.maxPositionRad",LIM(1),"System.Double"; "SafetyLimits.maxVelocityRadS",LIM(2),"System.Double"; "SafetyLimits.maxTwistRad",LIM(3),"System.Double"};
for k=1:size(w,1)
  tr.write_scalar(P+w{k,1}, w{k,2}, w{k,3});
  rb = tr.read_scalar(P+w{k,1}, w{k,3});
  fprintf('%s = %g (readback %g)\n', w{k,1}, double(w{k,2}), double(rb));
  assert(double(rb)==double(w{k,2}));
end
