# Matlab Refactor Plan

> **状態: 完了 (2026-07-03)**。本計画の Phase 1〜5 は実装済み。
> 現行仕様の正本は [MatlabSpec](../architecture/MatlabSpec.md) を参照。
> 本文書は履歴として保持する。
> 計画からの主な逸脱: 旧 API は deprecation ラッパーを残さず削除した。

> **位置づけ:** MATLAB 層の大規模改修計画  
> **対象読者:** MATLAB 実装者、改修計画のレビュー担当者  
> **更新条件:** 改修フェーズ、依存関係、完了条件が変わったとき  
> **関連文書:** [MatlabSpec](../architecture/MatlabSpec.md) / [NamingConvention](../operations/NamingConvention.md) / [OpenIssues](../status/OpenIssues.md)

## Plan: MATLAB大規模改修 — ADS Toolbox拡充・ライブラリ責任拡大・統一パラメタライズ

## TL;DR
MATLAB層を5フェーズで大規模改修する。`+twincat_ads/` を汎用ADS Toolboxとして拡充し、`+experiment/` にサブパッケージ群（波形生成・制御器設計・可視化）を追加、Config体系を構造化された単一階層に統合し、runスクリプトをライブラリ呼び出しの手続き的パイプラインに変換する。dist/FFを第一級市民として完全公開する。

---

## Phase 1: +twincat_ads/ ADS Toolbox 拡充

### Step 1.1 — 型マッピング拡充 (*独立*)
- `AdsTransport.net_types()` に `int16`, `int32`, `int64`, `string` を追加
- `IAdsTransport` の read/write メソッドが新型を透過的にサポートすることを保証
- **対象**: [+twincat_ads/AdsTransport.m](../../matlab/+twincat_ads/AdsTransport.m), [+twincat_ads/IAdsTransport.m](../../matlab/+twincat_ads/IAdsTransport.m)

### Step 1.2 — AdsSession 接続管理クラス (*独立*)
- 新規 `twincat_ads.AdsSession` クラスを作成
  - コンストラクタ: `AdsSession(ams_net_id, opts)` (opts: assembly path, reconnect policy)
  - `transport(port)` → 指定ポートの `AdsTransport` をlazy作成・接続・キャッシュして返す
  - `close()` → 全ポートのtransportをdisconnect
  - `onCleanup` でセッション破棄時に自動disconnect
  - 同一ポートの重複接続を自動回避
- **意図**: run scriptやライブラリ関数でのtransport手動管理を完全除去
- **対象**: 新規 `matlab/+twincat_ads/AdsSession.m`

### Step 1.3 — バッチ read/write API (*Step 1.1 依存*)
- `IAdsTransport` に `read_struct(symbol_map)` / `write_struct(symbol_map, values)` を追加
  - `symbol_map` = struct(field_name → {symbol, net_type}) のマップ
  - `read_struct` → 各フィールドをread_scalarして結果structを返す
  - `write_struct` → 各フィールドをwrite_scalarで一括書込み
- `AdsTransport` で実装
- **対象**: [+twincat_ads/IAdsTransport.m](../../matlab/+twincat_ads/IAdsTransport.m), [+twincat_ads/AdsTransport.m](../../matlab/+twincat_ads/AdsTransport.m)

### Step 1.4 — ADS Notification 対応 (*Step 1.1 依存*)
- 新規 `twincat_ads.AdsNotificationManager` クラス
  - `subscribe(transport, symbol, net_type, callback, cycle_time_ms)` → .NET `AddDeviceNotification()` をラップ
  - `unsubscribe(handle)` → `DeleteDeviceNotification()`
  - `unsubscribe_all()`
  - MATLABの `addlistener` / callback構造と互換
- **用途**: heartbeat監視、リアルタイム状態モニタリング（Phase 4以降で活用）
- **優先度**: 低。Phase 1の他ステップ完了後に着手
- **対象**: 新規 `matlab/+twincat_ads/AdsNotificationManager.m`

---

## Phase 2: Config体系の統合・構造化

### Step 2.1 — 構造化サブConfig定義 (*独立*)
新規value classを作成:

**`experiment.BiquadStage`** — 単一biquadフィルタ段
```
properties: b0=1, b1=0, b2=0, a1=0, a2=0, enable=false
static: passthrough() → enable=false 全係数デフォルト
static: from_struct(s) → フラット struct {b0,b1,b2,a1,a2,enable} から構築
method: to_flat(prefix) → prefix付きフラットstruct (ADS書込み用)
```

**`experiment.ControllerConfig`** — 4段biquadカスケード
```
properties: pid, lead, notch, reso (各 BiquadStage)
static: p_only(Kp) → pid.b0=Kp, pid.enable=true, 他bypass
static: from_flat_struct(s) → RunConfig互換フラットstructから構築
method: to_flat_struct() → write_controller_params 互換フラットstruct
```

**`experiment.PlantConfig`** — VM物理パラメータ
```
properties: m=0.01, d=0.1, rated_current=1.2, max_permille=0, tau_limit=5.0, vel_limit=100.0
static: from_struct(s) → struct から構築
method: to_struct() → write_vm_params 互換struct
```

- **対象**: 新規 `matlab/+experiment/BiquadStage.m`, `ControllerConfig.m`, `PlantConfig.m`

### Step 2.2 — ExperimentConfig 統合クラス (*Step 2.1 依存*)
`RunConfig` + `PositionCommandConfig` を統合した単一クラス:

```
experiment.ExperimentConfig
  properties:
    % 接続
    ams_net_id (string)
    seq_port, control_port, module_port (double)

    % プラント (構造化)
    plant (experiment.PlantConfig)

    % 制御器 (構造化)
    controller (experiment.ControllerConfig)

    % 波形 (第一級)
    ref_profile (:,1) double
    ff_profile  (:,1) double
    dist_profile (:,1) double

    % 実行制御
    repeat_count = 1
    task_rate_hz = 1000
    table_max_n = 100000
    wait_for_done = true
    done_timeout_s = 30.0
    reset_timeout_s = 5.0
    hold_seconds = 0

    % ハートビート
    host_heartbeat_enable = true
    host_heartbeat_period_s = 0.1

    % 出力
    save_path = ""
    read_logs = true
    validate_symbols = true

    % パラメータ書込み制御
    write_plant_params = true    % false → PLC-onlyモード (旧PositionCommandConfig相当)
    write_controller_params = true

  static methods:
    from_varargin(...) → フラットname-value引数から構築（後方互換）
    from_struct(s) → struct から構築
    defaults() → EnvironmentConfig からデフォルト値充填
```

- **注意**: `RunConfig` と `PositionCommandConfig` は deprecated にし、`ExperimentConfig` への移行ブリッジを提供
- 旧: `write_plant_params=true, write_controller_params=true` → full run
- 旧: `write_plant_params=false, write_controller_params=false` → position command only
- **対象**: 新規 `matlab/+experiment/ExperimentConfig.m`、既存 `RunConfig.m`, `PositionCommandConfig.m` をdeprecated化

### Step 2.3 — 波形自動パディング (*Step 2.2 依存*)
- `ExperimentConfig` のバリデーションで `ff_profile`, `dist_profile` の長さが `ref_profile` と不一致時に自動ゼロパディング
- 空配列 `[]` が渡された場合はゼロベクトルにフォールバック
- これにより従来の「ff_profile=zeros(N,1)」の明示が不要に

---

## Phase 3: +experiment/ ライブラリ機能拡充

### Step 3.1 — 波形生成サブパッケージ (*独立*)
新規 `+experiment/+waveform/` パッケージ:

| 関数 | シグネチャ | 説明 |
|------|-----------|------|
| `step` | `(amplitude, duration_s, rate_hz, "pre_step_s", 0)` | ステップ信号 (pre-step区間付き) |
| `sine` | `(amplitude, freq_hz, duration_s, rate_hz, "phase_rad", 0)` | 正弦波 |
| `chirp` | `(amplitude, f0_hz, f1_hz, duration_s, rate_hz)` | 線形チャープ |
| `ramp` | `(start_val, end_val, duration_s, rate_hz)` | 線形ランプ |
| `impulse` | `(amplitude, sample_idx, total_n)` | 離散インパルス |
| `constant` | `(value, duration_s, rate_hz)` | 定数値 |
| `concat` | `(varargin)` | 複数波形の結合 |
| `zeros_like` | `(ref_vec)` | 参照ベクトルと同長のゼロ |
| `pad` | `(vec, target_len, pad_value)` | 末尾パディング |

- **対象**: 新規 `matlab/+experiment/+waveform/` 以下の各.mファイル

### Step 3.2 — 制御器設計サブパッケージ (*Step 2.1 依存*)
新規 `+experiment/+controller/` パッケージ:

| 関数 | シグネチャ | 戻り値 |
|------|-----------|--------|
| `p_biquad` | `(Kp)` | `BiquadStage` (b0=Kp) |
| `pd_biquad` | `(Kp, Kd, Ts)` | `BiquadStage` (離散PD) |
| `pid_biquad` | `(Kp, Ki, Kd, Ts)` | `BiquadStage` (後退差分PID) |
| `notch_biquad` | `(center_hz, bandwidth_hz, Ts)` | `BiquadStage` |
| `lead_biquad` | `(wz, wp, gain, Ts)` | `BiquadStage` |
| `c2d_biquad` | `(num, den, Ts, "method", "tustin")` | `BiquadStage` (連続→離散変換) |

- **対象**: 新規 `matlab/+experiment/+controller/` 以下の各.mファイル

### Step 3.3 — 可視化サブパッケージ (*独立*)
新規 `+experiment/+plot/` パッケージ:

| 関数 | 用途 |
|------|------|
| `step_response(out, opts)` | ref vs position, error, current の3段表示 |
| `time_series(out, opts)` | 任意信号の時系列プロット |
| `current_signals(out, opts)` | controlInput, targetCurrent, ff, dist の重畳表示 |
| `waveform_comparison(out, opts)` | 入力波形 vs ログ波形の比較 |

- 現在 `run_position_command_demo.m` に埋め込まれているプロット処理をここに移設
- **対象**: 新規 `matlab/+experiment/+plot/` 以下の各.mファイル

### Step 3.4 — ConnectionManager (*Step 1.2 依存*)
新規 `experiment.ConnectionManager` クラス:

```
static create(opts) → struct(session, seq, ctrl, module)
  - AdsSession を作成し、EnvironmentConfig のポート定義で接続
  - seq    = session.transport(env.seq_port)
  - ctrl   = session.transport(env.control_port)
  - module = session.transport(env.module_port)
  - cleanup = onCleanup で session.close()

static create_plc_only(opts) → struct(session, seq, ctrl)
  - Module port 省略版 (send_position_command 向け)
```

- **対象**: 新規 `matlab/+experiment/ConnectionManager.m`

### Step 3.5 — ExperimentRunner 統合 (*Step 2.2, 3.4 依存*)
`VirtualMotorService.run` と `send_position_command` のロジックを統合:

新規 `experiment.ExperimentRunner` クラス:
```
methods (Static):
  out = run(conn, cfg)
    % 1. Symbol解決・検証
    % 2. cfg.write_plant_params → experiment.write_vm_params()
    % 3. cfg.write_controller_params → experiment.write_controller_params()
    % 4. リセットシーケンス
    % 5. テーブル書込み (ref, ff, dist) — ff/dist は cfg からそのまま
    % 6. サーボ有効化 → 実験開始
    % 7. 完了待機 (heartbeat付き)
    % 8. シャットダウン
    % 9. ログ読出し + 評価
    % 10. 結果struct返却
```

- `send_position_command` と `VirtualMotorService.run` の両方を内部的にこれに委譲
- transport管理は `ConnectionManager` に完全委任
- **対象**: 新規 `matlab/+experiment/ExperimentRunner.m`

---

## Phase 4: run スクリプトの手続き化

### Step 4.1 — run_step_response.m (*Phase 2, 3 依存*)
`run_position_command_demo.m` を置き換え:

```matlab
%% Step Response Demo
cfg = experiment.ExperimentConfig.defaults();
cfg.plant = experiment.PlantConfig(m=0.02, d=0.2, rated_current=1.2, tau_limit=2.4, vel_limit=2*pi*60);
cfg.controller = experiment.ControllerConfig.p_only(1.0);
cfg.ref_profile = experiment.waveform.step(0.25, 1.0, cfg.env.task_rate_hz, "pre_step_s", 1.0);
cfg.repeat_count = 1;

conn = experiment.ConnectionManager.create();
out = experiment.ExperimentRunner.run(conn, cfg);

experiment.plot.step_response(out);
fprintf("Done=%d, RMSE=%.6f\n", out.host.done, out.metrics.input_waveform.rmse);
```

- 現在の ~220行 → ~15行
- **対象**: 新規 `matlab/tools/run_step_response.m`、旧 `matlab/tools/run_position_command_demo.m` をdeprecated

### Step 4.2 — run_ff_demo.m (*Phase 2, 3 依存, Step 4.1 と並行可*)
FF (フィードフォワード) を使用するデモ:

```matlab
cfg = experiment.ExperimentConfig.defaults();
cfg.plant = experiment.PlantConfig(m=0.02, d=0.2, rated_current=1.2);
cfg.controller = experiment.ControllerConfig.p_only(1.0);
cfg.ref_profile = experiment.waveform.sine(0.1, 2.0, 5.0, cfg.env.task_rate_hz);
cfg.ff_profile = compute_ff_from_ref(cfg.ref_profile, cfg.plant, cfg.env.task_rate_hz);
% ↑ 加速度補償: ff = m * d²ref/dt² (離散微分)

conn = experiment.ConnectionManager.create();
out = experiment.ExperimentRunner.run(conn, cfg);
experiment.plot.waveform_comparison(out);
```

- **対象**: 新規 `matlab/tools/run_ff_demo.m`

### Step 4.3 — run_dist_rejection_demo.m (*Phase 2, 3 依存, Step 4.1 と並行可*)
外乱抑圧性能テストのデモ:

```matlab
cfg = experiment.ExperimentConfig.defaults();
cfg.plant = experiment.PlantConfig(m=0.02, d=0.2, rated_current=1.2);
cfg.controller = experiment.ControllerConfig.p_only(1.0);
cfg.ref_profile = experiment.waveform.constant(0.0, 5.0, cfg.env.task_rate_hz);
cfg.dist_profile = experiment.waveform.step(0.5, 3.0, cfg.env.task_rate_hz, "pre_step_s", 1.0);
% ↑ 静止状態にステップ外乱を注入

conn = experiment.ConnectionManager.create();
out = experiment.ExperimentRunner.run(conn, cfg);
experiment.plot.current_signals(out);
```

- **対象**: 新規 `matlab/tools/run_dist_rejection_demo.m`

### Step 4.4 — 既存スクリプトの移行 (*Phase 3 依存*)
- `run_verify_xar.m` → `ConnectionManager.create()` を使用するよう更新
- `run_ads_discovery_demo.m` → `AdsSession` を使用するよう更新
- `run_check_logger_bin.m` → 変更なし (ADS非依存)

---

## Phase 5: テスト・クリーンアップ・OpenIssues 解消

### Step 5.1 — 新規ユニットテスト (*各Phase 完了後*)
| テスト | 対象 |
|--------|------|
| `TestBiquadStage` | BiquadStage 構築・変換・バリデーション |
| `TestControllerConfig` | p_only, from_flat_struct 相互変換 |
| `TestPlantConfig` | struct 変換 |
| `TestExperimentConfig` | defaults, from_varargin, ff/dist 自動パディング |
| `TestWaveformGenerators` | step/sine/chirp/concat の出力値・長さ検証 |
| `TestControllerDesign` | p/pd/pid_biquad の係数計算、c2d_biquad 検証 |
| `TestConnectionManager` | Mock transport 使用のポートルーティング検証 |
| `TestExperimentRunner` | MockTransport でのフルオーケストレーション (VirtualMotorServiceテストから移行) |

### Step 5.2 — OpenIssues 解消 (*Phase 2, 3 依存*)
- **#5**: `out.raw` フィールド名を `ref_value`, `ff_value`, `dist_value`, `control_input`, `target_current`, `position_act`, `seq` にリネーム (ExperimentRunner の出力で実施)
- **#6**: `preload_eval.m` の `pre_roll_count=0`, `post_roll_count=0` 除去
- **#7**: `TestPreloadEval.m` の `log_overflow` テストフィクスチャ削除
- **#9**: `AdsTransport.m` の uint64 フォールバック — Step 1.1 の型拡充で再評価・削除判断

### Step 5.3 — 既存コードdeprecation (*Phase 4 完了後*)
- `RunConfig.m` → `ExperimentConfig` へのアダプタ追加、deprecation warning
- `PositionCommandConfig.m` → 同様
- `VirtualMotorService.m` → `ExperimentRunner` への委譲ラッパーに変更
- `send_position_command.m` → `ExperimentRunner.run` への委譲ラッパーに変更
- `run_virtualmotor.m` → `ExperimentRunner` 使用に更新

---

## Relevant Files

### 変更対象 (既存)
- `matlab/+twincat_ads/IAdsTransport.m` — batch API追加 (Step 1.3)
- `matlab/+twincat_ads/AdsTransport.m` — 型拡充 + batch実装 (Step 1.1, 1.3)
- `matlab/+config/EnvironmentConfig.m` — 環境固定値 (Step 2.2)
- `matlab/+experiment/preload_eval.m` — pre/post_roll 除去 (Step 5.2)
- `matlab/+experiment/RunConfig.m` — deprecated化 (Step 5.3)
- `matlab/+experiment/PositionCommandConfig.m` — deprecated化 (Step 5.3)
- `matlab/+experiment/VirtualMotorService.m` — 委譲ラッパー化 (Step 5.3)
- `matlab/+experiment/send_position_command.m` — 委譲ラッパー化 (Step 5.3)
- `matlab/tools/run_position_command_demo.m` — deprecated化 (Step 4.1)
- `matlab/tools/run_verify_xar.m` — ConnectionManager使用に更新 (Step 4.4)
- `matlab/tools/run_ads_discovery_demo.m` — AdsSession使用に更新 (Step 4.4)
- `matlab/tests/unit/TestPreloadEval.m` — フィクスチャ修正 (Step 5.2)

### 新規作成
- `matlab/+twincat_ads/AdsSession.m` (Step 1.2)
- `matlab/+twincat_ads/AdsNotificationManager.m` (Step 1.4)
- `matlab/+experiment/BiquadStage.m` (Step 2.1)
- `matlab/+experiment/ControllerConfig.m` (Step 2.1)
- `matlab/+experiment/PlantConfig.m` (Step 2.1)
- `matlab/+experiment/ExperimentConfig.m` (Step 2.2)
- `matlab/+experiment/ConnectionManager.m` (Step 3.4)
- `matlab/+experiment/ExperimentRunner.m` (Step 3.5)
- `matlab/+experiment/+waveform/step.m` (Step 3.1)
- `matlab/+experiment/+waveform/sine.m` (Step 3.1)
- `matlab/+experiment/+waveform/chirp.m` (Step 3.1)
- `matlab/+experiment/+waveform/ramp.m` (Step 3.1)
- `matlab/+experiment/+waveform/impulse.m` (Step 3.1)
- `matlab/+experiment/+waveform/constant.m` (Step 3.1)
- `matlab/+experiment/+waveform/concat.m` (Step 3.1)
- `matlab/+experiment/+waveform/zeros_like.m` (Step 3.1)
- `matlab/+experiment/+waveform/pad.m` (Step 3.1)
- `matlab/+experiment/+controller/p_biquad.m` (Step 3.2)
- `matlab/+experiment/+controller/pd_biquad.m` (Step 3.2)
- `matlab/+experiment/+controller/pid_biquad.m` (Step 3.2)
- `matlab/+experiment/+controller/notch_biquad.m` (Step 3.2)
- `matlab/+experiment/+controller/lead_biquad.m` (Step 3.2)
- `matlab/+experiment/+controller/c2d_biquad.m` (Step 3.2)
- `matlab/+experiment/+plot/step_response.m` (Step 3.3)
- `matlab/+experiment/+plot/time_series.m` (Step 3.3)
- `matlab/+experiment/+plot/current_signals.m` (Step 3.3)
- `matlab/+experiment/+plot/waveform_comparison.m` (Step 3.3)
- `matlab/tools/run_step_response.m` (Step 4.1)
- `matlab/tools/run_ff_demo.m` (Step 4.2)
- `matlab/tools/run_dist_rejection_demo.m` (Step 4.3)
- テスト: 8本 (Step 5.1)

---

## Verification

1. **Phase 1 検証**: `TestTransportContract` に型拡充テスト追加。`TestAdsSession` で接続ライフサイクル検証。MockTransport で `read_struct`/`write_struct` 往復テスト
2. **Phase 2 検証**: `TestExperimentConfig.from_varargin(...)` が旧 `RunConfig` / `PositionCommandConfig` と同等のconfig生成を確認。`BiquadStage.to_flat()` ↔ `from_flat_struct()` 往復テスト
3. **Phase 3 検証**: `TestWaveformGenerators` で波形長・値域・連結の正確性。`TestControllerDesign` で既知のKp→biquad変換、c2d_biquad のMATLAB `c2d()` 結果との比較
4. **Phase 4 検証**: `run_step_response.m` をMockTransportで実行し、出力struct構造が旧 `run_position_command_demo.m` と同等であること。XAR環境での統合テスト
5. **Phase 5 検証**: `run_tests.m` で全テストパス。deprecated関数がwarning付きで正常動作

---

## Decisions

- **単一Config方針**: `RunConfig` + `PositionCommandConfig` は `ExperimentConfig` に統合。`write_plant_params` / `write_controller_params` フラグで用途を切替え
- **サブパッケージ構造**: `+waveform/`, `+controller/`, `+plot/` はMATLABネストパッケージ (`experiment.waveform.step()` 形式)
- **後方互換**: 旧API (`RunConfig`, `send_position_command` 等) は即座に削除せずdeprecation warningを付けて委譲ラッパー化
- **ADS Notification**: 優先度低。Phase 1の他ステップ完了後に着手。現行heartbeat監視で十分機能中
- **名前規約**: MATLAB プロパティ・ローカル変数は `snake_case`、クラス名は `PascalCase`、パッケージは小文字 ([NamingConvention](../operations/NamingConvention.md) 準拠)
- **out.raw フィールド名変更**: `logRefValue` → `ref_value` 等。ExperimentRunner で新形式、旧API は互換フィールドを併存
- **スコープ外**: Simulink統合、バッチ実験自動化、JSON/YAMLコンフィグファイル読込み (将来拡張)
