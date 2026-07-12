script_file = mfilename("fullpath");
results = run_test_suite(script_file);
disp(table(results));

passed = nnz([results.Passed]);
failed = nnz([results.Failed]);
incomplete = nnz([results.Incomplete]);
fprintf("passed=%d failed=%d incomplete=%d total=%d\n", ...
  passed, failed, incomplete, numel(results));

assert(all([results.Passed]), "Some MATLAB tests failed.");

function results = run_test_suite(script_file)
original_path = path;
path_cleanup = onCleanup(@() path(original_path)); %#ok<NASGU>

script_dir = fileparts(script_file);
matlab_root = fileparts(script_dir);
restoredefaultpath;
addpath(matlab_root, fullfile(matlab_root, "experiment"), fullfile(script_dir, "fixtures"));

suite = testsuite(fullfile(matlab_root, "tests"), "IncludeSubfolders", true);
results = run(suite);
end
