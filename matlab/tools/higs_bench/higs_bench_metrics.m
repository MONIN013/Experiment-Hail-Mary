function m = higs_bench_metrics(raw, ts)
% higs_bench_metrics  Error, current and twist figures of one logged trial (raw logger struct, sample time ts [s]).
r = structfun(@double, raw, "UniformOutput", false);
e = r.ref_value - r.load_position;
t = (0:numel(e) - 1)' * ts;
twist = r.motor_position - r.load_position;
[b, a] = butter(4, [200 400] / (0.5 / ts));
twist_band = filtfilt(b, a, twist);
tail = t >= t(end) - 0.2;
m = struct("error_rms_rad", rms(e), "error_peak_rad", max(abs(e)), "tail_rms_rad", rms(e(tail)), ...
  "current_cmd_peak_a", max(abs(r.current_cmd)), "current_act_peak_a", max(abs(r.motor_current_act)), ...
  "twist_200_400hz_rms_rad", rms(twist_band), ...
  "higs_lp_modes", unique(r.higs_lp_mode)', "higs_i_modes", unique(r.higs_i_mode)', ...
  "logged_error_mismatch", max(abs(e - r.error)));
end
