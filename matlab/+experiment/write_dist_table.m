function write_dist_table(transport, dist_profile, expected_len)
% write_dist_table  外乱テーブルを GVL_SEQ に書き込む。
%
%   experiment.write_dist_table(transport, dist_profile, expected_len)
%
%   transport    — 接続済み twincat_ads.IAdsTransport (env.seq_port)
%   dist_profile — double 列ベクトル [N×1]
%
%   書込み先:
%     GVL_SEQ.distTable ← dist_profile
%
%   注: expected_len は ref_profile 長と一致していること。

  arguments
    transport    twincat_ads.IAdsTransport
    dist_profile (:,1) double
    expected_len (1,1) double {mustBeNonnegative}
  end

  if numel(dist_profile) ~= expected_len
    error("experiment:write_dist_table:lengthMismatch", ...
      "dist_profile length (%d) must match expected_len (%d).", ...
      numel(dist_profile), expected_len);
  end

  symbols = experiment.RuntimeSymbols.from_defaults();
  t = symbols.types;

  transport.write_array(symbols.distTable, dist_profile, t.double);
end
