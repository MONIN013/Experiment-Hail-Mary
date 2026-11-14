function res = higs_bench_run(ctrl, ref, ff, out_dir, name, opts)
% higs_bench_run  Run one trial on the bench with retries; save the raw logger struct to <out_dir>/<name>.mat.
%   res = higs_bench_run(ctrl, ref, ff, out_dir, name, disturbance=dist, repeat=1, attempts=3)
% ctrl: experiment.ControllerConfig; ref, ff, disturbance: one period of the tables at the task rate [rad, A, A].
% An attempt is repeated when it does not complete (done, no timeout, no abort). A safety trip stops everything and errors.
% Saved variables: raw (logger fields), REF, FF, trip, code.
arguments
  ctrl (1,1) experiment.ControllerConfig
  ref (:,1) double
  ff (:,1) double
  out_dir (1,1) string
  name (1,1) string
  opts.disturbance double = []
  opts.repeat (1,1) double = 1
  opts.attempts (1,1) double = 3
end

dist = opts.disturbance(:);
if isempty(dist), dist = zeros(size(ref)); end
cfg = experiment.scenario.configure_run(experiment.ExperimentConfig.defaults(), ref, ff, dist, ctrl, "repeat_count", opts.repeat);
if ~isfolder(out_dir), mkdir(out_dir); end
file = fullfile(out_dir, name + ".mat");
res = struct("name", name, "file", file, "completed", false, "attempts", 0, "trip", false, "code", uint32(0), ...
  "message", "", "raw", []);

for attempt = 1:opts.attempts
  res.attempts = attempt;
  higs_bench_limits("check");
  col = [];
  msg = "";
  try
    col = experiment.exp0n.run_and_collect(cfg);
  catch cause
    msg = string(cause.message);
  end
  st = read_state(cfg);
  fprintf("%s attempt %d: trip=%d code=%d modeFlags=%d modeState=%d active=%d %s\n", name, attempt, ...
    st.trip, st.code, st.modeFlags, st.modeState, st.active, msg);
  completed = false;
  if ~isempty(col)
    host = col.run.host;
    completed = host.done && ~host.timed_out && ~host.abort_requested;
    if ~completed
      msg = sprintf("done=%d timeout=%d abort=%d stop=%s", host.done, host.timed_out, host.abort_requested, string(host.stop_reason));
    end
  end
  if ~isempty(col) && (completed || st.trip)
    raw = col.logger_bin.raw;
    REF = ref; FF = ff; trip = st.trip; code = st.code;
    save(file, "raw", "REF", "FF", "trip", "code");
    res.raw = raw;
  end
  res.completed = completed;
  res.trip = st.trip;
  res.code = st.code;
  res.message = msg;
  if st.trip
    error("higs_bench:trip", "Safety trip (code %u) during %s; raw log saved if available. Inspect, then higs_bench_limits(""reset"").", st.code, name);
  end
  if completed, return; end
  fprintf("%s attempt %d did not complete: %s\n", name, attempt, msg);
end
end

function st = read_state(cfg)
types = twincat_ads.AdsTransport.net_types();
conn = experiment.ConnectionManager.create(cfg);
cleanup = onCleanup(@() conn.session.close());
prefix = "DriverAdapter_Obj1 (Module1).";
st = struct("trip", logical(conn.module.read_scalar(prefix + "Outputs.safetyTrip", types.bool)), ...
  "code", conn.module.read_scalar(prefix + "Outputs.safetyCode", types.u32), ...
  "modeFlags", conn.ctrl.read_scalar("GVL_MODE.modeFlags", types.u16), ...
  "modeState", conn.ctrl.read_scalar("GVL_MODE.modeState", types.i16), ...
  "active", logical(conn.ctrl.read_scalar("GVL_MODE.experimentActive", types.bool)));
end
