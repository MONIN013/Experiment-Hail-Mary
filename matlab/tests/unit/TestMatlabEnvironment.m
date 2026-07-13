classdef TestMatlabEnvironment < matlab.unittest.TestCase
  methods (Test)
    function setupScriptDisablesPromptsOutsideDesktop(testCase)
      matlab_root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
      source = string(fileread(fullfile(matlab_root, "setup_matlab_environment.m")));

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '"Interactive", usejava("desktop")'));
    end

    function installWritesCacheAndStartupFile(testCase)
      matlab_root = create_fake_matlab_root();
      pref_dir = create_temp_folder();
      startup_dir = create_temp_folder();
      cleanup = onCleanup(@() cleanup_dirs({matlab_root, pref_dir, startup_dir}));

      out = config.MatlabEnvironment.install(matlab_root, ...
        "pref_dir", pref_dir, ...
        "startup_dir", startup_dir, ...
        "apply_now", false);
      cache = config.MatlabEnvironment.load_cache(char(out.cache_file));

      testCase.verifyTrue(isfile(char(out.cache_file)));
      testCase.verifyTrue(isfile(char(out.startup_file)));
      testCase.verifyEqual(char(out.cache_file), ...
        char(fullfile(pref_dir, "ExperimentHailMaryPathCache.mat")));
      testCase.verifyEqual(char(out.startup_file), char(fullfile(startup_dir, "startup.m")));
      testCase.verifyFalse(isfile(fullfile(pref_dir, "startup.m")));
      testCase.verifyEqual(cache.matlab_root, matlab_root);
      testCase.verifyTrue(isequal(cache.path_entries, config.MatlabEnvironment.default_path_entries(matlab_root)));
      startup_source = string(fileread(char(out.startup_file)));
      testCase.verifyThat(startup_source, matlab.unittest.constraints.ContainsSubstring( ...
        "fullfile(prefdir, 'ExperimentHailMaryPathCache.mat')"));
    end

    function startupManagedBlockIsIdempotentAndPreservesUserContent(testCase)
      matlab_root = create_fake_matlab_root();
      pref_dir = create_temp_folder();
      startup_dir = create_temp_folder();
      cleanup = onCleanup(@() cleanup_dirs({matlab_root, pref_dir, startup_dir}));

      startup_file = config.MatlabEnvironment.startup_file(startup_dir);
      cache_file = config.MatlabEnvironment.cache_file(pref_dir);
      fid = fopen(startup_file, "w");
      fwrite(fid, char("disp('custom startup');" + newline), "char");
      fclose(fid);

      config.MatlabEnvironment.save_cache(cache_file, matlab_root, ...
        config.MatlabEnvironment.default_path_entries(matlab_root));
      config.MatlabEnvironment.upsert_startup_file(startup_file, cache_file);
      config.MatlabEnvironment.upsert_startup_file(startup_file, cache_file);

      source = string(fileread(startup_file));
      testCase.verifyEqual(count(source, "% >>> ExperimentHailMary MATLAB environment >>>"), 1);
      testCase.verifyEqual(count(source, "% <<< ExperimentHailMary MATLAB environment <<<"), 1);
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("disp('custom startup');"));
    end

    function defaultStartupDirUsesFirstUserpathEntry(testCase)
      entries = strsplit(char(string(userpath)), pathsep);
      entries = entries(~cellfun(@(value) isempty(strtrim(value)), entries));

      testCase.assertNotEmpty(entries, "This test requires a configured MATLAB userpath.");
      testCase.verifyEqual(config.MatlabEnvironment.default_startup_dir(), ...
        strtrim(entries{1}));
    end

    function staleCacheWarnsAndDoesNotApplyPaths(testCase)
      pref_dir = create_temp_folder();
      cleanup = onCleanup(@() cleanup_dirs({pref_dir})); 

      cache_file = config.MatlabEnvironment.cache_file(pref_dir);
      matlab_root = fullfile(pref_dir, "missing_root");
      path_entries = {matlab_root; fullfile(matlab_root, "experiment")};
      save(cache_file, "matlab_root", "path_entries");

      original_path = path;
      restoredefaultpath;
      addpath(project_matlab_root());
      resetter = onCleanup(@() path(original_path)); 

      testCase.verifyWarning(@() config.MatlabEnvironment.apply_cached_paths(cache_file), ...
        "config:MatlabEnvironment:setupRequired");
      path_parts = strsplit(path, pathsep);
      testCase.verifyFalse(any(strcmp(path_parts, matlab_root)));
    end

    function applyCachedPathsAddsExactEntries(testCase)
      matlab_root = create_fake_matlab_root();
      pref_dir = create_temp_folder();
      cleanup = onCleanup(@() cleanup_dirs({matlab_root, pref_dir})); 

      cache_file = config.MatlabEnvironment.cache_file(pref_dir);
      config.MatlabEnvironment.save_cache(cache_file, matlab_root, ...
        config.MatlabEnvironment.default_path_entries(matlab_root));

      original_path = path;
      restoredefaultpath;
      addpath(project_matlab_root());
      resetter = onCleanup(@() path(original_path)); 

      applied = config.MatlabEnvironment.apply_cached_paths(cache_file);
      path_parts = strsplit(path, pathsep);

      testCase.verifyTrue(applied);
      testCase.verifyTrue(any(strcmp(path_parts, fullfile(matlab_root, "experiment"))));
      testCase.verifyFalse(any(strcmp(path_parts, fullfile(matlab_root, "+experiment"))));
    end

    function setupWritesLocalEnvironmentConfigNonInteractively(testCase)
      matlab_root = create_fake_matlab_root();
      pref_dir = create_temp_folder();
      startup_dir = create_temp_folder();
      cleanup = onCleanup(@() cleanup_dirs({matlab_root, pref_dir, startup_dir}));

      out = config.MatlabEnvironment.setup(matlab_root, ...
        "pref_dir", pref_dir, ...
        "startup_dir", startup_dir, ...
        "apply_now", false, ...
        "Interactive", false, ...
        "ValidateAds", false, ...
        "Reconfigure", true);

      testCase.verifyEqual(out.local_config_status, "written");
      testCase.verifyTrue(isfile(char(out.local_config_file)));
      source = string(fileread(char(out.local_config_file)));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("classdef LocalEnvironmentConfig"));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring("ams_net_id"));
      testCase.verifyEqual(char(out.local_config_file), ...
        char(fullfile(matlab_root, "+config", "LocalEnvironmentConfig.m")));
    end

    function setupDoesNotRediscoverWhenLocalEnvironmentConfigExists(testCase)
      matlab_root = create_fake_matlab_root();
      pref_dir = create_temp_folder();
      startup_dir = create_temp_folder();
      cleanup = onCleanup(@() cleanup_dirs({matlab_root, pref_dir, startup_dir}));

      local_file = fullfile(matlab_root, "+config", "LocalEnvironmentConfig.m");
      write_text(local_file, join([
        "classdef LocalEnvironmentConfig"
        "  properties (Constant)"
        "    ams_net_id = ""1.2.3.4.5.6"""
        "    seq_port = 853"
        "    control_port = 852"
        "    module_port = 351"
        "    task_rate_hz = 8000"
        "    controller_prefix = ""ControllerCore_Obj1 (Module1)."""
        "    logger_host_file_path = ""\\sunnyday\ExperimentData\experiment_logger.bin"""
        "  end"
        "  methods (Static)"
        "    function s = to_struct()"
        "      s = struct(""ams_net_id"", config.LocalEnvironmentConfig.ams_net_id);"
        "    end"
        "  end"
        "end"
        ""], newline));
      out = config.MatlabEnvironment.setup(matlab_root, ...
        "pref_dir", pref_dir, ...
        "startup_dir", startup_dir, ...
        "apply_now", false, ...
        "Interactive", false, ...
        "ValidateAds", false);

      testCase.verifyEqual(out.local_config_status, "existing");
      testCase.verifyEqual(char(out.local_config_file), char(local_file));
      testCase.verifyThat(string(fileread(local_file)), ...
        matlab.unittest.constraints.ContainsSubstring("1.2.3.4.5.6"));
    end

    function setupCodeDoesNotDependOnExperimentPackage(testCase)
      source = string(fileread(which("config.MatlabEnvironment")));
      testCase.verifyFalse(contains(source, "experiment.RuntimeSymbols"));
    end
  end
end

function root_dir = create_fake_matlab_root()
root_dir = create_temp_folder();
mkdir(fullfile(root_dir, "+config"));
mkdir(fullfile(root_dir, "+experiment"));
mkdir(fullfile(root_dir, "experiment"));
end

function dir_path = create_temp_folder()
dir_path = tempname;
mkdir(dir_path);
end

function cleanup_dirs(paths)
for idx = 1:numel(paths)
  target = char(string(paths{idx}));
  if isfolder(target)
    rmdir(target, "s");
  end
end
end

function matlab_root = project_matlab_root()
matlab_root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

function write_text(file_path, content)
fid = fopen(file_path, "w");
if fid < 0
  error("test:writeFailed", "Could not write %s", file_path);
end
cleaner = onCleanup(@() fclose(fid));
fwrite(fid, char(string(content)), "char");
end
