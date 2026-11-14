function out = higs_bench_limits(action, opts)
% higs_bench_limits  DriverAdapter scaling check, limit write and safety reset on the bench.
%   state = higs_bench_limits("check")   scaling/sign preflight; error if a trip is latched
%   higs_bench_limits("write", max_position_rad=40)   IDLE only; writes limits and reads them back
%   higs_bench_limits("reset")           SafetyResetRevision + 1 (only after the cause is understood)
% Connection from experiment.ExperimentConfig.defaults().env.
arguments
  action (1,1) string {mustBeMember(action, ["check", "write", "reset"])}
  opts.motor_max_current_a (1,1) double = 2.71
  opts.load_max_current_a (1,1) double = 1.0
  opts.max_position_rad (1,1) double = 40
  opts.max_velocity_rad_s (1,1) double = 107   % value in logger units (true speed = 3.906 x this)
  opts.max_twist_rad (1,1) double = 0.05
  opts.scaling (1,1) logical = false           % write encoder resolution and rated current too
end

cfg = experiment.ExperimentConfig.defaults();
types = twincat_ads.AdsTransport.net_types();
conn = experiment.ConnectionManager.create(cfg);
cleanup = onCleanup(@() conn.session.close());
prefix = "DriverAdapter_Obj1 (Module1).";
scaling = {"MotorParams.encoderResolution", uint32(1048576), types.u32; ...
           "LoadParams.encoderResolution", uint32(1048576), types.u32; ...
           "MotorParams.ratedCurrentA", 2.71, types.double; ...
           "LoadParams.ratedCurrentA", 1.0, types.double};
signs = {"MotorParams.positionSign", 1; "MotorParams.velocitySign", 1; ...
         "LoadParams.positionSign", -1; "LoadParams.velocitySign", -1};

switch action
  case "check"
    out = check(conn, prefix, types, scaling, signs);
  case "write"
    require_idle(conn, types);
    entries = {"MotorParams.maxCurrentA", opts.motor_max_current_a, types.double; ...
               "LoadParams.maxCurrentA", opts.load_max_current_a, types.double; ...
               "SafetyLimits.maxPositionRad", opts.max_position_rad, types.double; ...
               "SafetyLimits.maxVelocityRadS", opts.max_velocity_rad_s, types.double; ...
               "SafetyLimits.maxTwistRad", opts.max_twist_rad, types.double};
    if opts.scaling, entries = [scaling; entries]; end
    for k = 1:size(entries, 1)
      conn.module.write_scalar(prefix + entries{k, 1}, entries{k, 2}, entries{k, 3});
      back = conn.module.read_scalar(prefix + entries{k, 1}, entries{k, 3});
      fprintf("%s = %g (readback %g)\n", entries{k, 1}, double(entries{k, 2}), double(back));
      if double(back) ~= double(entries{k, 2})
        error("higs_bench:readback", "Readback of %s differs.", entries{k, 1});
      end
    end
    out = check(conn, prefix, types, scaling, signs);
  case "reset"
    rev = conn.module.read_scalar(prefix + "SafetyResetRevision", types.u32);
    conn.module.write_scalar(prefix + "SafetyResetRevision", uint32(rev + 1), types.u32);
    pause(0.5);
    out.trip = logical(conn.module.read_scalar(prefix + "Outputs.safetyTrip", types.bool));
    fprintf("reset revision %d -> %d, trip now %d\n", rev, rev + 1, out.trip);
end
end

function state = check(conn, prefix, types, scaling, signs)
state.trip = logical(conn.module.read_scalar(prefix + "Outputs.safetyTrip", types.bool));
state.code = conn.module.read_scalar(prefix + "Outputs.safetyCode", types.u32);
if state.trip
  error("higs_bench:tripLatched", "Safety trip latched (code %u); inspect it, then higs_bench_limits(""reset"").", state.code);
end
for k = 1:size(scaling, 1)
  v = double(conn.module.read_scalar(prefix + scaling{k, 1}, scaling{k, 3}));
  if v ~= double(scaling{k, 2}), error("higs_bench:preflight", "%s = %g, expected %g.", scaling{k, 1}, v, double(scaling{k, 2})); end
end
for k = 1:size(signs, 1)
  v = double(conn.module.read_scalar(prefix + signs{k, 1}, types.i32));
  if v ~= signs{k, 2}, error("higs_bench:preflight", "%s = %g, expected %g.", signs{k, 1}, v, signs{k, 2}); end
end
for name = ["maxPositionRad", "maxVelocityRadS", "maxTwistRad"]
  v = conn.module.read_scalar(prefix + "SafetyLimits." + name, types.double);
  if ~(v > 0), error("higs_bench:preflight", "SafetyLimits.%s = %g, must be > 0.", name, v); end
  state.(name) = v;
end
state.motorMaxCurrentA = conn.module.read_scalar(prefix + "MotorParams.maxCurrentA", types.double);
if ~(state.motorMaxCurrentA > 0 && state.motorMaxCurrentA <= 2.71)
  error("higs_bench:preflight", "MotorParams.maxCurrentA = %g, must be in (0, 2.71].", state.motorMaxCurrentA);
end
end

function require_idle(conn, types)
if conn.ctrl.read_scalar("GVL_MODE.modeFlags", types.u16) ~= 0 || ...
    conn.ctrl.read_scalar("GVL_MODE.modeState", types.i16) ~= 0 || ...
    logical(conn.ctrl.read_scalar("GVL_MODE.experimentActive", types.bool))
  error("higs_bench:notIdle", "Limits may be written only in IDLE.");
end
end
