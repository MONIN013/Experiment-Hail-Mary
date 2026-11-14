# higs_bench

実機ベンチ（16 kHz）で HIGS 設計を試す関数群。ADS へ書き込むので、使う前に安全条件を確認する。接続と周期は `ExperimentConfig.defaults().env` に従う。
準備: `addpath('matlab', 'matlab/experiment', 'matlab/tools/higs_bench')`（`setup_matlab_environment.m` は不要）。

- `higs_bench_limits("check" | "write" | "reset")`: 換算・符号と trip ラッチの確認、IDLE での上限の書込みと readback、`SafetyResetRevision` の更新。
- `higs_bench_trial(design_json, mode, out_dir, name, amplitude_rad=, move_time_s=, coulomb_a=)`: exp05 設計の1試行（最大3回再試行）。生ログを `<out_dir>/<name>.mat` に保存し、誤差・電流・200〜400 Hz ねじれを表示する。
- `higs_bench_multisine("run" | "analyze", out_dir, name, amplitude_a=)`: 開ループのランダム奇数マルチサインと FRF（`frf_<name>.mat`）。
- `higs_bench_sensitivity("run" | "analyze", out_dir, name, design_path=, mode=)`: 等速ランプ上の外乱マルチサインによる閉ループ感度。
- `higs_bench_run`、`higs_bench_metrics`: 上記が使う実行部と指標計算。

例: `higs_bench_limits("write")` の後に `higs_bench_trial("simulations/hardware/designs/hw_design_both_book.json", "both", "simulations/hardware/trials", "a10m010_2_both", amplitude_rad=1, move_time_s=0.1, coulomb_a=0.10)`。保護停止（trip）は例外で止まる。原因を確認してから `higs_bench_limits("reset")` を使う。
