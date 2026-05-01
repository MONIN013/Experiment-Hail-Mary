# Matlab Spec

> **位置づけ:** `matlab/` 以下の現行 API と責務分離の正本
> **対象読者:** MATLAB 実装者、ADS 連携の保守担当者  
> **更新条件:** MATLAB 側 API、出力契約、TwinCAT との接続面が変わったとき
> **関連文書:** [ProjectOverview](../overview/ProjectOverview.md) / [SystemArchitecture](./SystemArchitecture.md) / [TechnicalReference](./TechnicalReference.md) / [NamingConvention](../operations/NamingConvention.md)

---

## 1. 概要

MATLAB 層は **実験統括・パラメータ設定・ログ取得・解析** を担当する。リアルタイム制御は TwinCAT 側に委譲し、MATLAB は ADS と logger `.bin` を使って以下を行う。

* `GVL_SEQ` への `ref/ff/dist` テーブル書込み
* `GVL_MODE` による reset / start / stop / 状態監視
* ControllerCore のパラメータ注入
* VirtualMotorCore のパラメータ注入 (`virtualMotor.writeParams`)
* logger `.bin` の読出しと再生評価

---

## 2. パッケージ構成

| パッケージ | パス | 役割 |
|---|---|---|
| `+config` | `matlab/+config/` | 環境設定、MATLAB 起動 bootstrap |
| `+experiment` | `matlab/+experiment/` | orchestration / 解析 / TwinCAT 実行補助 |
| `+twincat_ads` | `matlab/+twincat_ads/` | 汎用 ADS 通信層 |
| `+twincat_ads/+internal` | `matlab/+twincat_ads/+internal/` | 非公開内部実装 |

依存方向は `+experiment -> +config` と `+experiment -> +twincat_ads` のみとする。

---

## 3. 公開 API

現行の正本 API は以下のみ。

| クラス / 関数 | 役割 |
|---|---|
| `config.EnvironmentConfig.current()` | ローカル設定を反映した環境固定値 |
| `config.MatlabEnvironment` | startup / path cache / local config の管理 |
| `experiment.ConnectionManager` | `AdsSession` を使った transport 構築 |
| `experiment.ExperimentRunner` | 実験実行フロー本体 |
| `experiment.ExperimentConfig` | 実験実行の主 runtime config (`cfg.env` に環境 snapshot を内包) |
| `experiment.ControllerConfig` | ControllerCore 用の 4 段 biquad 設定 |
| `virtualMotor.PlantConfig` | VirtualMotorCore 用の物理パラメータ |
| `virtualMotor.writeParams` | VirtualMotorCore parameter write |
| `twincat_ads.AdsSession` | AMS Net ID 単位の transport キャッシュ |
| `twincat_ads.AdsTransport` | TwinCAT ADS 実装 |
| `twincat_ads.SymbolBrowser` | シンボル列挙 / 契約検証 |

以下の legacy API は現行実装から削除済みで、正本ではない。

* `experiment.RunConfig`
* `experiment.PositionCommandConfig`
* `experiment.send_position_command`
* `experiment.run_virtualmotor`
* `experiment.VirtualMotorService`

---

## 4. Config 所有

| 所有者 | 責務 |
|---|---|
| `config.EnvironmentConfig.current()` | 環境固定値 |
| `config.MatlabEnvironment` | startup / path cache 管理 |
| `experiment.ExperimentConfig` | 実行時設定。`defaults()` が `cfg.env` に環境 snapshot を持つ |
| `experiment.ControllerConfig` | ControllerCore パラメータ |
| `virtualMotor.PlantConfig` | VM パラメータ |

`experiment.ExperimentConfig` は canonical runtime field と `env` のみを保持する。互換入力として `ams_net_id` / `seq_port` などの flat 環境値は受けるが、normalize 後は `cfg.env` に折り込む。`ams_port` / `control_ams_port` / `module_ams_port` や legacy config object は受理しない。

---

## 5. PATH 初期化

初回セットアップは一度だけ `run('matlab/setup_matlab_environment.m')` を実行する。

* `prefdir/ExperimentHailMaryPathCache.mat` に `matlab_root` と exact `path_entries` を保存する
* `prefdir/startup.m` の managed block を更新し、次回以降の MATLAB 起動で cache を読む
* `matlab/+config/LocalEnvironmentConfig.m` に PC ごとの ADS / logger 設定を生成する
* 既存 local config がある場合は再探索しない。再探索は `config.MatlabEnvironment.setup("Reconfigure", true)` のみで行う
* cache が欠落または stale の場合は探索せず、setup の再実行を警告する
* 起動時に追加する path は `matlab/` と `matlab/experiment/` の 2 本だけとする

---

## 6. `EnvironmentConfig` の主要値

| プロパティ | 値 | 説明 |
|---|---|---|
| `ams_net_id` | `"192.168.10.3.1.1"` | XAR の AMS Net ID |
| `seq_port` | `853` | ExperimentSequencer |
| `control_port` | `852` | ModeManager |
| `module_port` | `351` | C++ TcCOM 群 |
| `task_rate_hz` | `8000` | `VirtualMotorTask` 周波数 |
| `controller_prefix` | `"ControllerCore_Obj1 (Module1)."` | Controller parameter prefix |
| `logger_target_file_path` | `"C:\\ExperimentData\\experiment_logger.bin"` | TwinCAT 側 logger 保存先 |
| `logger_host_file_path` | `"\\\\sunnyday\\ExperimentData\\experiment_logger.bin"` | MATLAB 側 logger 読み取り先 |
| `table_max_n` | `100000` | テーブル長上限 |
| `logger_release_timeout_s` | `5.0` | logger close 待ち既定値 |

`GVL_MODE.*` などの fixed symbol contract は `experiment.RuntimeSymbols` / `experiment.ModeManagerControl` が正本であり、environment config には置かない。

active contract は `351/852/853` のみを使う。`851` は discovery 用にローカルで明示指定する場合だけ扱う。

---

## 7. 実行フロー

### 7.1 `ExperimentRunner.run(conn, cfg, ...)`

1. `experiment.ExperimentConfig` を normalize / validate
2. Symbol contract を必要に応じて検証
3. `ModeManagerControl` で `resetReq/resetAckCounter` handshake
4. `GVL_SEQ` へ `ref/ff/dist/tableLen/repeatCount` を書き込む
5. `ControllerCore` へ parameter を書き込む
6. `modeFlags` で servo enable -> experiment start
7. `GVL_MODE.experimentState` / `experimentActive` を監視
8. `GVL_MODE.loggerFileReleased` / `loggerErrorCode` を監視
9. logger `.bin` を読んで `out.raw` と `out.metrics` を返す

### 7.2 `ConnectionManager`

* `create(cfg)` は `seq`, `ctrl`, `module` をまとめて返す
* `create_plc_only(cfg)` は `seq`, `ctrl` だけを返す
* 接続先 AMS / port は `cfg.env` から取り、戻り値 `conn.env` に同じ snapshot を保持する
* `from_transports(...)` は既存 transport を runner 契約へ束ねる

### 7.3 VM parameter write

* VM parameter は `ExperimentRunner` ではなく `virtualMotor.writeParams(conn, vm_cfg)` で明示的に書き込む
* `experiment.ExperimentConfig` は VM parameter や `write_plant_params` を保持しない
* step demo / SI demo は実行前に必要な VM preset を自分で適用する

---

## 8. 出力契約

### 8.1 正本出力

`ExperimentRunner.run(...)` の `out.raw` は snake_case を正本とする。

主フィールド:

* `seq`
* `ref_value`
* `ff_value`
* `dist_value`
* `control_input`
* `target_current`
* `position_act`

### 8.2 評価結果

`out.metrics` が唯一の評価出力であり、`out.eval` は存在しない。

* `metrics.sampling` は command/log の件数と sequence gap を返す
* `metrics.input_waveform`, `ff_waveform`, `dist_waveform` は replay 一致性を返す
* `metrics.torque_sum` は `control_input + dist_value == target_current` の整合性を返す
* `metrics.position_diag` は位置ログの利用可否と速度推定を返す

`preload_eval` は snake_case raw schema を直接受け、legacy `log*` field や `pre_roll_count` / `post_roll_count` は扱わない。

---

## 9. 手動ツール

各手動ツールは `restoredefaultpath` / `genpath` を持たず、startup で復元された PATH を前提にする。
`matlab/tools/` は MATLAB path に追加せず、明示パスで実行する。

```matlab
run('matlab/tools/run_position_command_demo.m')
```

学生実験用の `matlab/experiment/exp0n_*.m` は Live Editor 用 `.m` を正本にする。
学生が調整する `Controller` / `Chirp` / 軌道条件はファイル上部に集約し、ローカル関数は置かない。
共通処理は `experiment.waveform` / `experiment.controller` / `experiment.analysis` / `experiment.plot` / `experiment.io` / `experiment.exp0n` に置く。

| スクリプト | 位置づけ |
|---|---|
| `matlab/tools/run_position_command_demo.m` | `virtualMotor.writeParams` を明示的に使う VM step response demo |
| `matlab/tools/run_si_demo.m` | `virtualMotor.writeParams` を明示的に使う VM デモ |
| `matlab/tools/run_verify_xar.m` | active contract (`852/853/351`) の接続・symbol・読み出し確認 |
| `matlab/tools/run_verify_virtual_motor.m` | VirtualMotorCore parameter symbol の確認 |
| `matlab/tools/run_ads_discovery_demo.m` | discovery 補助。必要なら `851` をローカル指定で probe する |
| `matlab/tools/run_check_logger_bin.m` | logger bin の直接検査 |

---

## 10. テスト

テスト実行:

```matlab
run('matlab/tests/run_tests.m')
```

主なテスト:

| ファイル | 役割 |
|---|---|
| `tests/unit/TestExperimentConfig.m` | 現行正本 runtime config |
| `tests/unit/TestMatlabEnvironment.m` | startup / path cache 管理 |
| `tests/unit/TestConnectionManager.m` | transport 構築 |
| `tests/unit/TestExperimentRunner.m` | 実行フロー本体 |
| `tests/unit/TestPreloadEval.m` | snake_case raw の replay 評価 |
| `tests/unit/TestRunPositionCommandDemoConfig.m` | demo の現行設定 |
| `tests/unit/TestEnvironmentConfig.m` | 環境固定値 |
| `tests/unit/TestRuntimeSymbols.m` | experiment symbol contract |
| `tests/unit/TestVirtualMotorSymbols.m` | VM symbol contract |
| `tests/contract/TestAdsSession.m` | AdsSession 契約 |
| `tests/contract/TestTransportContract.m` | transport 契約 |
