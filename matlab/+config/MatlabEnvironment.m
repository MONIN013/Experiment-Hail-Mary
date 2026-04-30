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

      local_file = config.SystemConfig.local_config_file();
      local_exists = isfile(local_file);
      if local_exists && ~logical(opts.Reconfigure)
        out.local_config_file = string(local_file);
        out.local_config_status = "existing";
        out.system_config = config.SystemConfig.current();
        fprintf("Local system config already exists: %s\n", local_file);
        fprintf("Use config.MatlabEnvironment.setup(""Reconfigure"", true) to rediscover.\n");
        return;
      end

      discovered = config.MatlabEnvironment.discover_system_config(matlab_root);
      candidate = config.SystemConfig.merge_structs(config.SystemConfig.to_struct(), discovered);
      candidate = config.SystemConfig.normalize_struct(candidate);

      validation = config.MatlabEnvironment.empty_ads_validation();
      if logical(opts.ValidateAds)
        validation = config.MatlabEnvironment.validate_ads_read_only(candidate);
      end

      config.MatlabEnvironment.print_system_config_candidate(candidate, validation);
      if logical(opts.Interactive)
        accepted = config.MatlabEnvironment.confirm_local_config_write();
      else
        accepted = true;
      end

      out.local_config_file = string(local_file);
      out.discovered_config = candidate;
      out.ads_validation = validation;
      if accepted
        config.MatlabEnvironment.write_local_system_config(local_file, candidate);
        clear('config.LocalSystemConfig');
        rehash;
        out.local_config_status = "written";
        out.system_config = config.SystemConfig.current();
        fprintf("Local system config written: %s\n", local_file);
      else
        out.local_config_status = "skipped";
        out.system_config = config.SystemConfig.current("use_local", false);
        fprintf("Local system config was not written.\n");
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

    function discovered = discover_system_config(matlab_root)
      matlab_root = config.MatlabEnvironment.validate_matlab_root(matlab_root);
      repo_root = fileparts(matlab_root);
      preferred = fullfile(repo_root, "ExperimentHailMary.RealMotor.tsproj");
      fallback = fullfile(repo_root, "ExperimentHailMary.tsproj");
      if isfile(preferred)
        project_file = preferred;
      elseif isfile(fallback)
        project_file = fallback;
      else
        project_file = "";
      end

      discovered = struct();
      if strlength(string(project_file)) == 0
        return;
      end

      source = string(fileread(project_file));
      discovered.SOURCE_PROJECT_FILE = string(project_file);
      value = config.MatlabEnvironment.first_regex(source, ...
        '<Project[^>]*TargetNetId="([^"]+)"');
      if strlength(value) > 0
        discovered.AMS_NET_ID = value;
      end
      value = config.MatlabEnvironment.first_number_regex(source, ...
        'Name="StateMachineControl"[^>]*AmsPort="(\d+)"');
      if ~isnan(value)
        discovered.CONTROL_PORT = value;
      end
      value = config.MatlabEnvironment.first_number_regex(source, ...
        'Name="ExperimentSequencer"[^>]*AmsPort="(\d+)"');
      if ~isnan(value)
        discovered.SEQ_PORT = value;
      end
      value = config.MatlabEnvironment.first_number_regex(source, ...
        '<Task[^>]*AmsPort="(\d+)"[^>]*>\s*<Name>VirtualMotorTask</Name>');
      if ~isnan(value)
        discovered.MODULE_PORT = value;
      end

      task_cycle_ns = config.MatlabEnvironment.first_number_regex(source, ...
        '<Name>VirtualMotorTask</Name>[\s\S]{0,300}?<CycleTime>(\d+)</CycleTime>');
      if ~isnan(task_cycle_ns) && task_cycle_ns > 0
        discovered.TASK_RATE_HZ = round(1e9 / double(task_cycle_ns));
      end

      controller_name = config.MatlabEnvironment.first_regex(source, ...
        '<Name>(ControllerCore_Obj\d+ \(Module1\))</Name>');
      if strlength(controller_name) > 0
        discovered.CTRL_PREFIX = controller_name + ".";
      end

      target_path = config.MatlabEnvironment.first_regex(source, ...
        '<Name>LogControl\.filePath</Name>\s*<String>([^<]+)</String>');
      if strlength(target_path) == 0
        target_path = config.MatlabEnvironment.first_regex(source, ...
          '<Name>filePath</Name>[\s\S]{0,200}?<!\[CDATA\[(.*?)\]\]>');
      end
      if strlength(target_path) > 0
        discovered.LOGGER_TARGET_FILE_PATH = target_path;
      end
    end

    function validation = empty_ads_validation()
      validation = struct( ...
        "requested", false, ...
        "ok", false, ...
        "ports_ok", false, ...
        "symbols_ok", false, ...
        "detail", "not requested");
    end

    function validation = validate_ads_read_only(sys)
      validation = config.MatlabEnvironment.empty_ads_validation();
      validation.requested = true;
      validation.detail = "";
      ports = [sys.CONTROL_PORT, sys.SEQ_PORT, sys.MODULE_PORT];
      try
        t_ports = twincat_ads.SymbolBrowser.list_ports(char(sys.AMS_NET_ID), ports, ...
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

      transports = cell(1, numel(ports));
      try
        for k = 1:numel(ports)
          transports{k} = twincat_ads.AdsTransport();
          transports{k}.connect(char(sys.AMS_NET_ID), ports(k));
        end
        seq = transports{ports == sys.SEQ_PORT};
        module = transports{ports == sys.MODULE_PORT};
        plc_symbols = experiment.RuntimeSymbols.from_defaults();
        ctrl_symbols = experiment.RuntimeSymbols.from_controller_prefix(char(sys.CTRL_PREFIX));
        twincat_ads.SymbolBrowser.validate_symbols(seq, plc_symbols.plcRequiredProbes);
        twincat_ads.SymbolBrowser.validate_symbols(module, ctrl_symbols.controllerRequiredProbes);
        validation.symbols_ok = true;
        validation.ok = true;
        validation.detail = "ADS ports and required symbols are readable";
      catch e
        validation.detail = "symbol validation failed: " + string(e.message);
      end
      config.MatlabEnvironment.disconnect_transports(transports);
    end

    function disconnect_transports(transports)
      for k = 1:numel(transports)
        if isempty(transports{k})
          continue;
        end
        try
          transports{k}.disconnect();
        catch
        end
      end
    end

    function print_system_config_candidate(sys, validation)
      fprintf("\n=== ExperimentHailMary system config candidate ===\n");
      fprintf("AMS_NET_ID              = %s\n", char(sys.AMS_NET_ID));
      fprintf("SEQ_PORT                = %d\n", sys.SEQ_PORT);
      fprintf("CONTROL_PORT            = %d\n", sys.CONTROL_PORT);
      fprintf("MODULE_PORT             = %d\n", sys.MODULE_PORT);
      fprintf("TASK_RATE_HZ            = %.0f\n", sys.TASK_RATE_HZ);
      fprintf("CTRL_PREFIX             = %s\n", char(sys.CTRL_PREFIX));
      fprintf("LOGGER_TARGET_FILE_PATH = %s\n", char(sys.LOGGER_TARGET_FILE_PATH));
      fprintf("LOGGER_HOST_FILE_PATH   = %s\n", char(sys.LOGGER_HOST_FILE_PATH));
      if validation.requested
        fprintf("ADS validation          = %s\n", char(string(validation.detail)));
      end
      fprintf("\n");
    end

    function accepted = confirm_local_config_write()
      answer = input("Write this local system config? [Y/n]: ", "s");
      answer = lower(strtrim(string(answer)));
      accepted = answer == "" || answer == "y" || answer == "yes";
    end

    function write_local_system_config(local_file, sys)
      lines = {
        "classdef LocalSystemConfig"
        "% LocalSystemConfig  Machine-local generated system configuration."
        "% Generated by config.MatlabEnvironment.setup. Do not commit this file."
        "  properties (Constant)"
        "    AMS_NET_ID = " + config.MatlabEnvironment.string_literal(sys.AMS_NET_ID)
        "    SEQ_PORT = " + string(round(sys.SEQ_PORT))
        "    CONTROL_PORT = " + string(round(sys.CONTROL_PORT))
        "    MODULE_PORT = " + string(round(sys.MODULE_PORT))
        "    TASK_RATE_HZ = " + string(round(sys.TASK_RATE_HZ))
        "    CTRL_PREFIX = " + config.MatlabEnvironment.string_literal(sys.CTRL_PREFIX)
        "    MODE_FLAGS_SYMBOL = " + config.MatlabEnvironment.string_literal(sys.MODE_FLAGS_SYMBOL)
        "    LOGGER_FILE_RELEASED_SYMBOL = " + config.MatlabEnvironment.string_literal(sys.LOGGER_FILE_RELEASED_SYMBOL)
        "    LOGGER_ERROR_CODE_SYMBOL = " + config.MatlabEnvironment.string_literal(sys.LOGGER_ERROR_CODE_SYMBOL)
        "    LOGGER_TARGET_FILE_PATH = " + config.MatlabEnvironment.string_literal(sys.LOGGER_TARGET_FILE_PATH)
        "    LOGGER_HOST_FILE_PATH = " + config.MatlabEnvironment.string_literal(sys.LOGGER_HOST_FILE_PATH)
        "    LOGGER_DEFAULT_FILE_PATH = " + config.MatlabEnvironment.string_literal(sys.LOGGER_HOST_FILE_PATH)
        "    TABLE_MAX_N = " + string(round(sys.TABLE_MAX_N))
        "    LOGGER_RELEASE_TIMEOUT_S = " + string(double(sys.LOGGER_RELEASE_TIMEOUT_S))
        "  end"
        ""
        "  methods (Static)"
        "    function s = to_struct()"
        "      mc = ?config.LocalSystemConfig;"
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
