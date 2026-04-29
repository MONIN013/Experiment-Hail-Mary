stack = dbstack("-completenames");
script_dir = fileparts(stack(1).file);
matlab_root = fileparts(script_dir);
restoredefaultpath;
addpath(matlab_root, fullfile(matlab_root, "experiment"), fullfile(script_dir, "fixtures"));

suite = testsuite(fullfile(matlab_root, "tests"), "IncludeSubfolders", true);
results = run(suite);
disp(table(results));

passed = nnz([results.Passed]);
failed = nnz([results.Failed]);
incomplete = nnz([results.Incomplete]);
fprintf("passed=%d failed=%d incomplete=%d total=%d\n", ...
  passed, failed, incomplete, numel(results));

assert(all([results.Passed]), "Some MATLAB tests failed.");
