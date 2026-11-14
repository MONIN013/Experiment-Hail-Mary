% Inputs (workspace): NAME, REF, FF, CTRL. Runs one trial on hardware, saves raw.
if ~exist('REPEAT','var'), REPEAT=1; end
cd('c:/Users/Nogiku/source/repos/ExperimentHailMary/ExperimentHailMary');
addpath('matlab','matlab/experiment');
HW='C:/Users/Nogiku/AppData/Local/Temp/claude/163a9fc9a304703e/67da9375-757e-4d7c-8f6c-2a0d19d37214/scratchpad/hw';
cfg = experiment.ExperimentConfig.defaults();
cfg = experiment.scenario.configure_run(cfg, REF(:), FF(:), zeros(numel(REF),1), CTRL, "repeat_count", REPEAT);
P="DriverAdapter_Obj1 (Module1).";
tr = twincat_ads.AdsTransport(); tr.connect('192.168.10.3.1.1', 351);
assert(~tr.read_scalar(P+"Outputs.safetyTrip","System.Boolean"), 'trip latched before run');
pf={"MotorParams.encoderResolution",1048576,"System.UInt32";"LoadParams.encoderResolution",1048576,"System.UInt32";
 "MotorParams.ratedCurrentA",2.71,"System.Double";"LoadParams.ratedCurrentA",1.0,"System.Double";
 "MotorParams.positionSign",1,"System.Int32";"MotorParams.velocitySign",1,"System.Int32";
 "LoadParams.positionSign",-1,"System.Int32";"LoadParams.velocitySign",-1,"System.Int32"};
for k=1:size(pf,1), v=double(tr.read_scalar(P+pf{k,1},pf{k,3})); assert(v==pf{k,2}, 'preflight %s=%g', pf{k,1}, v); end
for n=["maxPositionRad","maxVelocityRadS","maxTwistRad"], v=tr.read_scalar(P+"SafetyLimits."+n,"System.Double"); assert(v>0, 'preflight limit %s=0', n); end
imax=tr.read_scalar(P+"MotorParams.maxCurrentA","System.Double"); assert(imax>0 && imax<=1.0, 'preflight maxCurrentA=%g', imax);
err = '';
try
  col = experiment.exp0n.run_and_collect(cfg);
catch e
  err = e.message; col = [];
end
trip = tr.read_scalar(P+"Outputs.safetyTrip","System.Boolean"); code = tr.read_scalar(P+"Outputs.safetyCode","System.UInt32");
c = twincat_ads.AdsTransport(); c.connect('192.168.10.3.1.1', 852);
fprintf('after: trip=%d code=%d modeFlags=%d modeState=%d active=%d err=%s\n', trip, code, c.read_scalar("GVL_MODE.modeFlags","System.UInt16"), c.read_scalar("GVL_MODE.modeState","System.Int16"), c.read_scalar("GVL_MODE.experimentActive","System.Boolean"), err);
if ~isempty(col)
  raw = col.logger_bin.raw; fprintf('fields: %s\n', strjoin(string(fieldnames(raw))', ' '));
  host = col.run.host; fprintf('done=%d timeout=%d stop=%s records=%d\n', host.done, host.timed_out, string(host.stop_reason), col.logger_bin.record_count);
  save(fullfile(HW, NAME + ".mat"), 'raw', 'REF', 'FF', 'trip', 'code');
end
