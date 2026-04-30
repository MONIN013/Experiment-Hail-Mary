classdef SystemConfig
% SystemConfig  実験環境に紐づく既定値と実行時設定の入口。
%
%   Constant プロパティは repository の既定値である。実験実行コードは
%   config.SystemConfig.current() を使い、setup が生成した
%   +config/LocalSystemConfig.m があればそれを優先する。
%
%   参照: docs/architecture/MatlabSpec.md

  properties (Constant)
    % --- ADS 接続 ---
    AMS_NET_ID         = "192.168.10.3.1.1"   % XAR の AMS Net ID

    % --- ポート番号 ---
    SEQ_PORT           = 853     % ExperimentSequencer (GVL_SEQ)
    CONTROL_PORT       = 852     % StateMachineControl / ModeManager (GVL_MODE)
    MODULE_PORT        = 351     % C++ TcCOM (ControllerCore / ExperimentLogger)

    % --- タスク周期 ---
    TASK_RATE_HZ       = 8000    % active real-time task 周期 [Hz]

    % --- シンボルプレフィクス ---
    CTRL_PREFIX        = "ControllerCore_Obj1 (Module1)."

    % --- ModeManager ---
    MODE_FLAGS_SYMBOL  = "GVL_MODE.modeFlags"
    LOGGER_FILE_RELEASED_SYMBOL = "GVL_MODE.loggerFileReleased"
    LOGGER_ERROR_CODE_SYMBOL    = "GVL_MODE.loggerErrorCode"

    % --- Logger path ---
    LOGGER_TARGET_FILE_PATH = "C:\ExperimentData\experiment_logger.bin"
    LOGGER_HOST_FILE_PATH   = "\\sunnyday\ExperimentData\experiment_logger.bin"
    LOGGER_DEFAULT_FILE_PATH = "\\sunnyday\ExperimentData\experiment_logger.bin" % compatibility alias

    % --- ログ / テーブル ---
    TABLE_MAX_N        = 100000
    LOGGER_RELEASE_TIMEOUT_S = 5.0
  end

  methods (Static)
    function s = current(varargin)
    % current  setup が生成したローカル設定を反映した実行時設定を返す。
      p = inputParser;
      p.addParameter("use_local", true, @(x) islogical(x) || isnumeric(x));
      p.parse(varargin{:});

      s = config.SystemConfig.to_struct();
      if logical(p.Results.use_local) && exist("config.LocalSystemConfig", "class") == 8
        local = config.LocalSystemConfig.to_struct();
        s = config.SystemConfig.merge_structs(s, local);
      end
      s = config.SystemConfig.normalize_struct(s);
    end

    function s = to_struct()
    % to_struct  repository 既定値を struct として返す。
      mc = ?config.SystemConfig;
      props = mc.PropertyList;
      s = struct();
      for k = 1:numel(props)
        if props(k).Constant
          s.(props(k).Name) = props(k).DefaultValue;
        end
      end
      s = config.SystemConfig.normalize_struct(s);
    end

    function task_dt_ns = task_dt_ns(varargin)
    % task_dt_ns  current() のタスク周期を [ns] 単位で返す。
      p = inputParser;
      p.addParameter("use_local", true, @(x) islogical(x) || isnumeric(x));
      p.parse(varargin{:});
      sys = config.SystemConfig.current("use_local", logical(p.Results.use_local));
      task_dt_ns = uint64(round(1e9 / double(sys.TASK_RATE_HZ)));
    end

    function file_path = local_config_file()
      file_path = fullfile(fileparts(mfilename("fullpath")), "LocalSystemConfig.m");
    end

    function s = normalize_struct(s)
      if ~isfield(s, "LOGGER_TARGET_FILE_PATH")
        s.LOGGER_TARGET_FILE_PATH = config.SystemConfig.LOGGER_TARGET_FILE_PATH;
      end
      if ~isfield(s, "LOGGER_HOST_FILE_PATH")
        if isfield(s, "LOGGER_DEFAULT_FILE_PATH")
          s.LOGGER_HOST_FILE_PATH = s.LOGGER_DEFAULT_FILE_PATH;
        else
          s.LOGGER_HOST_FILE_PATH = config.SystemConfig.LOGGER_HOST_FILE_PATH;
        end
      end
      s.LOGGER_DEFAULT_FILE_PATH = s.LOGGER_HOST_FILE_PATH;
      s.AMS_NET_ID = string(s.AMS_NET_ID);
      s.CTRL_PREFIX = string(s.CTRL_PREFIX);
      s.MODE_FLAGS_SYMBOL = string(s.MODE_FLAGS_SYMBOL);
      s.LOGGER_FILE_RELEASED_SYMBOL = string(s.LOGGER_FILE_RELEASED_SYMBOL);
      s.LOGGER_ERROR_CODE_SYMBOL = string(s.LOGGER_ERROR_CODE_SYMBOL);
      s.LOGGER_TARGET_FILE_PATH = string(s.LOGGER_TARGET_FILE_PATH);
      s.LOGGER_HOST_FILE_PATH = string(s.LOGGER_HOST_FILE_PATH);
      s.LOGGER_DEFAULT_FILE_PATH = string(s.LOGGER_DEFAULT_FILE_PATH);
      s.SEQ_PORT = double(s.SEQ_PORT);
      s.CONTROL_PORT = double(s.CONTROL_PORT);
      s.MODULE_PORT = double(s.MODULE_PORT);
      s.TASK_RATE_HZ = double(s.TASK_RATE_HZ);
      s.TABLE_MAX_N = double(s.TABLE_MAX_N);
      s.LOGGER_RELEASE_TIMEOUT_S = double(s.LOGGER_RELEASE_TIMEOUT_S);
    end

    function out = merge_structs(base, override)
      out = base;
      fields = fieldnames(override);
      for k = 1:numel(fields)
        out.(fields{k}) = override.(fields{k});
      end
    end
  end
end

