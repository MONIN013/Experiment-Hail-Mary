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

> Reset 制御は `modeFlags` パルス方式を廃止し、`GVL_MODE.resetReq` / `GVL_MODE.resetAckCounter` のハンドシェイク方式を使用する。  
> MATLAB は `resetReq=TRUE` を書き込み、`resetAckCounter` の更新を待つ。`resetReq` のクリアは TwinCAT 側が行う。

---

## §2 SystemConfig

**ファイル:** `+experiment/SystemConfig.m`

環境・ハードウェアに紐づく **不変パラメータと runtime config の default 値** を一元定義する。  
環境切替時はこのファイルのみ変更する。`SystemConfig` 自体は runtime config を保持せず、`RunConfig` / `PositionCommandConfig` に default を供給する。

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
| `MODE_FLAGS_SYMBOL` | string | `"GVL_MODE.modeFlags"` | modeFlags 正規書込み先シンボル |
| `LOG_N` | double | `200000` | GVL_SEQ_LOG リングバッファサイズ |
| `TABLE_MAX_N` | double | `100000` | refTable / ffTable / distTable 最大長 |

### Static メソッド

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `to_struct()` | struct | 全 Constant プロパティを struct で返す |
| `task_dt_ns()` | uint64 | タスク周期 [ns] (`1e9 / TASK_RATE_HZ`) |
| `run_defaults()` | struct | `RunConfig` 用の環境既定値を返す |
| `position_command_defaults()` | struct | `PositionCommandConfig` 用の環境既定値を返す |

---

## §3 設定所有

| クラス | 所有する責務 |
|---|---|
| `SystemConfig` | 環境固定の default 値のみ |
| `RunConfig` | `run_virtualmotor` / `VirtualMotorService` 用のフル実験 runtime config |
| `PositionCommandConfig` | `send_position_command` 用の PLC-only runtime config |

後方互換のための別経路や hidden fallback は提供しない。`send_position_command` の独自 parser は廃止し、`PositionCommandConfig` を唯一の正本とする。

---

## §4 ヘルパー関数 API

テーブル書込み・パラメータ書込み・ログ読出しを **機能単位** で分離した関数群。  
すべて `+experiment` パッケージ内に配置。

### §4.1 write_ref_table(transport, ref_profile, table_max_n)

位置指令テーブルを `GVL_SEQ.refTable` へ書込み、`GVL_SEQ.tableLen` をセットする。

- **transport:** `twincat_ads.IAdsTransport` (Port = `SEQ_PORT`)
- **ref_profile:** `double` 列ベクトル [N×1]
- **table_max_n:** caller が所有する上限値
- **制約:** `N ≤ table_max_n` でなければエラー

### §4.2 write_ff_table(transport, ff_profile, expected_len)

FF テーブルを `GVL_SEQ.ffTable` へ書込む。

- **expected_len:** caller が所有する期待長
- 長さ不一致時は error (`experiment:write_ff_table:lengthMismatch`)

### §4.3 write_dist_table(transport, dist_profile, expected_len)

外乱テーブルを `GVL_SEQ.distTable` へ書込む。

### §4.4 write_vm_params(transport, vm_param_symbol_prefix, params, task_dt_ns)

VirtualMotorCore の物理パラメータを Port 351 に書込む。

- **vm_param_symbol_prefix:** caller が所有する VM prefix
- **params:** struct with fields `m`, `d`, `rated_current`, `max_permille`, `tau_limit`, `vel_limit`
- **task_dt_ns:** caller が所有するタスク周期 [ns]

| 書込み先 | フィールド |
|---|---|
| `{VM_PREFIX}mass` | `params.m` |
| `{VM_PREFIX}damping` | `params.d` |
| `{VM_PREFIX}ratedTorque` | `params.rated_current` (VirtualMotorCore 内部例外。kt=1 前提で外部 `rated_current [A]` と同一値を書き込む) |
| `{VM_PREFIX}maxPermille` | `params.max_permille` |
| `{VM_PREFIX}tauLimit` | `params.tau_limit` |
| `{VM_PREFIX}velLimit` | `params.vel_limit` |
| `{vm_param_symbol_prefix}taskDtNs` | `task_dt_ns` |

### §4.5 write_controller_params(transport, controller_param_symbol_prefix, params)

ControllerCore の biquad フィルタパラメータ (4 段カスケード) を Port 351 に書込む。

- **controller_param_symbol_prefix:** caller が所有する Controller prefix
- **params:** struct with fields:
  - `pid_b0..pid_a2`, `lead_b0..lead_a2`, `notch_b0..notch_a2`, `reso_b0..reso_a2`
  - `enable_pid`, `enable_lead`, `enable_notch`, `enable_reso`

| ステージ | シンボル形式 | 係数フィールド名 |
|---|---|---|
| PID | `{controller_param_symbol_prefix}PIDParams.pidB0..pidA2` | pidBx / pidAx |
| Lead | `{controller_param_symbol_prefix}LeadParams.leadB0..leadA2` | leadBx / leadAx |
| Notch | `{controller_param_symbol_prefix}NotchParams.notchB0..notchA2` | notchBx / notchAx |
| Reso | `{controller_param_symbol_prefix}ResoParams.resoB0..resoA2` | resoBx / resoAx |

> **注:** 各ステージのフィールド名は C++ 構造体 (`ST_PID`, `ST_PhaseLead`, `ST_Notch`, `ST_Reso`) に準拠。

### §4.6 read_experiment_logs(transport, log_n)

`GVL_SEQ_LOG` からログを一括読出す（上位読取方式、非ストリーミング）。

- **transport:** `twincat_ads.IAdsTransport` (Port = `SEQ_PORT`)
- **log_n:** caller が所有する読出し上限
- **戻り値:** struct with fields:
  - `logSeq`, `logRefValue`, `logFfValue`, `logDistValue`
  - `logControlInput`, `logTargetCurrent`, `logPositionAct`
  - `logT` (uint64 → double), `logIdx`
  - `wrIdx`, `overflow`
- 読出し失敗時は warning + 空 struct 返却

---

## §5 RunConfig

**ファイル:** `+experiment/RunConfig.m`

単一実験の全条件を保持する Value Object。  
`from_varargin(...)` ファクトリで生成。

主要フィールド:

| フィールド | デフォルト | 説明 |
|---|---|---|
| `ams_net_id` | `SystemConfig.run_defaults()` | 接続先 AMS Net ID |
| `ams_port` | `SystemConfig.run_defaults()` | データ ADS ポート |
| `control_ams_port` | auto | 制御ポート (ams_port=853 のとき 852 に自動設定) |
| `module_ams_port` | `SystemConfig.run_defaults()` | TcCOM ポート |
| `vm_param_symbol_prefix` | `SystemConfig.run_defaults()` | VM パラメータプレフィクス |
| `controller_param_symbol_prefix` | `SystemConfig.run_defaults()` | Controller パラメータプレフィクス |
| `ref_profile` | (必須) | 位置指令テーブル |
| `ff_profile` | zeros(N,1) | FF テーブル |
| `dist_profile` | zeros(N,1) | 外乱テーブル |
| `task_dt_ns` | auto | タスク周期 [ns] |
| `save_path` | auto | 結果保存パス |

---

## §6 PositionCommandConfig

**ファイル:** `+experiment/PositionCommandConfig.m`

`send_position_command(...)` の唯一の runtime config。`SystemConfig.position_command_defaults()` から環境既定値を取得し、PLC-only 実行に必要な項目だけを保持する。

主要フィールド:

| フィールド | デフォルト | 説明 |
|---|---|---|
| `ams_net_id` | `SystemConfig.position_command_defaults()` | 接続先 AMS Net ID |
| `ams_port` | `SystemConfig.position_command_defaults()` | Sequencer/PLC ポート |
| `control_ams_port` | auto | `ams_port==SEQ_PORT` なら `CONTROL_PORT`、それ以外は `ams_port` |
| `ref_profile` | (必須) | 位置指令テーブル |
| `ff_profile` | zeros(N,1) | FF テーブル |
| `dist_profile` | zeros(N,1) | 外乱テーブル |
| `mode_flags_symbol` | `SystemConfig.position_command_defaults()` | modeFlags 正規シンボル |
| `repeat_count` | `1` | 同一テーブルの連続再生回数 |

---

## §7 デモスクリプト

`matlab/` ルートに 3 本のエントリスクリプトがある。  
いずれも先頭で `restoredefaultpath; addpath(genpath(base_dir));` により独立したパス環境を構築する。

---

### §7.1 run_position_command_demo.m

P 制御ステップ応答デモ（同一 trial を `N_REPEAT` 回連続再生）。

#### 処理フロー

1. `experiment.SystemConfig` から接続先 / ポート / タスクレートを取得
2. VirtualMotorCore 物理パラメータ (`vm_params`) を構築
3. Controller biquad パラメータ (`ctrl_params`) を構築（PID ステージのみ有効）
4. 指令波形 (`ref_profile`, `ff_profile`, `dist_profile`) を 1 trial 分生成
5. 3 本の ADS トランスポートを生成・接続 (SEQ=853, CTRL=852, MODULE=351)
6. `write_vm_params` / `write_controller_params` でパラメータを TcCOM に書込み (Port 351)
7. `send_position_command` で実験実行・完了待ち（`repeat_count=N_REPEAT`）
8. 結果を標準出力に表示し、位置応答・制御入力をプロット

#### 現在の設定パラメータ

| カテゴリ | パラメータ | 値 | 説明 |
|---|---|---|---|
| **指令** | `target_position_rad` | `0.25` rad | ステップ指令値 |
| **指令** | `step_duration_s` | `3.0` s | ステップ区間長 |
| **指令** | `pre_step_s` | `2.0` s | ステップ前ゼロ区間（リセット残留吸収） |
| **指令** | `hold_margin_s` | `0.50` s | `done_timeout_s` に加算するマージン |
| **指令** | `N_REPEAT` | `10` | 同一 trial の連続再生回数 |
| **VM** | `m` | `1.0` | 慣性モーメント [kg·m²] |
| **VM** | `d` | `6.0` | 粘性減衰係数 [N·m·s/rad] |
| **VM** | `rated_current` | `0.1` | 定格トルク電流 [A]（kt=1 前提、`ratedTorque` として書込み） |
| **VM** | `tau_limit` | `100.0` | トルク上限 [N·m] |
| **VM** | `vel_limit` | `10.0` | 速度上限 [rad/s] |
| **制御** | `Kp` (`pid_b0`) | `180` | P ゲイン |
| **制御** | 他ステージ | 無効 | `lead` / `notch` / `reso` は `enable_*=false` |

#### P 制御設計根拠

プラント:

$$G(s) = \frac{k_t}{m s^2 + d s} = \frac{0.1}{s^2 + 6s}$$

閉ループ:

$$T(s) = \frac{0.1 K_p}{s^2 + 6s + 0.1 K_p}$$

$K_p = 180$ のとき:

$$\omega_n = \sqrt{0.1 K_p} = \sqrt{18} = 4.24 \text{ rad/s}$$
$$\zeta = \frac{d}{2\sqrt{m \, k_t \, K_p}} = \frac{6}{2\sqrt{0.1 \times 180}} = 0.707$$

#### trial 境界抽出

`repeat_count > 1` のとき、`out.raw.logIdx` の負ジャンプで trial 境界を抽出する:

```matlab
idx_log  = out.raw.logIdx;
boundary = [0; find(diff(idx_log) < 0); numel(idx_log)];
```

`done_timeout_s` は `N_REPEAT * per_trial_s + hold_margin_s + 5.0` で計算される。

#### プロット

2-tile figure（`"P Control Position Demo"`）:

- **上段:** 位置応答 — `logRefValue` (青) vs `logPositionAct` (緑)
- **下段:** 制御出力 — `logControlInput` (紫) + `logTargetCurrent` (赤破線、存在する場合)

---

### §7.2 run_ads_discovery_demo.m

ADS シンボル列挙デモ。デプロイ後の symbol ブラウズや接続確認に使用する。

#### 設定パラメータ

| パラメータ | 値 | 説明 |
|---|---|---|
| `ams_net_id` | `"192.168.10.3.1.1"` | XAR の AMS Net ID |
| `ports` | `[851 852 853 351]` | 走査対象ポート |
| `connect_timeout_ms` | `1000` | ポートごとの接続タイムアウト [ms] |
| `top_level_only` | `false` | ネストシンボルも列挙 |
| `force_reload` | `true` | キャッシュを無視して再取得 |

#### 処理フロー

1. `SymbolBrowser.discover_ports_and_symbols` で全ポートのシンボルを一括取得
2. `t_ports`（接続ステータステーブル）を Status 別にカウントして表示
3. 自動生成プレフィクス（`_`、`TwinCAT_SystemInfoVarList`、`AlarmManager`）を除外し、ポートごとにユーザー定義シンボルのみ表示
4. 非 `ok` 行がある場合は Name / Status / ErrorMessage を別掲示

#### 標準出力例

```
[2026-03-02 HH:MM:SS] Starting ADS discovery
  AmsNetId=192.168.10.3.1.1, ports=[851, 852, 853, 351], timeout=1000 ms
[2026-03-02 HH:MM:SS] Discovery finished in X.XXX sec

=== Tports ===
  ...
=== Tports summary by Status ===
  ok: 4
=== Tsymbols (user-defined only) ===
--- Port 851 : N user rows (of M total, non-ok=0) ---
--- Port 852 : ...
--- Port 853 : ...
--- Port 351 : ...
```

---

### §7.3 run_verify_xar.m

XAR デプロイ済みバイナリの Health Check スクリプト。  
詳細検証内容は §8 を参照。実験実行前に必ずパスさせる。

#### 実行例（全 PASS 時）

```
=== XAR Verification: 192.168.10.3.1.1 ===
Ports: 851, 852, 853, 351

Check                                               Result  Detail
------------------------------------------------------------------------------------------
ADS connect port 851                                PASS
ADS connect port 852                                PASS
ADS connect port 853                                PASS
ADS connect port 351                                PASS
Symbol discovery (all ports)                        PASS    4 ports ok, NNN symbols
PLC required symbols (port 853)                     PASS    N probes OK
VM param symbols (port 351)                         PASS    N probes OK
Controller param symbols (port 351)                 PASS    N probes OK
Read tableLen (port 853)                            PASS    value=0
Read experimentState (port 852)                     PASS    value=0
Read LOG_N (port 853)                               PASS    value=200000
Read controller pidB0 (port 351)                    PASS    value=X.X
...
------------------------------------------------------------------------------------------
Total: 18 PASS, 0 FAIL (of 18)
```

FAIL がある場合は `warning: experiment:verify:failures` を発行する。

---

## §8 XAR 検証 (run_verify_xar.m)

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

## §9 命名規則・テスト

### 出力スキーマ互換方針

- MATLAB 公開出力スキーマ（`VirtualMotorService.run(...).raw`, `experiment.preload_eval(...)` の戻り値）は **正規フィールド名のみ** を提供する。
- 後方互換のための別名（互換エイリアス）は提供しない。
- 旧互換エイリアス `raw.log_i`, `raw.log_x`, `metrics.comparison.current_command_vs_plc` は使用不可。

### 命名規則

- **パッケージ:** `+experiment`, `+twincat_ads` (snake_case)
- **クラス:** PascalCase (`SystemConfig`, `RunConfig`, `PositionCommandConfig`)
- **関数:** snake_case (`write_ref_table`, `read_experiment_logs`)
- **テスト:** `Test` + PascalCase (`TestSystemConfig`, `TestWriteHelpers`)
- **struct フィールド:** snake_case (`pid_b0`, `tau_limit`)
- **ADS シンボル:** TwinCAT 側定義に準拠 (PascalCase struct + camelCase field)

### テストファイル

| ファイル | 対象 |
|---|---|
| `tests/unit/TestSystemConfig.m` | SystemConfig 定数・メソッド |
| `tests/unit/TestWriteHelpers.m` | helper 関数の explicit config 引数契約 |
| `tests/unit/TestVirtualMotorSymbols.m` | シンボル名契約 |
| `tests/unit/TestRunConfig.m` | RunConfig バリデーション |
| `tests/unit/TestPositionCommandConfig.m` | PositionCommandConfig バリデーション |
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
│   ├── PositionCommandConfig.m
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
