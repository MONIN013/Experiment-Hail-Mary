%% exp01-exp04 preflight -- read-only checks before motor experiments
%
% This script verifies MATLAB path, required toolboxes, ADS connectivity,
% and the exp01 -> exp02/exp03/exp04 plant data handoff. It does not write ADS symbols
% and does not start an experiment.

use_virtual_motor = true; % false for the RealMotor project

tool_file = mfilename("fullpath");
matlab_root = fileparts(fileparts(tool_file));
addpath(matlab_root, fullfile(matlab_root, "experiment"));
preflight_matlab_root = matlab_root;
preflight_repo_root = fileparts(preflight_matlab_root);

fprintf("=== exp01-exp04 preflight ===\n");
fprintf("repoRoot=%s\n", preflight_repo_root);
fprintf("matlabRoot=%s\n", preflight_matlab_root);

required_functions = {
  "pid", "Control System Toolbox"
  "c2d", "Control System Toolbox"
  "tf", "Control System Toolbox"
  "ss", "Control System Toolbox"
  "feedback", "Control System Toolbox"
  "freqresp", "Control System Toolbox"
  "tfestimate", "Signal Processing Toolbox"
  "mscohere", "Signal Processing Toolbox"
};
for k = 1:size(required_functions, 1)
  assert_function_available(required_functions{k, 1}, required_functions{k, 2});
end
fprintf("Toolbox functions: OK\n");

env = config.EnvironmentConfig.current();
fprintf("amsNetId=%s ports(seq/control/module)=%d/%d/%d taskRate=%.0fHz\n", ...
  char(env.ams_net_id), env.seq_port, env.control_port, env.module_port, env.task_rate_hz);
fprintf("loggerHostFile=%s\n", char(env.logger_host_file_path));

run(fullfile(preflight_matlab_root, "tools", "run_verify_xar.m"));
if exist("n_fail", "var") && n_fail > 0
  error("experiment:preflight:xarFailed", ...
    "run_verify_xar.m reported %d failure(s). Fix ADS/runtime readiness before exp01-exp04.", n_fail);
end
if use_virtual_motor
  run(fullfile(preflight_matlab_root, "tools", "run_verify_virtual_motor.m"));
end

plant_mat_path = fullfile(preflight_matlab_root, "experiment", "data", "plant.mat");
if isfile(plant_mat_path)
  experiment.exp0n.load_plant_data( ...
    plant_mat_path, "expected_sample_time_s", 1 / env.task_rate_hz);
  fprintf("exp02/exp03/exp04 plant data: OK (%s)\n", plant_mat_path);
else
  warning("experiment:preflight:plantMatMissing", ...
    "plant.mat is missing. Run exp01_SysId.m before exp02_FeedBack.m, exp03_FeedForward.m, and exp04_ILC.m.");
end

trajectory = experiment.exp0n.load_trajectory( ...
  "expected_sample_time_s", 1 / env.task_rate_hz, ...
  "table_max_n", env.table_max_n);
fprintf("exp02-exp04 trajectory: OK (%d samples, %.6f s, position %.6g..%.6g deg)\n", ...
  trajectory.sample_count, trajectory.t(end), ...
  rad2deg(min(trajectory.p)), rad2deg(max(trajectory.p)));

fprintf("\nRun directory:\n  %s\n", preflight_repo_root);
fprintf("Commands:\n");
fprintf("  run('matlab/experiment/exp01_SysId.m')\n");
fprintf("  run('matlab/experiment/exp02_FeedBack.m')\n");
fprintf("  run('matlab/experiment/exp03_FeedForward.m')\n");
fprintf("  run('matlab/experiment/exp04_ILC.m')\n");
fprintf("Preflight complete.\n");

function assert_function_available(function_name, toolbox_name)
if exist(function_name, "file") ~= 2 && exist(function_name, "builtin") ~= 5
  error("experiment:preflight:missingToolboxFunction", ...
    "%s is required for exp01-exp04 (%s).", function_name, toolbox_name);
end
end
