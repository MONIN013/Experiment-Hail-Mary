# MATLAB 実装仕様 — MatlabSpec

> **作成日:** 2026-02-28  
> **対象:** matlab/ 以下の全 MATLAB コード  
> **参照:** [ProjectArchitecture.md](ProjectArchitecture.md) / [TechnicalReference.md](TechnicalReference.md) / [NamingConvention.md](NamingConvention.md)

---

## §1 概要

MATLAB 層は **実験統括・パラメータ設定・ログ取得・解析** のみを担当する。  
リアルタイム制御は TwinCAT 側 (ExperimentSequencer / ControllerCore / VirtualMotorCore) に完全委譲し、  
MATLAB からは **ADS 通信**（.NET Interop 経由 `TcAdsClient`）でパラメータ注入とログ読み出しを行う。

### パッケージ構成

| パッケージ | パス | 役割 |
|---|---|---|
| `+experiment` | `matlab/+experiment/` | プロジェクト固有ロジック (SystemConfig, VirtualMotorService, send_position_command, ヘルパー群) |
| `+twincat_ads` | `matlab/+twincat_ads/` | 汎用 ADS ライブラリ (AdsTransport, IAdsTransport, SymbolBrowser)。プロジェクト非依存 |

依存方向: `+experiment` → `+twincat_ads` （逆依存なし）

---

## §2 SystemConfig

**ファイル:** `+experiment/SystemConfig.m`

環境・ハードウェアに紐づく **不変パラメータ** を `Constant` プロパティとして一元定義する。  
環境切替時はこのファイルのみ変更する。

### 定数一覧

| プロパティ | 型 | 値 | 説明 |
|---|---|---|---|
| `AMS_NET_ID` | string | `"192.168.10.3.1.1"` | XAR の AMS Net ID |
| `SEQ_PORT` | double | `853` | ExperimentSequencer (GVL_SEQ / GVL_SEQ_LOG) |
| `CONTROL_PORT` | double | `852` | StateMachineControl / ModeManager (GVL_MODE) |
| `DRIVER_PORT` | double | `851` | DriverAdapter (GVL_DRV) |
| `MODULE_PORT` | double | `351` | C++ TcCOM (ControllerCore / VirtualMotorCore / ExperimentLogger) |
| `TASK_RATE_HZ` | double | `1000` | VirtualMotorTask 周期 [Hz] |
| `VM_PREFIX` | string | `"VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter."` | VM パラメータシンボルプレフィクス |
| `CTRL_PREFIX` | string | `"ControllerCore_Obj1 (Module1)."` | Controller パラメータシンボルプレフィクス |
| `MODE_FLAGS_SYMBOL` | string | `"GVL_SEQ.modeFlags"` | modeFlags 書込み先シンボル |
| `LOG_N` | double | `200000` | GVL_SEQ_LOG リングバッファサイズ |
| `TABLE_MAX_N` | double | `100000` | refTable / ffTable / distTable 最大長 |

### Static メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `to_struct()` | struct | 全 Constant プロパティを struct で返す |
| `task_dt_ns()` | uint64 | タスク周期 [ns] (`1e9 / TASK_RATE_HZ`) |

---

## §3 ヘルパー関数 API

テーブル書込み・パラメータ書込み・ログ読出しを **機能単位** で分離した関数群。  
すべて `+experiment` パッケージ内に配置。

### §3.1 write_ref_table(transport, ref_profile)

位置指令テーブルを `GVL_SEQ.refTable` へ書込み、`GVL_SEQ.tableLen` をセットする。

- **transport:** `twincat_ads.IAdsTransport` (Port = `SEQ_PORT`)
- **ref_profile:** `double` 列ベクトル [N×1]
- **制約:** `N ≤ TABLE_MAX_N` でなければエラー

### §3.2 write_ff_table(transport, ff_profile)

FF テーブルを `GVL_SEQ.ffTable` へ書込む。

- `tableLen` は `write_ref_table` で設定済みであること。
- 長さ不一致時は warning (`experiment:write_ff_table:lengthMismatch`)

### §3.3 write_dist_table(transport, dist_profile)

外乱テーブルを `GVL_SEQ.distTable` へ書込む。

### §3.4 write_vm_params(transport, params)

VirtualMotorCore の物理パラメータを Port 351 に書込む。

- **params:** struct with fields `m`, `d`, `kt`, `tau_limit`, `vel_limit`
- `taskDtNs` は `SystemConfig.task_dt_ns()` から自動取得

| 書込み先 | フィールド |
|---|---|
| `{VM_PREFIX}mass` | `params.m` |
| `{VM_PREFIX}damping` | `params.d` |
| `{VM_PREFIX}torqueConstant` | `params.kt` |
| `{VM_PREFIX}tauLimit` | `params.tau_limit` |
| `{VM_PREFIX}velLimit` | `params.vel_limit` |
| `{VM_PREFIX}taskDtNs` | `SystemConfig.task_dt_ns()` |

### §3.5 write_controller_params(transport, params)

ControllerCore の biquad フィルタパラメータ (4 段カスケード) を Port 351 に書込む。

- **params:** struct with fields:
  - `pid_b0..pid_a2`, `lead_b0..lead_a2`, `notch_b0..notch_a2`, `reso_b0..reso_a2`
  - `enable_pid`, `enable_lead`, `enable_notch`, `enable_reso`

| ステージ | シンボル形式 | 係数フィールド名 |
|---|---|---|
| PID | `{CTRL_PREFIX}PIDParams.pidB0..pidA2` | pidBx / pidAx |
| Lead | `{CTRL_PREFIX}LeadParams.leadB0..leadA2` | leadBx / leadAx |
| Notch | `{CTRL_PREFIX}NotchParams.notchB0..notchA2` | notchBx / notchAx |
| Reso | `{CTRL_PREFIX}ResoParams.resoB0..resoA2` | resoBx / resoAx |

> **注:** 各ステージのフィールド名は C++ 構造体 (`ST_PID`, `ST_PhaseLead`, `ST_Notch`, `ST_Reso`) に準拠。

### §3.6 read_experiment_logs(transport)

`GVL_SEQ_LOG` からログを一括読出す（上位読取方式、非ストリーミング）。

- **transport:** `twincat_ads.IAdsTransport` (Port = `SEQ_PORT`)
- **戻り値:** struct with fields:
  - `logSeq`, `logRefValue`, `logFfValue`, `logDistValue`
  - `logControlInput`, `logTargetTorque`, `logPositionAct`
  - `logT` (uint64 → double), `logIdx`
  - `wrIdx`, `overflow`
- 読出し失敗時は warning + 空 struct 返却

---

## §4 RunConfig

**ファイル:** `+experiment/RunConfig.m`

単一実験の全条件を保持する Value Object。  
`from_varargin(...)` ファクトリで生成。

主要フィールド:

| フィールド | デフォルト | 説明 |
|---|---|---|
| `ams_net_id` | (必須) | 接続先 AMS Net ID |
| `ams_port` | 851 | データ ADS ポート |
| `control_ams_port` | auto | 制御ポート (ams_port=853 のとき 852 に自動設定) |
| `module_ams_port` | 351 | TcCOM ポート |
| `vm_param_symbol_prefix` | (必須) | VM パラメータプレフィクス |
| `controller_param_symbol_prefix` | (必須) | Controller パラメータプレフィクス |
| `ref_profile` | (必須) | 位置指令テーブル |
| `ff_profile` | zeros(N,1) | FF テーブル |
| `dist_profile` | zeros(N,1) | 外乱テーブル |
| `task_dt_ns` | auto | タスク周期 [ns] |
| `save_path` | auto | 結果保存パス |

---

## §5 デモスクリプト

### §5.1 run_position_command_demo.m

**P 制御ステップ応答デモ。**

- SystemConfig の全定数を使用
- 3 本の ADS トランスポート (SEQ=853, CTRL=852, MODULE=351) を生成
- `write_vm_params` + `write_controller_params` でパラメータ注入
- `send_position_command` で実験実行

#### P 制御設計根拠

プラント:

$$G(s) = \frac{k_t}{m s^2 + d s} = \frac{0.1}{s^2 + 6s}$$

閉ループ:

$$T(s) = \frac{0.1 K_p}{s^2 + 6s + 0.1 K_p}$$

$K_p = 180$ のとき:

$$\zeta = \frac{d}{2\sqrt{m k_t K_p}} = \frac{6}{2\sqrt{0.1 \times 180}} = 0.707$$
$$\omega_n = \sqrt{\frac{k_t K_p}{m}} = \sqrt{18} = 4.24 \text{ rad/s}$$

| パラメータ | 値 | 説明 |
|---|---|---|
| `Kp` | 180 | 比例ゲイン (biquad pid_b0) |
| target | 0.25 rad | ステップ指令値 |
| duration | 2.0 s | 観察時間 |
| vm: m, d, kt | 1.0, 6.0, 0.1 | VirtualMotorCore パラメータ |

### §5.2 run_ads_discovery_demo.m

ADS シンボル列挙デモ（SymbolBrowser 使用）。

### §5.3 run_verify_xar.m

XAR デプロイ済みバイナリの検証スクリプト (§6 参照)。

---

## §6 XAR 検証 (run_verify_xar.m)

192.168.10.3 の XAR に対し以下を自動検証する:

| # | 検証項目 | ポート |
|---|---|---|
| 1 | ADS 接続 (4 ポート) | 851, 852, 853, 351 |
| 2 | シンボル列挙 (SymbolBrowser) | 全ポート |
| 3 | PLC 必須シンボル存在 | 853 |
| 4 | VM パラメータシンボル存在 | 351 |
| 5 | Controller パラメータシンボル存在 | 351 |
| 6 | 基本スカラー読取 (tableLen, experimentState, LOG_N) | 853, 852 |
| 7 | Controller パラメータ読出し (pidB0, leadB0 等) | 351 |

実行結果は PASS/FAIL のサマリーテーブルとして表示。

---

## §7 命名規則・テスト

### 出力スキーマ互換方針

- MATLAB 公開出力スキーマ（`VirtualMotorService.run(...).raw`, `experiment.preload_eval(...)` の戻り値）は **正規フィールド名のみ** を提供する。
- 後方互換のための別名（互換エイリアス）は提供しない。
- 旧互換エイリアス `raw.log_i`, `raw.log_x`, `metrics.comparison.current_command_vs_plc` は使用不可。

### 命名規則

- **パッケージ:** `+experiment`, `+twincat_ads` (snake_case)
- **クラス:** PascalCase (`SystemConfig`, `VirtualMotorSymbols`, `RunConfig`)
- **関数:** snake_case (`write_ref_table`, `read_experiment_logs`)
- **テスト:** `Test` + PascalCase (`TestSystemConfig`, `TestWriteHelpers`)
- **struct フィールド:** snake_case (`pid_b0`, `tau_limit`)
- **ADS シンボル:** TwinCAT 側定義に準拠 (PascalCase struct + camelCase field)

### テストファイル

| ファイル | 対象 |
|---|---|
| `tests/unit/TestSystemConfig.m` | SystemConfig 定数・メソッド |
| `tests/unit/TestWriteHelpers.m` | write_ref_table, write_ff_table, write_dist_table, write_vm_params, write_controller_params, read_experiment_logs |
| `tests/unit/TestVirtualMotorSymbols.m` | シンボル名契約 |
| `tests/unit/TestRunConfig.m` | RunConfig バリデーション |
| `tests/unit/TestVirtualMotorService.m` | VirtualMotorService フロー (Mock) |
| `tests/unit/TestSendPositionCommand.m` | send_position_command フロー (Mock) |
| `tests/unit/TestModeManagerControl.m` | ModeManagerControl ヘルパー |
| `tests/unit/TestPreloadEval.m` | プリロード評価 |
| `tests/unit/TestSymbolTraversal.m` | シンボルトラバーサル |
| `tests/contract/TestTransportContract.m` | IAdsTransport 契約 |
| `tests/contract/TestSymbolBrowserContract.m` | SymbolBrowser 契約 |

テスト実行: `run('tests/run_tests.m')`

### ファイルツリー (matlab/)

```
matlab/
├── run_ads_discovery_demo.m
├── run_position_command_demo.m
├── run_verify_xar.m
├── +experiment/
│   ├── SystemConfig.m
│   ├── VirtualMotorSymbols.m
│   ├── VirtualMotorService.m
│   ├── ModeManagerControl.m
│   ├── RunConfig.m
│   ├── send_position_command.m
│   ├── write_ref_table.m
│   ├── write_ff_table.m
│   ├── write_dist_table.m
│   ├── write_vm_params.m
│   ├── write_controller_params.m
│   └── read_experiment_logs.m
├── +twincat_ads/
│   ├── AdsTransport.m
│   ├── IAdsTransport.m
│   └── SymbolBrowser.m
├── tests/
│   ├── run_tests.m
│   ├── unit/
│   ├── contract/
│   └── fixtures/
├── results/
└── simulink/
```
