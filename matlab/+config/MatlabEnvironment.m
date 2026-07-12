classdef MatlabEnvironment
  properties (Constant, Access = private)
    CACHE_FILE_NAME = "ExperimentHailMaryPathCache.mat"
    START_MARKER = "% >>> ExperimentHailMary MATLAB environment >>>"
    END_MARKER = "% <<< ExperimentHailMary MATLAB environment <<<"
  end

  methods (Static)
    function out = setup(varargin)
      [matlab_root, args] = config.MatlabEnvironment.split_setup_args(varargin{:});

      p = inputParser;
      p.addParameter("pref_dir", prefdir, @(x) ischar(x) || isstring(x));
      p.addParameter("apply_now", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("Reconfigure", false, @(x) islogical(x) || isnumeric(x));
      p.addParameter("Interactive", true, @(x) islogical(x) || isnumeric(x));
      p.addParameter("ValidateAds", true, @(x) islogical(x) || isnumeric(x));
      p.parse(args{:});
      opts = p.Results;

      out = config.MatlabEnvironment.install( ...
        matlab_root, ...
        "pref_dir", opts.pref_dir, ...
        "apply_now", opts.apply_now);

      % Resolve the generated file from the root being configured so tests and
      % secondary checkouts never overwrite the active checkout's local file.
      local_file = fullfile(matlab_root, "+config", "LocalEnvironmentConfig.m");
      active_local_file = config.EnvironmentConfig.local_config_file();
      targets_active_environment = strcmpi( ...
        char(string(local_file)), char(string(active_local_file)));
      local_exists = isfile(local_file);
      if local_exists && ~logical(opts.Reconfigure)
        if logical(opts.Interactive) && ...
            config.MatlabEnvironment.confirm_local_environment_reconfigure(local_file)
          opts.Reconfigure = true;
        else
          out.local_config_file = string(local_file);
          out.local_config_status = "existing";
          if targets_active_environment
            out.environment_config = config.EnvironmentConfig.current();
          else
            out.environment_config = config.EnvironmentConfig.current("use_local", false);
          end
          fprintf("Local environment config already exists: %s\n", local_file);
          fprintf("Use config.MatlabEnvironment.setup(""Reconfigure"", true) to rediscover.\n");
          return;
        end
      end

      discovered = config.MatlabEnvironment.discover_environment_config(matlab_root);
      defaults = config.EnvironmentConfig.defaults();
      candidate = config.EnvironmentConfig.from_struct( ...
        config.EnvironmentConfig.merge_structs(defaults.to_struct(), discovered));

      if logical(opts.Interactive)
        config.MatlabEnvironment.print_environment_config_candidate( ...
          candidate, config.MatlabEnvironment.empty_ads_validation());
        candidate = config.MatlabEnvironment.prompt_environment_config(candidate);
      end

      validation = config.MatlabEnvironment.empty_ads_validation();
      if logical(opts.ValidateAds)
        validation = config.MatlabEnvironment.validate_ads_read_only(candidate);
      end

      config.MatlabEnvironment.print_environment_config_candidate(candidate, validation);
      if logical(opts.Interactive)
        accepted = config.MatlabEnvironment.confirm_local_environment_write();
      else
        accepted = true;
      end

      out.local_config_file = string(local_file);
      out.discovered_config = candidate.to_struct();
      out.ads_validation = validation;
      if accepted
        config.MatlabEnvironment.write_local_environment_config(local_file, candidate);
        if targets_active_environment
          clear('config.LocalEnvironmentConfig');
          rehash;
        end
        out.local_config_status = "written";
        if targets_active_environment
          out.environment_config = config.EnvironmentConfig.current();
        else
          out.environment_config = candidate;
        end
        fprintf("Local environment config written: %s\n", local_file);
      else
        out.local_config_status = "skipped";
        out.environment_config = config.EnvironmentConfig.current("use_local", false);
        fprintf("Local environment config was not written.\n");
      end
    end

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
    function [matlab_root, args] = split_setup_args(varargin)
      matlab_root = fileparts(fileparts(mfilename("fullpath")));
      args = varargin;
      if isempty(varargin)
        return;
      end

      first = varargin{1};
      if (ischar(first) || isstring(first)) && isscalar(string(first)) && ...
          isfolder(char(string(first))) && ...
          ~any(strcmpi(char(string(first)), {"pref_dir", "apply_now", "Reconfigure", "Interactive", "ValidateAds"}))
        matlab_root = char(string(first));
        args = varargin(2:end);
      end
    end

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

    function discovered = discover_environment_config(matlab_root)
      matlab_root = config.MatlabEnvironment.validate_matlab_root(matlab_root);
      repo_root = fileparts(matlab_root);
      project_file = fullfile(repo_root, "ExperimentHailMary.tsproj");

      discovered = struct();
      if ~isfile(project_file)
        return;
      end

      source = string(fileread(project_file));
      value = config.MatlabEnvironment.first_regex(source, ...
        '<Project[^>]*TargetNetId="([^"]+)"');
      if strlength(value) > 0
        discovered.ams_net_id = value;
      end
      value = config.MatlabEnvironment.first_number_regex(source, ...
        'Name="StateMachineControl"[^>]*AmsPort="(\d+)"');
      if ~isnan(value)
        discovered.control_port = value;
      end
      value = config.MatlabEnvironment.first_number_regex(source, ...
        'Name="ExperimentSequencer"[^>]*AmsPort="(\d+)"');
      if ~isnan(value)
        discovered.seq_port = value;
      end
      value = config.MatlabEnvironment.first_number_regex(source, ...
        '<Task[^>]*AmsPort="(\d+)"[^>]*>\s*<Name>VirtualMotorTask</Name>');
      if ~isnan(value)
        discovered.module_port = value;
      end

      task_cycle_ns = config.MatlabEnvironment.first_number_regex(source, ...
        '<Name>VirtualMotorTask</Name>[\s\S]{0,300}?<CycleTime>(\d+)</CycleTime>');
      if ~isnan(task_cycle_ns) && task_cycle_ns > 0
        discovered.task_rate_hz = round(1e9 / double(task_cycle_ns));
      end

      controller_name = config.MatlabEnvironment.first_regex(source, ...
        '<Name>(ControllerCore_Obj\d+ \(Module1\))</Name>');
      if strlength(controller_name) > 0
        discovered.controller_prefix = controller_name + ".";
      end

      target_path = config.MatlabEnvironment.first_regex(source, ...
        '<Name>LogControl\.filePath</Name>\s*<String>([^<]+)</String>');
      if strlength(target_path) == 0
        target_path = config.MatlabEnvironment.first_regex(source, ...
          '<Name>filePath</Name>[\s\S]{0,200}?<!\[CDATA\[(.*?)\]\]>');
      end
      if strlength(target_path) > 0
        discovered.logger_target_file_path = target_path;
      end
    end

    function validation = empty_ads_validation()
      validation = struct( ...
        "requested", false, ...
        "ok", false, ...
        "ports_ok", false, ...
        "detail", "not requested");
    end

    function validation = validate_ads_read_only(env)
      validation = config.MatlabEnvironment.empty_ads_validation();
      validation.requested = true;
      validation.detail = "";
      env = config.EnvironmentConfig.from_struct(env);
      ports = [env.control_port, env.seq_port, env.module_port];
      try
        t_ports = twincat_ads.SymbolBrowser.list_ports(char(env.ams_net_id), ports, ...
          "connect_timeout_ms", 1000);
        validation.ports_ok = all(t_ports.Status == "ok");
        validation.port_table = t_ports;
      catch e
        validation.detail = "port validation failed: " + string(e.message);
        return;
      end

      if ~validation.ports_ok
        validation.detail = "one or more ADS ports are unavailable";
        return;
      end
      validation.ok = true;
      validation.detail = "configured ADS ports are reachable";
    end

    function print_environment_config_candidate(env, validation)
      env = config.EnvironmentConfig.from_struct(env);
      fprintf("\n=== ExperimentHailMary environment config candidate ===\n");
      fprintf("ams_net_id              = %s\n", char(env.ams_net_id));
      fprintf("seq_port                = %d\n", env.seq_port);
      fprintf("control_port            = %d\n", env.control_port);
      fprintf("module_port             = %d\n", env.module_port);
      fprintf("task_rate_hz            = %.0f\n", env.task_rate_hz);
      fprintf("controller_prefix       = %s\n", char(env.controller_prefix));
      fprintf("logger_target_file_path = %s\n", char(env.logger_target_file_path));
      fprintf("logger_host_file_path   = %s\n", char(env.logger_host_file_path));
      if validation.requested
        fprintf("ADS validation          = %s\n", char(string(validation.detail)));
      end
      fprintf("\n");
    end

    function out = prompt_environment_config(env)
      env = config.EnvironmentConfig.from_struct(env);
      values = env.to_struct();
      fields = config.EnvironmentConfig.field_names();

      fprintf("Edit local environment config. Press Enter to keep the current value.\n");
      for k = 1:numel(fields)
        key = char(fields(k));
        while true
          current = values.(key);
          prompt = sprintf("%s [%s]: ", key, ...
            char(config.MatlabEnvironment.prompt_value(current)));
          answer = strtrim(string(input(prompt, "s")));
          if strlength(answer) == 0
            break;
          end

          candidate = values;
          try
            candidate.(key) = config.MatlabEnvironment.parse_environment_prompt_value( ...
              key, answer, current);
            candidate_env = config.EnvironmentConfig.from_struct(candidate);
            values = candidate_env.to_struct();
            break;
          catch e
            fprintf("Invalid %s: %s\n", key, e.message);
          end
        end
      end

      out = config.EnvironmentConfig.from_struct(values);
    end

    function value = parse_environment_prompt_value(key, text, current_value)
      if isnumeric(current_value)
        value = str2double(text);
        if ~(isnumeric(value) && isscalar(value) && isfinite(value))
          error("config:MatlabEnvironment:invalidPromptValue", ...
            "%s must be numeric.", key);
        end
      else
        value = string(text);
      end
    end

    function out = prompt_value(value)
      if isnumeric(value)
        out = string(sprintf("%.15g", double(value)));
      else
        out = string(value);
      end
    end

    function accepted = confirm_local_environment_write()
      answer = input("Write this local environment config? [Y/n]: ", "s");
      answer = lower(strtrim(string(answer)));
      accepted = answer == "" || answer == "y" || answer == "yes";
    end

    function accepted = confirm_local_environment_reconfigure(local_file)
      fprintf("Local environment config already exists: %s\n", local_file);
      answer = input("Reconfigure local environment config now? [y/N]: ", "s");
      answer = lower(strtrim(string(answer)));
      accepted = answer == "y" || answer == "yes";
    end

    function write_local_environment_config(local_file, env)
      env = config.EnvironmentConfig.from_struct(env);
      lines = {
        "classdef LocalEnvironmentConfig"
        "% LocalEnvironmentConfig  Machine-local generated environment configuration."
        "% Generated by config.MatlabEnvironment.setup. Do not commit this file."
        "  properties (Constant)"
        "    ams_net_id = " + config.MatlabEnvironment.string_literal(env.ams_net_id)
        "    seq_port = " + string(round(env.seq_port))
        "    control_port = " + string(round(env.control_port))
        "    module_port = " + string(round(env.module_port))
        "    task_rate_hz = " + string(round(env.task_rate_hz))
        "    controller_prefix = " + config.MatlabEnvironment.string_literal(env.controller_prefix)
        "    logger_target_file_path = " + config.MatlabEnvironment.string_literal(env.logger_target_file_path)
        "    logger_host_file_path = " + config.MatlabEnvironment.string_literal(env.logger_host_file_path)
        "    table_max_n = " + string(round(env.table_max_n))
        "    logger_release_timeout_s = " + string(double(env.logger_release_timeout_s))
        "  end"
        ""
        "  methods (Static)"
        "    function s = to_struct()"
        "      mc = ?config.LocalEnvironmentConfig;"
        "      props = mc.PropertyList;"
        "      s = struct();"
        "      for k = 1:numel(props)"
        "        if props(k).Constant"
        "          s.(props(k).Name) = props(k).DefaultValue;"
        "        end"
        "      end"
        "    end"
        "  end"
        "end"
        ""
      };

      fid = fopen(local_file, "w");
      if fid < 0
        error("config:MatlabEnvironment:localConfigWriteFailed", ...
          "Could not write local config file: %s", local_file);
      end
      cleaner = onCleanup(@() fclose(fid));
      fwrite(fid, char(strjoin(string(lines), newline)), "char");
    end

    function out = string_literal(value)
      out = """" + replace(string(value), """", """""") + """";
    end

    function out = first_regex(source, pattern)
      tokens = regexp(char(source), pattern, "tokens", "once");
      if isempty(tokens)
        out = "";
      else
        out = string(tokens{1});
      end
    end

    function out = first_number_regex(source, pattern)
      value = config.MatlabEnvironment.first_regex(source, pattern);
      if strlength(value) == 0
        out = NaN;
      else
        out = str2double(value);
      end
    end
  end
end
