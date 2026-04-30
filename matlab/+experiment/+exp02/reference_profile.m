function ref_profile = reference_profile(trajectory_mat_path, trajectory_variable_name, target_position_rad, pre_step_s, step_hold_s, sample_time_s)
% reference_profile  Load a trajectory from MAT or build the default step.
if strlength(strtrim(string(trajectory_mat_path))) > 0
  ref_profile = experiment.io.load_reference_profile_from_mat(trajectory_mat_path, trajectory_variable_name);
else
  ref_profile = experiment.waveform.step_reference( ...
    target_position_rad, pre_step_s, step_hold_s, sample_time_s);
end
end
