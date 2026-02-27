function write_ff_table(transport, ff_profile)
% write_ff_table  フィードフォワードテーブルを GVL_SEQ に書き込む。
%
%   experiment.write_ff_table(transport, ff_profile)
%
%   transport   — 接続済み twincat_ads.IAdsTransport (Port = SystemConfig.SEQ_PORT)
%   ff_profile  — double 列ベクトル [N×1]
%
%   書込み先:
%     GVL_SEQ.ffTable ← ff_profile
%
%   注: tableLen は write_ref_table で設定済みであること。
%       長さが既存 tableLen と異なる場合は warning を出す。

  arguments
    transport  twincat_ads.IAdsTransport
    ff_profile (:,1) double
  end

  symbols = experiment.VirtualMotorSymbols.from_defaults();
  t = symbols.types;

  try
    current_len = double(transport.read_scalar(symbols.tableLen, t.u32));
    if current_len > 0 && numel(ff_profile) ~= current_len
      warning("experiment:write_ff_table:lengthMismatch", ...
        "ff_profile length (%d) differs from current tableLen (%d).", ...
        numel(ff_profile), current_len);
    end
  catch
    % tableLen が読めない場合は無視
  end

  transport.write_array(symbols.ffTable, ff_profile, t.double);
end
