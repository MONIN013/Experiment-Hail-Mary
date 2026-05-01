classdef TestEnvironmentConfig < matlab.unittest.TestCase
  methods (Test)
    function defaultsHaveExpectedValues(testCase)
      env = config.EnvironmentConfig.defaults();
      testCase.verifyEqual(env.ams_net_id, config.EnvironmentConfig.DEFAULT_AMS_NET_ID);
      testCase.verifyEqual(env.seq_port, config.EnvironmentConfig.DEFAULT_SEQ_PORT);
      testCase.verifyEqual(env.control_port, config.EnvironmentConfig.DEFAULT_CONTROL_PORT);
      testCase.verifyEqual(env.module_port, config.EnvironmentConfig.DEFAULT_MODULE_PORT);
      testCase.verifyEqual(env.task_rate_hz, config.EnvironmentConfig.DEFAULT_TASK_RATE_HZ);
      testCase.verifyEqual(env.table_max_n, config.EnvironmentConfig.DEFAULT_TABLE_MAX_N);
      testCase.verifyEqual(env.logger_release_timeout_s, config.EnvironmentConfig.DEFAULT_LOGGER_RELEASE_TIMEOUT_S);
      testCase.verifyEqual(env.logger_target_file_path, config.EnvironmentConfig.DEFAULT_LOGGER_TARGET_FILE_PATH);
      testCase.verifyEqual(env.logger_host_file_path, config.EnvironmentConfig.DEFAULT_LOGGER_HOST_FILE_PATH);
    end

    function taskDtNsReturnsOneEighthMsInNanoseconds(testCase)
      env = config.EnvironmentConfig.defaults();
      testCase.verifyEqual(env.task_dt_ns(), uint64(125000));
    end

    function currentFallsBackToRepositoryDefaults(testCase)
      env = config.EnvironmentConfig.current("use_local", false);
      testCase.verifyEqual(env.ams_net_id, config.EnvironmentConfig.DEFAULT_AMS_NET_ID);
      testCase.verifyEqual(env.task_rate_hz, config.EnvironmentConfig.DEFAULT_TASK_RATE_HZ);
    end

    function toStructReturnsCanonicalFields(testCase)
      env = config.EnvironmentConfig.defaults();
      s = env.to_struct();
      testCase.verifyTrue(isstruct(s));
      testCase.verifyTrue(isfield(s, 'ams_net_id'));
      testCase.verifyTrue(isfield(s, 'seq_port'));
      testCase.verifyTrue(isfield(s, 'control_port'));
      testCase.verifyTrue(isfield(s, 'module_port'));
      testCase.verifyTrue(isfield(s, 'task_rate_hz'));
      testCase.verifyTrue(isfield(s, 'controller_prefix'));
      testCase.verifyTrue(isfield(s, 'logger_target_file_path'));
      testCase.verifyTrue(isfield(s, 'logger_host_file_path'));
      testCase.verifyTrue(isfield(s, 'table_max_n'));
      testCase.verifyTrue(isfield(s, 'logger_release_timeout_s'));
      testCase.verifyFalse(isfield(s, 'MODE_FLAGS_SYMBOL'));
      testCase.verifyEqual(s.seq_port, 853);
    end

    function currentUsesLocalEnvironmentConfig(testCase)
      guard = preserve_local_environment_config();
      local_file = config.EnvironmentConfig.local_config_file();
      write_text(local_file, join([
        "classdef LocalEnvironmentConfig"
        "  properties (Constant)"
        "    ams_net_id = ""1.2.3.4.5.6"""
        "    task_rate_hz = 4000"
        "  end"
        "  methods (Static)"
        "    function s = to_struct()"
        "      s = struct(""ams_net_id"", config.LocalEnvironmentConfig.ams_net_id, ""task_rate_hz"", config.LocalEnvironmentConfig.task_rate_hz);"
        "    end"
        "  end"
        "end"
        ""], newline));
      clear('config.LocalEnvironmentConfig');
      rehash;

      env = config.EnvironmentConfig.current();
      testCase.verifyEqual(env.ams_net_id, "1.2.3.4.5.6");
      testCase.verifyEqual(env.task_rate_hz, 4000);
      clear guard;
    end

    function rejectsUnknownAndInvalidFields(testCase)
      testCase.verifyError(@() config.EnvironmentConfig.from_struct(struct("unknown", 1)), ...
        "config:EnvironmentConfig:invalid");
      testCase.verifyError(@() config.EnvironmentConfig.from_struct(struct("task_rate_hz", -1)), ...
        "config:EnvironmentConfig:invalid");
      testCase.verifyError(@() config.EnvironmentConfig.from_struct(struct("seq_port", "bad")), ...
        "config:EnvironmentConfig:invalid");
    end
  end
end

function guard = preserve_local_environment_config()
local_file = config.EnvironmentConfig.local_config_file();
existed = isfile(local_file);
if existed
  original = string(fileread(local_file));
else
  original = "";
end
guard = onCleanup(@() restore_local_environment_config(local_file, existed, original));
end

function restore_local_environment_config(local_file, existed, original)
if existed
  write_text(local_file, original);
elseif isfile(local_file)
  delete(local_file);
end
clear('config.LocalEnvironmentConfig');
rehash;
end

function write_text(file_path, content)
fid = fopen(file_path, "w");
if fid < 0
  error("test:writeFailed", "Could not write %s", file_path);
end
cleaner = onCleanup(@() fclose(fid));
fwrite(fid, char(string(content)), "char");
end
