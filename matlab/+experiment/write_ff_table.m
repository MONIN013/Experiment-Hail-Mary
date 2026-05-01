function write_ff_table(transport, ff_profile, expected_len)
% write_ff_table  フィードフォワードテーブルを GVL_SEQ に書き込む。
%
%   experiment.write_ff_table(transport, ff_profile, expected_len)
%
%   transport   — 接続済み twincat_ads.IAdsTransport (env.seq_port)
%   ff_profile  — double 列ベクトル [N×1]
%
%   書込み先:
%     GVL_SEQ.ffTable ← ff_profile
%
%   注: expected_len は ref_profile 長と一致していること。

  arguments
    transport  twincat_ads.IAdsTransport
    ff_profile (:,1) double
    expected_len (1,1) double {mustBeNonnegative}
  end

  if numel(ff_profile) ~= expected_len
    error("experiment:write_ff_table:lengthMismatch", ...
      "ff_profile length (%d) must match expected_len (%d).", ...
      numel(ff_profile), expected_len);
  end

  symbols = experiment.RuntimeSymbols.from_defaults();
  t = symbols.types;

  transport.write_array(symbols.ffTable, ff_profile, t.double);
end
