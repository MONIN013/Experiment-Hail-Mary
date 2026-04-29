classdef MatlabEnvironment
  properties (Constant, Access = private)
    CACHE_FILE_NAME = "ExperimentHailMaryPathCache.mat"
    START_MARKER = "% >>> ExperimentHailMary MATLAB environment >>>"
    END_MARKER = "% <<< ExperimentHailMary MATLAB environment <<<"
  end

  methods (Static)
    function out = install(matlab_root, varargin)
      p = inputParser;
      p.addParameter("pref_dir", prefdir, @(x) ischar(x) || isstring(x));
      p.addParameter("apply_now", true, @(x) islogical(x) || isnumeric(x));
      p.parse(varargin{:});

      matlab_root = config.MatlabEnvironment.validate_matlab_root(matlab_root);
      pref_dir = char(string(p.Results.pref_dir));
      if ~isfolder(pref_dir)
        mkdir(pref_dir);
      end

      path_entries = config.MatlabEnvironment.default_path_entries(matlab_root);
      cache_file = config.MatlabEnvironment.cache_file(pref_dir);
      startup_file = config.MatlabEnvironment.startup_file(pref_dir);

      config.MatlabEnvironment.save_cache(cache_file, matlab_root, path_entries);
      config.MatlabEnvironment.upsert_startup_file(startup_file, cache_file);
      if logical(p.Results.apply_now)
        config.MatlabEnvironment.apply_path_entries(path_entries);
      end

      out = struct( ...
        "matlab_root", string(matlab_root), ...
        "path_entries", {string(path_entries(:))}, ...
        "cache_file", string(cache_file), ...
        "startup_file", string(startup_file));
    end

    function path_entries = default_path_entries(matlab_root)
      matlab_root = config.MatlabEnvironment.validate_matlab_root(matlab_root);
      experiment_dir = fullfile(matlab_root, "experiment");
      if ~isfolder(experiment_dir)
        error("config:MatlabEnvironment:invalidRoot", ...
          "matlab_root must contain an experiment script directory.");
      end
      path_entries = {
        matlab_root;
        experiment_dir
      };
    end

    function save_cache(cache_file, matlab_root, path_entries)
      matlab_root = config.MatlabEnvironment.validate_matlab_root(matlab_root);
      path_entries = cellstr(string(path_entries(:)));
      save(cache_file, "matlab_root", "path_entries");
    end

    function cache = load_cache(cache_file)
      if ~isfile(cache_file)
        error("config:MatlabEnvironment:cacheMissing", ...
          "Path cache is missing. Re-run run('matlab/setup_matlab_environment.m').");
      end

      data = load(cache_file, "matlab_root", "path_entries");
      if ~isfield(data, "matlab_root") || ~isfield(data, "path_entries")
        error("config:MatlabEnvironment:cacheInvalid", ...
          "Path cache is invalid. Re-run run('matlab/setup_matlab_environment.m').");
      end

      cache = struct( ...
        "matlab_root", char(string(data.matlab_root)), ...
        "path_entries", {cellstr(string(data.path_entries(:)))});
    end

    function applied = apply_cached_paths(cache_file)
      applied = false;
      try
        cache = config.MatlabEnvironment.load_cache(cache_file);
      catch
        warning("config:MatlabEnvironment:setupRequired", ...
          "%s", config.MatlabEnvironment.setup_required_message());
        return;
      end

      if ~config.MatlabEnvironment.is_cache_valid(cache)
        warning("config:MatlabEnvironment:setupRequired", ...
          "%s", config.MatlabEnvironment.setup_required_message());
        return;
      end

      config.MatlabEnvironment.apply_path_entries(cache.path_entries);
      applied = true;
    end

    function apply_path_entries(path_entries)
      path_entries = cellstr(string(path_entries(:)));
      addpath(path_entries{:});
    end

    function upsert_startup_file(startup_file, cache_file)
      block = config.MatlabEnvironment.managed_startup_block(cache_file);
      if isfile(startup_file)
        original = string(fileread(startup_file));
      else
        original = "";
      end
      original = replace(original, sprintf('\r\n'), newline);
      original = replace(original, sprintf('\r'), newline);

      start_marker = config.MatlabEnvironment.START_MARKER;
      end_marker = config.MatlabEnvironment.END_MARKER;
      original_char = char(original);
      start_idx = strfind(original_char, char(start_marker));
      end_idx = strfind(original_char, char(end_marker));

      if ~isempty(start_idx) && ~isempty(end_idx)
        block_start = start_idx(1);
        block_end = [];
        for idx = 1:numel(end_idx)
          if end_idx(idx) >= block_start
            block_end = end_idx(idx) + strlength(end_marker) - 1;
            break;
          end
        end
        if isempty(block_end)
          updated = config.MatlabEnvironment.append_block(original, block);
        else
          updated = extractBefore(original, block_start) + block + extractAfter(original, block_end);
        end
      else
        updated = config.MatlabEnvironment.append_block(original, block);
      end

      fid = fopen(startup_file, "w");
      if fid < 0
        error("config:MatlabEnvironment:startupWriteFailed", ...
          "Could not write startup file: %s", startup_file);
      end
      cleaner = onCleanup(@() fclose(fid)); 
      fwrite(fid, char(updated), "char");
    end

    function cache_file = cache_file(pref_dir)
      cache_file = fullfile(char(string(pref_dir)), char(config.MatlabEnvironment.CACHE_FILE_NAME));
    end

    function startup_file = startup_file(pref_dir)
      startup_file = fullfile(char(string(pref_dir)), "startup.m");
    end
  end

  methods (Static, Access = private)
    function matlab_root = validate_matlab_root(matlab_root)
      matlab_root = char(string(matlab_root));
      if ~isfolder(matlab_root)
        error("config:MatlabEnvironment:invalidRoot", ...
          "matlab_root must point to an existing directory.");
      end
      if ~isfolder(fullfile(matlab_root, "+config")) || ~isfolder(fullfile(matlab_root, "+experiment"))
        error("config:MatlabEnvironment:invalidRoot", ...
          "matlab_root must contain +config and +experiment directories.");
      end
    end

    function ok = is_cache_valid(cache)
      ok = isfolder(cache.matlab_root) && ...
        ~isempty(cache.path_entries) && ...
        all(cellfun(@(p) isfolder(char(p)), cache.path_entries));
    end

    function block = managed_startup_block(cache_file)
      escaped_cache = strrep(char(string(cache_file)), "'", "''");
      escaped_message = strrep(config.MatlabEnvironment.setup_required_message(), "'", "''");
      lines = {
        char(config.MatlabEnvironment.START_MARKER)
        sprintf("ehm_cache_file = '%s';", escaped_cache)
        "if isfile(ehm_cache_file)"
        "  ehm_cache = load(ehm_cache_file, 'matlab_root', 'path_entries');"
        "  if isfield(ehm_cache, 'matlab_root') && isfield(ehm_cache, 'path_entries')"
        "    ehm_matlab_root = char(string(ehm_cache.matlab_root));"
        "    ehm_path_entries = cellstr(string(ehm_cache.path_entries(:)));"
        "    ehm_valid_entries = ~isempty(ehm_path_entries) && all(cellfun(@(p) isfolder(char(p)), ehm_path_entries));"
        "    if isfolder(ehm_matlab_root) && ehm_valid_entries"
        "      addpath(ehm_path_entries{:});"
        "    else"
        sprintf("      warning('config:MatlabEnvironment:setupRequired', '%s');", escaped_message)
        "    end"
        "  else"
        sprintf("    warning('config:MatlabEnvironment:setupRequired', '%s');", escaped_message)
        "  end"
        "else"
        sprintf("  warning('config:MatlabEnvironment:setupRequired', '%s');", escaped_message)
        "end"
        "clear ehm_cache_file ehm_cache ehm_matlab_root ehm_path_entries ehm_valid_entries;"
        char(config.MatlabEnvironment.END_MARKER)
        ""
      };
      block = strjoin(string(lines), newline);
    end

    function updated = append_block(original, block)
      if strlength(original) == 0
        updated = block;
      elseif endsWith(original, newline)
        updated = original + block;
      else
        updated = original + newline + newline + block;
      end
    end

    function message = setup_required_message()
      message = "ExperimentHailMary MATLAB path cache is missing or stale. Re-run run('matlab/setup_matlab_environment.m').";
    end
  end
end
