classdef TestMatlabEnvironment < matlab.unittest.TestCase
  methods (Test)
    function installWritesCacheAndStartupFile(testCase)
      matlab_root = create_fake_matlab_root();
      pref_dir = create_temp_folder();
      cleanup = onCleanup(@() cleanup_dirs({matlab_root, pref_dir})); 

      out = config.MatlabEnvironment.install(matlab_root, ...
        "pref_dir", pref_dir, ...
        "apply_now", false);
      cache = config.MatlabEnvironment.load_cache(char(out.cache_file));

      testCase.verifyTrue(isfile(char(out.cache_file)));
      testCase.verifyTrue(isfile(char(out.startup_file)));
      testCase.verifyEqual(cache.matlab_root, matlab_root);
      testCase.verifyTrue(isequal(cache.path_entries, config.MatlabEnvironment.default_path_entries(matlab_root)));
    end

    function startupManagedBlockIsIdempotentAndPreservesUserContent(testCase)
      matlab_root = create_fake_matlab_root();
      pref_dir = create_temp_folder();
      cleanup = onCleanup(@() cleanup_dirs({matlab_root, pref_dir})); 

      startup_file = config.MatlabEnvironment.startup_file(pref_dir);
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
