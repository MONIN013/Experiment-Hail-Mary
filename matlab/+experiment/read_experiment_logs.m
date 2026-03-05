function log_data = read_experiment_logs(transport, log_n)
% read_experiment_logs  GVL_SEQ_LOG からログを一括読み出す（上位読み取り方式）。
%
%   log_data = experiment.read_experiment_logs(transport, log_n)
%
%   transport — 接続済み twincat_ads.IAdsTransport (Port = SystemConfig.SEQ_PORT)
%
%   戻り値 log_data (struct):
%     .logSeq           — uint32 シーケンス番号
%     .logRefValue      — double 位置指令
%     .logFfValue       — double FF値
%     .logDistValue     — double 外乱値
%     .logControlInput  — double 制御出力
%     .logTargetCurrent — double 合計電流
%     .logPositionAct   — double 実位置
%     .logT             — uint64 タイムスタンプ [ns]
%     .logIdx           — uint32 repeat をまたいだ絶対インデックス
%     .wrIdx            — double 書き込みインデックス
%     .overflow         — logical オーバーフロー検出

  arguments
    transport twincat_ads.IAdsTransport
    log_n (1,1) double {mustBePositive}
  end

  symbols = experiment.VirtualMotorSymbols.from_defaults();
  t = symbols.types;

  log_data = empty_log();

  try
    wr_idx = transport.read_scalar(symbols.log.wrIdx, t.u32);
    overflow = transport.read_scalar(symbols.log.overflow, t.bool);
    valid_n = uint32(min(double(wr_idx), double(log_n)));

    if valid_n > 0
      log_data.logSeq          = double(transport.read_array(symbols.log.logSeq, t.u32, valid_n));
      log_data.logRefValue     = double(transport.read_array(symbols.log.logRefValue, t.double, valid_n));
      log_data.logFfValue      = double(transport.read_array(symbols.log.logFfValue, t.double, valid_n));
      log_data.logDistValue    = double(transport.read_array(symbols.log.logDistValue, t.double, valid_n));
      log_data.logControlInput = double(transport.read_array(symbols.log.logControlInput, t.double, valid_n));
      log_data.logTargetCurrent = double(transport.read_array(symbols.log.logTargetCurrent, t.double, valid_n));
      log_data.logPositionAct  = double(transport.read_array(symbols.log.logPositionAct, t.double, valid_n));
      try
        log_data.logT = double(transport.read_array(symbols.log.logT, t.u64, valid_n));
      catch
        log_data.logT = zeros(double(valid_n), 1);
      end
      try
        log_data.logIdx = double(transport.read_array(symbols.log.logIdx, t.u32, valid_n));
      catch
        log_data.logIdx = zeros(0, 1);
      end
    end

    log_data.wrIdx    = double(wr_idx);
    log_data.overflow = logical(overflow);
  catch e
    log_data = empty_log();
    warning("experiment:read_experiment_logs:unavailable", ...
      "Log read failed; returning empty logs (%s: %s).", ...
      string(e.identifier), string(e.message));
  end
end

function out = empty_log()
  out = struct( ...
    "logSeq",          zeros(0, 1), ...
    "logRefValue",     zeros(0, 1), ...
    "logFfValue",      zeros(0, 1), ...
    "logDistValue",    zeros(0, 1), ...
    "logControlInput", zeros(0, 1), ...
    "logTargetCurrent", zeros(0, 1), ...
    "logPositionAct",  zeros(0, 1), ...
    "logT",            zeros(0, 1), ...
    "logIdx",          zeros(0, 1), ...
    "wrIdx",           0, ...
    "overflow",        false);
end
