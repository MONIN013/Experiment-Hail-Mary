function write_dist_table(transport, dist_profile)
% write_dist_table  外乱テーブルを GVL_SEQ に書き込む。
%
%   experiment.write_dist_table(transport, dist_profile)
%
%   transport    — 接続済み twincat_ads.IAdsTransport (Port = SystemConfig.SEQ_PORT)
%   dist_profile — double 列ベクトル [N×1]
%
%   書込み先:
%     GVL_SEQ.distTable ← dist_profile
%
%   注: tableLen は write_ref_table で設定済みであること。

  arguments
    transport    twincat_ads.IAdsTransport
    dist_profile (:,1) double
  end

  symbols = experiment.VirtualMotorSymbols.from_defaults();
  t = symbols.types;

  transport.write_array(symbols.distTable, dist_profile, t.double);
end
