# Matlab Spec

> **位置づけ:** `matlab/` 以下の実装仕様と責務分離の正本  
> **対象読者:** MATLAB 実装者、ADS 連携の保守担当者  
> **更新条件:** MATLAB 側 API、責務境界、パッケージ構成、TwinCAT との契約が変わったとき  
> **関連文書:** [ProjectOverview](../overview/ProjectOverview.md) / [SystemArchitecture](./SystemArchitecture.md) / [TechnicalReference](./TechnicalReference.md) / [NamingConvention](../operations/NamingConvention.md)

---

## 1. 概要

MATLAB 層は **実験統括・パラメータ設定・ログ取得・解析** を担当する。リアルタイム制御は TwinCAT 側に完全委譲し、MATLAB は ADS とファイル I/O を使って以下を行う。

* `GVL_SEQ` へのテーブル書込み
* `GVL_MODE` による reset / start / stop / 状態監視
* ControllerCore / VirtualMotorCore のパラメータ注入
* logger `.bin` の読出しと解析

---

## 2. パッケージ構成

| パッケージ | パス | 役割 |
|---|---|---|
| `+experiment` | `matlab/+experiment/` | プロジェクト固有の config / orchestration / 解析 |
| `+twincat_ads` | `matlab/+twincat_ads/` | 汎用 ADS 通信層 |
| `+twincat_ads/+internal` | `matlab/+twincat_ads/+internal/` | 非公開内部実装 |

依存方向は `+experiment -> +twincat_ads` のみとする。

---

## 3. 主 API と責務

### 3.1 現行の正本 API

| クラス / 関数 | 役割 |
|---|---|
| `experiment.ExperimentConfig` | 現行の主 runtime config |
| `experiment.PlantConfig` | VirtualMotorCore 用の物理パラメータ |
| `experiment.ControllerConfig` | ControllerCore 用の 4 段 biquad 設定 |
| `experiment.ConnectionManager` | `AdsSession` を使った transport 構築 |
| `experiment.ExperimentRunner` | 実験実行フロー本体 |
| `twincat_ads.AdsSession` | AMS Net ID 単位の transport キャッシュ |
| `twincat_ads.AdsTransport` | TwinCAT ADS 実装 |
| `twincat_ads.SymbolBrowser` | シンボル列挙 / 契約検証 |

### 3.2 互換ブリッジとして残る API

| クラス / 関数 | 現在の位置づけ |
|---|---|
| `experiment.RunConfig` | legacy adapter。`ExperimentConfig` へ橋渡し可能 |
| `experiment.PositionCommandConfig` | legacy adapter。`send_position_command` 用の互換入力 |
| `experiment.send_position_command` | `PositionCommandConfig -> ExperimentConfig -> ExperimentRunner` の entrypoint |
| `experiment.VirtualMotorService` | `ExperimentRunner` への委譲ラッパー |
| `experiment.run_virtualmotor` | connection 構築 + wrapper 呼出し |

> `send_position_command` は `PositionCommandConfig` 直結の独自実装ではなく、内部で `ExperimentConfig` に橋渡しして `ExperimentRunner.run(...)` を呼ぶ。

---

## 4. Config 所有

| 所有者 | 責務 |
|---|---|
| `SystemConfig` | 環境固定値と default 値 |
| `ExperimentConfig` | 現行の正本 runtime config |
| `PlantConfig` | VM パラメータ |
| `ControllerConfig` | ControllerCore パラメータ |
| `RunConfig` | legacy bridge |
| `PositionCommandConfig` | legacy bridge |

### 4.1 prefix の扱い

現行の主実行経路では、VM / Controller の symbol prefix は caller override を前提にしない。`ExperimentRunner` は `SystemConfig.VM_PREFIX` と `SystemConfig.CTRL_PREFIX` を使用する。

---

## 5. `SystemConfig` の主要定数

| プロパティ | 値 | 説明 |
|---|---|---|
| `AMS_NET_ID` | `"192.168.10.3.1.1"` | XAR の AMS Net ID |
| `SEQ_PORT` | `853` | ExperimentSequencer |
| `CONTROL_PORT` | `852` | ModeManager |
| `MODULE_PORT` | `351` | C++ TcCOM 群 |
| `DRIVER_PORT` | `851` | 互換 / discovery 用に残る legacy 定数 |
| `TASK_RATE_HZ` | `8000` | `VirtualMotorTask` 周波数 |
| `VM_PREFIX` | `"VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter."` | VM parameter prefix |
| `CTRL_PREFIX` | `"ControllerCore_Obj1 (Module1)."` | Controller parameter prefix |
| `MODE_FLAGS_SYMBOL` | `"GVL_MODE.modeFlags"` | start / stop 用 symbol |
| `LOGGER_FILE_RELEASED_SYMBOL` | `"GVL_MODE.loggerFileReleased"` | logger close 完了 |
| `LOGGER_ERROR_CODE_SYMBOL` | `"GVL_MODE.loggerErrorCode"` | logger エラー |
| `LOGGER_DEFAULT_FILE_PATH` | `"\\\\RAINYDAY\\ExperimentData\\experiment_logger.bin"` | 現行 logger bin 既定値 |
| `TABLE_MAX_N` | `100000` | テーブル長上限 |

> `DRIVER_PORT` は現行 orchestrator の正本経路では使わないが、discovery / verify 補助スクリプトとの互換のため残っている。

---

## 6. ヘルパー関数

以下は `+experiment` の低レベル helper として維持する。

| 関数 | 役割 |
|---|---|
| `write_ref_table` | `GVL_SEQ.refTable` 書込み |
| `write_ff_table` | `GVL_SEQ.ffTable` 書込み |
| `write_dist_table` | `GVL_SEQ.distTable` 書込み |
| `write_vm_params` | `VirtualMotor1Parameter.*` 書込み |
| `write_controller_params` | `ControllerCore_*Params.*` 書込み |
| `read_logger_bin` | fixed-size logger bin の読出し |
| `read_latest_logger_bin` | 共有フォルダ上の最新 valid bin 探索 |
| `resolve_demo_log_source` | demo 用ログソース選択 |
| `preload_eval` | ログ整合性・再生評価 |

---

## 7. 実行フロー

### 7.1 `ExperimentRunner.run(conn, cfg, ...)`

1. `ExperimentConfig` を正規化 / validate
2. Symbol contract を必要に応じて検証
3. `ModeManagerControl` で `resetReq/resetAckCounter` handshake
4. `GVL_SEQ` へ `ref/ff/dist/tableLen/repeatCount` を書込む
5. `ControllerCore` / `VirtualMotorCore` へ parameter を書込む
6. `modeFlags` で servo enable -> experiment start
7. `GVL_MODE.experimentState` / `experimentActive` を監視
8. `GVL_MODE.loggerFileReleased` / `loggerErrorCode` を監視
9. logger `.bin` を読んで `out.raw`, `out.metrics`, `out.eval` を返す

### 7.2 `send_position_command(...)`

* `PositionCommandConfig` を受理する
* 内部で `ExperimentConfig` に変換する
* `write_plant_params=false`, `write_controller_params=false` 相当の PLC-only 実行へ橋渡しする

---

## 8. 出力契約

### 8.1 正本出力

`ExperimentRunner.run(...)` / `send_position_command(...)` の `out.raw` は snake_case を正本とする。

主フィールド:

* `seq`
* `ref_value`
* `ff_value`
* `dist_value`
* `control_input`
* `target_current`
* `position_act`

### 8.2 互換ブリッジ

現行実装は `preload_eval` 互換のために `to_legacy_raw(...)` / `to_legacy_eval(...)` を内部で使い、`out.eval` を併せて返す。したがって **legacy bridge はまだ残っている**。新規コードは `out.raw` / `out.metrics` を使う。

---

## 9. ルートスクリプト

### 9.1 `run_position_command_demo.m`

現行デモは `ExperimentConfig` と `ExperimentRunner` を使う。主な設定値は以下。

| パラメータ | 値 |
|---|---|
| `target_position_rad` | `0.25` |
| `step_duration_s` | `3.0` |
| `pre_step_s` | `3.0` |
| `hold_margin_s` | `0.50` |
| `N_REPEAT` | `1` |
| `Kp` | `10` |
| `plant.m` | `0.02` |
| `plant.d` | `0.2` |
| `plant.rated_current` | `1.2` |
| `plant.tau_limit` | `2.4` |
| `plant.vel_limit` | `2*pi*60` |

処理フロー:

1. `ExperimentConfig.defaults()` 取得
2. plant / controller / waveform を設定
3. 3 transport 接続
4. `ExperimentRunner.run(conn, cfg)`
5. `read_latest_logger_bin` + `resolve_demo_log_source`
6. 結果表示と plot

### 9.2 `run_ads_discovery_demo.m`

* 現行スクリプトは `ports = [851 852 853 351]` を走査する
* `851` は compatibility / discovery 用に残る
* active orchestrator の正本経路は `852`, `853`, `351`

### 9.3 `run_verify_xar.m`

現行スクリプトが検証するのは以下。

1. `ports = [sys.DRIVER_PORT, sys.CONTROL_PORT, sys.SEQ_PORT, sys.MODULE_PORT]` への ADS 接続
2. 全ポート symbol discovery
3. `VirtualMotorSymbols.from_defaults()` による PLC 必須 symbol 検証
4. VM parameter symbol 検証
5. Controller parameter symbol 検証
6. 基本 scalar 読出し
   - `GVL_SEQ.tableLen`
   - `GVL_MODE.experimentState`
7. Controller parameter 読出し
   - `pidB0`
   - `leadB0`
   - `notchB0`
   - `resoB0`
   - `enablePid`

### 9.4 `run_check_logger_bin.m`

`read_logger_bin(...)` を使って logger file を直接検査する補助スクリプト。

### 9.5 `run_si_demo.m`

`ExperimentConfig` / `ExperimentRunner` と解析 helper を使う SIL デモ。`run_position_command_demo.m` とは別に維持する。

---

## 10. テスト

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
| `tests/unit/TestRunConfig.m` | legacy bridge |
| `tests/unit/TestPositionCommandConfig.m` | legacy bridge |
| `tests/unit/TestVirtualMotorService.m` | wrapper 委譲確認 |
| `tests/unit/TestSendPositionCommand.m` | entrypoint 検証 |
| `tests/unit/TestRunPositionCommandDemoConfig.m` | demo の現行設定 |
| `tests/unit/TestRunPositionCommandDemoLoggerSelection.m` | demo の logger 選択 |
| `tests/unit/TestRunSiDemoConfig.m` | SI demo |
| `tests/unit/TestSystemConfig.m` | 環境固定値 |
| `tests/unit/TestVirtualMotorSymbols.m` | symbol contract |
| `tests/contract/TestAdsSession.m` | AdsSession 契約 |
| `tests/contract/TestTransportContract.m` | transport 契約 |
| `tests/contract/TestSymbolBrowserContract.m` | symbol browser 契約 |

---

## 11. ファイルツリー

```text
matlab/
├── run_ads_discovery_demo.m
├── run_check_logger_bin.m
├── run_position_command_demo.m
├── run_si_demo.m
├── run_verify_xar.m
├── +experiment/
│   ├── ConnectionManager.m
│   ├── ControllerConfig.m
│   ├── ExperimentConfig.m
│   ├── ExperimentRunner.m
│   ├── ModeManagerControl.m
│   ├── PlantConfig.m
│   ├── PositionCommandConfig.m
│   ├── RunConfig.m
│   ├── SystemConfig.m
│   ├── VirtualMotorService.m
│   ├── VirtualMotorSymbols.m
│   ├── preload_eval.m
│   ├── read_latest_logger_bin.m
│   ├── read_logger_bin.m
│   ├── resolve_demo_log_source.m
│   ├── run_virtualmotor.m
│   ├── send_position_command.m
│   ├── write_controller_params.m
│   ├── write_dist_table.m
│   ├── write_ff_table.m
│   ├── write_ref_table.m
│   └── write_vm_params.m
├── +twincat_ads/
│   ├── AdsSession.m
│   ├── AdsTransport.m
│   ├── IAdsTransport.m
│   ├── SymbolBrowser.m
│   └── +internal/
│       └── SymbolTraversal.m
└── tests/
    ├── run_tests.m
    ├── contract/
    ├── fixtures/
    └── unit/
```
