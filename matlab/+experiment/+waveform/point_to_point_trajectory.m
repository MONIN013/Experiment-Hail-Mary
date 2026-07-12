function traj = point_to_point_trajectory(varargin)
% point_to_point_trajectory  Snap-limited point-to-point position trajectory.
%
% The profile uses a seventh-order smoothstep segment.  Segment duration is
% checked against the requested velocity, acceleration, jerk, and snap limits.

p = inputParser;
p.addParameter("Ts", 1.25e-4, @is_positive_scalar);
p.addParameter("target_position_rad", deg2rad(720), @is_finite_scalar);
p.addParameter("vmax", deg2rad(9e3), @is_positive_scalar);
p.addParameter("amax", deg2rad(3e5), @is_positive_scalar);
p.addParameter("jmax", deg2rad(1e8), @is_positive_scalar);
p.addParameter("smax", deg2rad(1e10), @is_positive_scalar);
p.addParameter("motion_start_s", 0.25, @is_nonnegative_scalar);
p.addParameter("dwell_s", 0.15, @is_nonnegative_scalar);
p.addParameter("back_and_forth", true, @is_logical_scalar);
p.addParameter("total_time_s", 1.0, @is_positive_scalar);
p.parse(varargin{:});
args = p.Results;

Ts = double(args.Ts);
target = double(args.target_position_rad);
motion_start_s = double(args.motion_start_s);
dwell_s = double(args.dwell_s);
total_time_s = double(args.total_time_s);
back_and_forth = logical(args.back_and_forth);

sample_count = round(total_time_s / Ts);
if sample_count < 2
  error("experiment:waveform:invalidTrajectory", ...
    "total_time_s/Ts must produce at least two samples.");
end

t = Ts * (0:sample_count - 1)';
profile_end_s = t(end);
segment_count = 1 + double(back_and_forth);
available_motion_s = profile_end_s - motion_start_s - dwell_s;
if available_motion_s <= 0
  error("experiment:waveform:invalidTrajectory", ...
    "motion_start_s and dwell_s leave no time for motion.");
end
segment_duration_s = available_motion_s / segment_count;

minimum_duration_s = required_segment_duration( ...
  abs(target), double(args.vmax), double(args.amax), double(args.jmax), double(args.smax));
if segment_duration_s < minimum_duration_s
  error("experiment:waveform:invalidTrajectory", ...
    "Requested limits require segment duration %.6g s, but only %.6g s is available.", ...
    minimum_duration_s, segment_duration_s);
end

p_profile = zeros(sample_count, 1);
v_profile = zeros(sample_count, 1);
a_profile = zeros(sample_count, 1);

if target ~= 0
  forward_start_s = motion_start_s;
  forward_end_s = forward_start_s + segment_duration_s;
  return_start_s = forward_end_s + dwell_s;

  forward_idx = (t >= forward_start_s) & (t <= forward_end_s);
  u = clamp01((t(forward_idx) - forward_start_s) / segment_duration_s);
  [shape, dshape, ddshape] = smoothstep7(u);
  p_profile(forward_idx) = target * shape;
  v_profile(forward_idx) = target * dshape / segment_duration_s;
  a_profile(forward_idx) = target * ddshape / (segment_duration_s ^ 2);

  if back_and_forth
    dwell_idx = (t > forward_end_s) & (t < return_start_s);
    p_profile(dwell_idx) = target;

    return_idx = (t >= return_start_s) & (t <= profile_end_s);
    u = clamp01((t(return_idx) - return_start_s) / segment_duration_s);
    [shape, dshape, ddshape] = smoothstep7(u);
    p_profile(return_idx) = target * (1 - shape);
    v_profile(return_idx) = -target * dshape / segment_duration_s;
    a_profile(return_idx) = -target * ddshape / (segment_duration_s ^ 2);
  else
    hold_idx = t > forward_end_s;
    p_profile(hold_idx) = target;
  end
end

traj = struct( ...
  "t", t, ...
  "p", p_profile(:), ...
  "v", v_profile(:), ...
  "a", a_profile(:));
end

function tf = is_finite_scalar(x)
tf = isnumeric(x) && isscalar(x) && isfinite(x);
end

function tf = is_positive_scalar(x)
tf = is_finite_scalar(x) && x > 0;
end

function tf = is_nonnegative_scalar(x)
tf = is_finite_scalar(x) && x >= 0;
end

function tf = is_logical_scalar(x)
tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function x = clamp01(x)
x = min(1, max(0, double(x)));
end

function [y, dy, ddy] = smoothstep7(u)
u = double(u);
u2 = u .* u;
u3 = u2 .* u;
u4 = u2 .* u2;
u5 = u4 .* u;
u6 = u3 .* u3;
u7 = u6 .* u;
y = 35*u4 - 84*u5 + 70*u6 - 20*u7;
dy = 140*u3 - 420*u4 + 420*u5 - 140*u6;
ddy = 420*u2 - 1680*u3 + 2100*u4 - 840*u5;
end

function duration_s = required_segment_duration(distance, vmax, amax, jmax, smax)
if distance == 0
  duration_s = 0;
  return;
end
bounds = smoothstep7_bounds();
duration_s = max([ ...
  distance * bounds.v / vmax, ...
  sqrt(distance * bounds.a / amax), ...
  (distance * bounds.j / jmax)^(1/3), ...
  (distance * bounds.s / smax)^(1/4)]);
end

function bounds = smoothstep7_bounds()
persistent cached
if isempty(cached)
  u = linspace(0, 1, 20001)';
  u2 = u .* u;
  u3 = u2 .* u;
  u4 = u2 .* u2;
  d1 = 140*u3 - 420*u4 + 420*u4.*u - 140*u3.*u3;
  d2 = 420*u2 - 1680*u3 + 2100*u4 - 840*u4.*u;
  d3 = 840*u - 5040*u2 + 8400*u3 - 4200*u4;
  d4 = 840 - 10080*u + 25200*u2 - 16800*u3;
  cached = struct( ...
    "v", max(abs(d1)), ...
    "a", max(abs(d2)), ...
    "j", max(abs(d3)), ...
    "s", max(abs(d4)));
end
bounds = cached;
end
