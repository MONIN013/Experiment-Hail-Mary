# proto/ について

この `proto/` は旧講義リポジトリ由来の参照資料です。
元は Simulink `twomass_exp_2019a` 世代の実験スクリプトです。
このリポジトリの現行 MATLAB 層では実行不能です。

各スクリプトには `../config/data/config.mat` などの読み込みがあります。
現在のリポジトリには、その読み込み先や前提ファイルは存在しません。
現行の正本は `docs/architecture/MatlabSpec.md` と `matlab/README.md` です。

`exp01_SysId.m` と `exp02_FeedBack.m` は、この資料を設計元ネタにしています。
`feedforward_experiment.m` は将来の `exp03` の元ネタとして保持しています。
このディレクトリは編集・実行対象ではありません。
