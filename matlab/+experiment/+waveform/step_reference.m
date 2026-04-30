function ref_profile = step_reference(target_position_rad, pre_step_s, step_hold_s, sample_time_s)
% step_reference  Build a simple position step reference in rad.
validateattributes(target_position_rad, {'numeric'}, {'scalar', 'finite'});
validateattributes(pre_step_s, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
validateattributes(step_hold_s, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(sample_time_s, {'numeric'}, {'scalar', 'finite', 'positive'});

pre_step_n = max(1, round(double(pre_step_s) / double(sample_time_s)));
step_hold_n = max(1, round(double(step_hold_s) / double(sample_time_s)));
ref_profile = [
  zeros(pre_step_n, 1)
  double(target_position_rad) * ones(step_hold_n, 1)
];
end
