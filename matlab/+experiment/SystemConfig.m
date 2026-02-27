classdef SystemConfig
% SystemConfig  環境・ハードウェアに紐づく不変パラメータの一元定義。
%
%   実験ごとに変化しない値（AMS Net ID、ポート番号、シンボルプレフィクス等）を
%   Constant プロパティとして保持する。環境を切り替える場合はここだけ変更する。
%
%   参照: docs/MatlabSpec.md

  properties (Constant)
    % --- ADS 接続 ---
    AMS_NET_ID         = "192.168.10.3.1.1"   % XAR の AMS Net ID

    % --- ポート番号 ---
    SEQ_PORT           = 853     % ExperimentSequencer (GVL_SEQ / GVL_SEQ_LOG)
    CONTROL_PORT       = 852     % StateMachineControl / ModeManager (GVL_MODE)
    DRIVER_PORT        = 851     % DriverAdapter (GVL_DRV)
    MODULE_PORT        = 351     % C++ TcCOM (ControllerCore / VirtualMotorCore / ExperimentLogger)

    % --- タスク周期 ---
    TASK_RATE_HZ       = 1000    % VirtualMotorTask 周期 [Hz]

    % --- シンボルプレフィクス ---
    VM_PREFIX          = "VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter."
    CTRL_PREFIX        = "ControllerCore_Obj1 (Module1)."

    % --- ModeManager ---
    MODE_FLAGS_SYMBOL  = "GVL_MODE.modeFlags"  % modeFlags 正規書込み先

    % --- ログ / テーブル ---
    LOG_N              = 200000  % GVL_SEQ_LOG リングバッファサイズ
    TABLE_MAX_N        = 100000  % refTable / ffTable / distTable 最大長
  end

  methods (Static)
    function s = to_struct()
    % to_struct  全 Constant プロパティを struct として返す。
      mc = ?experiment.SystemConfig;
      props = mc.PropertyList;
      s = struct();
      for k = 1:numel(props)
        if props(k).Constant
          s.(props(k).Name) = props(k).DefaultValue;
        end
      end
    end

    function task_dt_ns = task_dt_ns()
    % task_dt_ns  タスク周期を [ns] 単位で返す。
      task_dt_ns = uint64(round(1e9 / experiment.SystemConfig.TASK_RATE_HZ));
    end
  end
end

