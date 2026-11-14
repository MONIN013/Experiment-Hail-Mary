function res = higs_bench_trial(design_path, mode, out_dir, name, opts)
% higs_bench_trial  One closed-loop trial of an exp05 design on the bench; prints error / current / twist figures.
%   res = higs_bench_trial("simulations/hardware/designs/hw_design_linear.json", "linear", out_dir, "a10m010_1_linear", ...
%           amplitude_rad=1, move_time_s=0.1, inertia=1.134e-4, coulomb_a=0.068, coulomb_slow_a=0.0625, viscous=3.45e-4, quadratic=5.41e-5)
% mode: linear | integrator | lowpass | both (selects the controller of the design file).
% amplitude_rad / move_time_s replace the design's trajectory; reference (column) replaces the trajectory altogether.
% Recommended identified coefficients are shown above (not defaults).
% Feedforward: inertia*a_ref + coulomb_a*tanh(v_ref/0.05) + coulomb_slow_a*tanh(v_ref/3)
%              + viscous*v_ref + quadratic*v_ref*abs(v_ref) (none when all coefficients are zero).
% Coefficient units: A/(rad/s^2), A, A, A/(rad/s), A/(rad/s)^2, respectively. Retries up to attempts times.
% max_position_rad / max_velocity_rad_s only relax the preview check of the trajectory; the active protection is
% the DriverAdapter limit set with higs_bench_limits.
% Needs addpath('matlab', 'matlab/experiment'). res: see higs_bench_run, plus metrics (higs_bench_metrics).
arguments
  design_path (1,1) string
  mode (1,1) string {mustBeMember(mode, ["linear", "integrator", "lowpass", "both"])}
  out_dir (1,1) string
  name (1,1) string
  opts.amplitude_rad double = []
  opts.move_time_s double = []
  opts.reference double = []
  opts.coulomb_a (1,1) double {mustBeNonnegative} = 0
  opts.coulomb_slow_a (1,1) double {mustBeNonnegative} = 0
  opts.viscous (1,1) double {mustBeNonnegative} = 0
  opts.quadratic (1,1) double {mustBeNonnegative} = 0
  opts.inertia (1,1) double = 0
  opts.disturbance double = []
  opts.repeat (1,1) double = 1
  opts.attempts (1,1) double = 3
  opts.max_position_rad (1,1) double = 40
  opts.max_velocity_rad_s (1,1) double = 1000
end

ts = 1 / double(experiment.ExperimentConfig.defaults().env.task_rate_hz);
design = jsondecode(fileread(design_path));
if abs(design.sample_time_s - ts) > 1e-12
  error("higs_bench:sampleTime", "Design sample time %g s differs from the task period %g s.", design.sample_time_s, ts);
end
if ~isempty(opts.amplitude_rad), design.reference_amplitude_rad = opts.amplitude_rad; end
if ~isempty(opts.move_time_s), design.move_time_s = opts.move_time_s; end
design.max_position_rad = opts.max_position_rad;
design.max_velocity_rad_s = opts.max_velocity_rad_s;
tmp = string(tempname) + ".json";
fid = fopen(tmp, "w");
fwrite(fid, jsonencode(design));
fclose(fid);
cleanup = onCleanup(@() delete(tmp));
pv = exp05_Higs("preview", "design_path", tmp, "plot", false);

ctrl = experiment.ControllerConfig.from_struct(pv.(mode));
ref = pv.reference(:);
if ~isempty(opts.reference), ref = opts.reference(:); end
ff = zeros(size(ref));
if any([opts.inertia, opts.coulomb_a, opts.coulomb_slow_a, opts.viscous, opts.quadratic] ~= 0)
  vr = gradient(ref) / ts;
  ar = gradient(vr) / ts;
  ff = opts.inertia * ar + opts.coulomb_a * tanh(vr / 0.05) ...
    + opts.coulomb_slow_a * tanh(vr / 3) + opts.viscous * vr + opts.quadratic * vr .* abs(vr);
  fprintf("FF peak %.3f A\n", max(abs(ff)));
end

res = higs_bench_run(ctrl, ref, ff, out_dir, name, disturbance=opts.disturbance, repeat=opts.repeat, attempts=opts.attempts);
if ~res.completed
  error("higs_bench:incomplete", "%s did not complete in %d attempts: %s", name, res.attempts, res.message);
end
res.metrics = higs_bench_metrics(res.raw, ts);
m = res.metrics;
fprintf("RESULT %s mode=%s: errRMS %.4f mrad, errPeak %.3f mrad, tailRMS %.4f mrad, Icmd peak %.4f A, Iact peak %.4f A, twist200-400 RMS %.3f urad, higsLp modes %s, higsI modes %s, logged-err-vs-mine %.2e\n", ...
  name, mode, 1e3 * m.error_rms_rad, 1e3 * m.error_peak_rad, 1e3 * m.tail_rms_rad, m.current_cmd_peak_a, m.current_act_peak_a, ...
  1e6 * m.twist_200_400hz_rms_rad, mat2str(m.higs_lp_modes), mat2str(m.higs_i_modes), m.logged_error_mismatch);
end
