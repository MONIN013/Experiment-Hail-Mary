function write_ref_table(transport, ref_profile, table_max_n)
% write_ref_table  位置指令テーブルを GVL_SEQ に書き込む。
%
%   experiment.write_ref_table(transport, ref_profile, table_max_n)
%
%   transport    — 接続済み twincat_ads.IAdsTransport (env.seq_port)
%   ref_profile  — double 列ベクトル [N×1]
%
%   書込み先:
%     GVL_SEQ.refTable  ← ref_profile
%
%   table_max_n を超過した場合はエラーを投げる。tableLen は、ff/dist
%   table も含む全書込みが完了した後に ExperimentRunner が公開する。

  arguments
    transport   twincat_ads.IAdsTransport
    ref_profile (:,1) double
    table_max_n (1,1) double {mustBePositive}
  end

  n = numel(ref_profile);
  if n > table_max_n
    error("experiment:write_ref_table:tooLong", ...
      "ref_profile length (%d) exceeds table_max_n (%d).", n, table_max_n);
  end

  symbols = experiment.RuntimeSymbols.from_defaults();
  transport.write_array(symbols.refTable, ref_profile, symbols.types.double);
end
