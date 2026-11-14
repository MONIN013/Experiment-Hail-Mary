cd('c:/Users/Nogiku/source/repos/ExperimentHailMary/ExperimentHailMary'); addpath('matlab','matlab/experiment');
tr = twincat_ads.AdsTransport(); tr.connect('192.168.10.3.1.1', 351); P="DriverAdapter_Obj1 (Module1).";
r = tr.read_scalar(P+"SafetyResetRevision","System.UInt32"); tr.write_scalar(P+"SafetyResetRevision", uint32(r+1), "System.UInt32"); pause(0.5);
fprintf('reset rev %d -> %d, trip now %d\n', r, r+1, tr.read_scalar(P+"Outputs.safetyTrip","System.Boolean"));
