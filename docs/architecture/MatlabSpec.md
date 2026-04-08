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
| `+experiment` | `matlab/+experiment/` | プロジェクト固有の config / orchestration / 解析 |
| `+twincat_ads` | `matlab/+twincat_ads/` | 汎用 ADS 通信層 |
| `+twincat_ads/+internal` | `matlab/+twincat_ads/+internal/` | 非公開内部実装 |

依存方向は `+experiment -> +twincat_ads` のみとする。

---

## 3. 公開 API

現行の正本 API は以下のみ。

| クラス / 関数 | 役割 |
|---|---|
| `experiment.ExperimentConfig` | 実験実行の主 runtime config |
| `experiment.ControllerConfig` | ControllerCore 用の 4 段 biquad 設定 |
| `experiment.ConnectionManager` | `AdsSession` を使った transport 構築 |
| `experiment.ExperimentRunner` | 実験実行フロー本体 |
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
| `SystemConfig` | 環境固定値 |
| `ExperimentConfig` | 実行時設定 |
| `ControllerConfig` | ControllerCore パラメータ |
| `virtualMotor.PlantConfig` | VM パラメータ |

`ExperimentConfig` は canonical field のみを受理する。`ams_port` / `control_ams_port` / `module_ams_port` や legacy config object は受理しない。

---

## 5. `SystemConfig` の主要定数

| プロパティ | 値 | 説明 |
|---|---|---|
| `AMS_NET_ID` | `"192.168.10.3.1.1"` | XAR の AMS Net ID |
| `SEQ_PORT` | `853` | ExperimentSequencer |
| `CONTROL_PORT` | `852` | ModeManager |
| `MODULE_PORT` | `351` | C++ TcCOM 群 |
| `TASK_RATE_HZ` | `8000` | `VirtualMotorTask` 周波数 |
| `CTRL_PREFIX` | `"ControllerCore_Obj1 (Module1)."` | Controller parameter prefix |
| `MODE_FLAGS_SYMBOL` | `"GVL_MODE.modeFlags"` | start / stop 用 symbol |
| `LOGGER_FILE_RELEASED_SYMBOL` | `"GVL_MODE.loggerFileReleased"` | logger close 完了 |
| `LOGGER_ERROR_CODE_SYMBOL` | `"GVL_MODE.loggerErrorCode"` | logger エラー |
| `LOGGER_DEFAULT_FILE_PATH` | `"\\\\RAINYDAY\\ExperimentData\\experiment_logger.bin"` | logger bin 既定値 |
| `TABLE_MAX_N` | `100000` | テーブル長上限 |

active contract は `351/852/853` のみを使う。`851` は discovery 用にローカルで明示指定する場合だけ扱う。

---

## 6. 実行フロー

### 6.1 `ExperimentRunner.run(conn, cfg, ...)`

1. `ExperimentConfig` を normalize / validate
2. Symbol contract を必要に応じて検証
3. `ModeManagerControl` で `resetReq/resetAckCounter` handshake
4. `GVL_SEQ` へ `ref/ff/dist/tableLen/repeatCount` を書き込む
5. `ControllerCore` へ parameter を書き込む
6. `modeFlags` で servo enable -> experiment start
7. `GVL_MODE.experimentState` / `experimentActive` を監視
8. `GVL_MODE.loggerFileReleased` / `loggerErrorCode` を監視
9. logger `.bin` を読んで `out.raw` と `out.metrics` を返す

### 6.2 `ConnectionManager`

* `create(cfg)` は `seq`, `ctrl`, `module` をまとめて返す
* `create_plc_only(cfg)` は `seq`, `ctrl` だけを返す
* `from_transports(...)` は既存 transport を runner 契約へ束ねる

### 6.3 VM parameter write

* VM parameter は `ExperimentRunner` ではなく `virtualMotor.writeParams(conn, vm_cfg)` で明示的に書き込む
* `ExperimentConfig` は VM parameter や `write_plant_params` を保持しない
* step demo / SI demo は実行前に必要な VM preset を自分で適用する

---

## 7. 出力契約

### 7.1 正本出力

`ExperimentRunner.run(...)` の `out.raw` は snake_case を正本とする。

主フィールド:

* `seq`
* `ref_value`
* `ff_value`
* `dist_value`
* `control_input`
* `target_current`
* `position_act`

### 7.2 評価結果

`out.metrics` が唯一の評価出力であり、`out.eval` は存在しない。

* `metrics.sampling` は command/log の件数と sequence gap を返す
* `metrics.input_waveform`, `ff_waveform`, `dist_waveform` は replay 一致性を返す
* `metrics.torque_sum` は `control_input + dist_value == target_current` の整合性を返す
* `metrics.position_diag` は位置ログの利用可否と速度推定を返す

`preload_eval` は snake_case raw schema を直接受け、legacy `log*` field や `pre_roll_count` / `post_roll_count` は扱わない。

---

## 8. ルートスクリプト

| スクリプト | 位置づけ |
|---|---|
| `run_position_command_demo.m` | `virtualMotor.writeParams` を明示的に使う VM step response demo |
| `run_si_demo.m` | `virtualMotor.writeParams` を明示的に使う VM デモ |
| `run_verify_xar.m` | active contract (`852/853/351`) の接続・symbol・読み出し確認 |
| `run_verify_virtual_motor.m` | VirtualMotorCore parameter symbol の確認 |
| `run_ads_discovery_demo.m` | discovery 補助。必要なら `851` をローカル指定で probe する |
| `run_check_logger_bin.m` | logger bin の直接検査 |

---

## 9. テスト

テスト実行:

```matlab
run('matlab/tests/run_tests.m')
```

主なテスト:

| ファイル | 役割 |
|---|---|
| `tests/unit/TestExperimentConfig.m` | 現行正本 config |
| `tests/unit/TestConnectionManager.m` | transport 構築 |
| `tests/unit/TestExperimentRunner.m` | 実行フロー本体 |
| `tests/unit/TestPreloadEval.m` | snake_case raw の replay 評価 |
| `tests/unit/TestRunPositionCommandDemoConfig.m` | demo の現行設定 |
| `tests/unit/TestSystemConfig.m` | 環境固定値 |
| `tests/unit/TestRuntimeSymbols.m` | experiment symbol contract |
| `tests/unit/TestVirtualMotorSymbols.m` | VM symbol contract |
| `tests/contract/TestAdsSession.m` | AdsSession 契約 |
| `tests/contract/TestTransportContract.m` | transport 契約 |
