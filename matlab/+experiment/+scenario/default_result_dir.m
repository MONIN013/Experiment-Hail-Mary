function value = default_result_dir()
% default_result_dir  Canonical ignored result directory for student runs.
scenario_dir = fileparts(mfilename("fullpath"));
experiment_package_dir = fileparts(scenario_dir);
matlab_root = fileparts(experiment_package_dir);
value = string(fullfile(matlab_root, "experiment", "data"));
end
