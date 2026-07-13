classdef TestExternalHeartbeat < matlab.unittest.TestCase
  methods (Test)
    function usesExplicitAssemblyAndCleansUpProcess(testCase)
      dll_path = [tempname, '.dll'];
      create_empty_file(dll_path);
      testCase.addTeardown(@() delete_if_exists(dll_path));
      counts = containers.Map({'wait', 'kill'}, {0, 0});
      hooks = struct( ...
        "start_process", @(~, ready_path, error_path) make_process( ...
          ready_path, error_path, counts, false, ""), ...
        "pause", @(~) [], ...
        "startup_timeout_s", 0.05);

      [cleanup, monitor] = experiment.start_external_heartbeat( ...
        config.EnvironmentConfig.defaults(), 0.03, dll_path, hooks);
      testCase.verifyClass(cleanup, "onCleanup");
      monitor();
      clear cleanup

      testCase.verifyEqual(counts("wait"), 1);
      testCase.verifyEqual(counts("kill"), 1);
    end

    function rejectsHelperThatExitsAfterReportingReady(testCase)
      dll_path = [tempname, '.dll'];
      create_empty_file(dll_path);
      testCase.addTeardown(@() delete_if_exists(dll_path));
      counts = containers.Map({'wait', 'kill'}, {0, 0});
      hooks = struct( ...
        "start_process", @(~, ready_path, error_path) make_process( ...
          ready_path, error_path, counts, true, "injected helper failure"), ...
        "pause", @(~) [], ...
        "startup_timeout_s", 0.05);

      testCase.verifyError(@() experiment.start_external_heartbeat( ...
        config.EnvironmentConfig.defaults(), 0.03, dll_path, hooks), ...
        "experiment:heartbeat:helperExited");
    end

    function rejectsMissingExplicitAssembly(testCase)
      missing_path = [tempname, '.dll'];
      testCase.verifyError(@() experiment.start_external_heartbeat( ...
        config.EnvironmentConfig.defaults(), 0.03, missing_path), ...
        "experiment:heartbeat:adsAssemblyMissing");
    end

    function helperStopsWhenOwningMatlabProcessExits(testCase)
      root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
      source = string(fileread(fullfile(root, "+experiment", ...
        "start_external_heartbeat.m")));
      testCase.verifyTrue(contains(source, 'feature("getpid")'));
      testCase.verifyTrue(contains(source, ...
        "[Diagnostics.Process]::GetProcessById("));
      testCase.verifyTrue(contains(source, "-not $owner.HasExited"));
      testCase.verifyTrue(contains(source, "$owner.Dispose()"));
    end
  end
end

function process = make_process(ready_path, error_path, counts, has_exited, detail)
create_text_file(ready_path, "ready");
if strlength(string(detail)) > 0
  create_text_file(error_path, detail);
end
process = struct( ...
  "HasExited", logical(has_exited), ...
  "WaitForExit", @(~) increment(counts, "wait"), ...
  "Kill", @() increment(counts, "kill"));
end

function new_count = increment(counts, key)
new_count = counts(key) + 1;
counts(key) = new_count; %#ok<NASGU> containers.Map mutation is the asserted side effect.
end

function create_empty_file(file_path)
create_text_file(file_path, "");
end

function create_text_file(file_path, value)
[fid, msg] = fopen(file_path, "w");
assert(fid >= 0, msg);
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, "%s", char(string(value)));
clear cleaner
end

function delete_if_exists(file_path)
if isfile(file_path)
  delete(file_path);
end
end
