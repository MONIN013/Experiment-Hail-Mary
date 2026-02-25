# 各モジュール実験準備状況（Mapping 除外）— 2026-02-25

> **目的:** 各モジュールのコード実装が実験可能な状態かを Mapping（GUI 作業）以外の観点で整理する。

---

## 結論

| モジュール | 実装方式 | コード状態 | 判定 |
|---|---|---|---|
| **ControllerCore** | C++ TcCOM | ✅ 完了 | 実験可能 |
| **VirtualMotorCore** | C++ TcCOM | ✅ 完了 | 実験可能 |
| **ExperimentLogger** | C++ TcCOM | ✅ 完了（Phase 3 先行） | 実験可能（統合は Phase 3） |
| **DriverAdapter** | PLC ST | ✅ 完了 | 実験可能 |
| **ExperimentSequencer** | PLC ST | ⚠ ほぼ完了 | **AT リンク不足 — 要修正** |
| **StateMachineControl** | PLC ST | ⚠ ほぼ完了 | **AT リンク不足 — 要修正** |

---

## 1. ControllerCore（C++ TcCOM）— ✅ 実験可能

### I/O

| 方向 | ポート | 型 | 状態 |
|---|---|---|---|
| IN | `ref_value` | `double` | ✔ |
| IN | `ff_value` | `double` | ✔ |
| IN | `position_act` | `double` | ✔ |
| OUT | `control_input` | `double` | ✔ |
| OUT | `error` | `double` | ✔ |

### 内部処理

- 誤差計算: $e = \text{ref\_value} - \text{position\_act}$
- FB チェーン: PID → Lead → Notch → Reso（各 biquad, Transposed Direct Form II）
- 各ブロック enable/bypass 切替 + NaN/Inf ガード
- FF 加算: $\text{control\_input} = u_{fb} + \text{ff\_value}$
- 状態遷移時にフィルタ内部状態 (s1/s2) をゼロクリア

### Tunable Parameters（ADS 注入）

`ST_PID`, `ST_PhaseLead`, `ST_Notch`, `ST_Reso` の biquad 係数 + `ST_FilterEnable` の enable フラグ。

### 注意点

- 各フィルタブロックのパラメータ構造体はブロック固有名称: `ST_PID`(`PID_b0` 等), `ST_PhaseLead`(`lead_b0` 等), `ST_Notch`(`notch_b0` 等), `ST_Reso`(`reso_b0` 等)。ArchitectureSpec §2.3 を実装に合わせて更新済み。

---

## 2. VirtualMotorCore（C++ TcCOM）— ✅ 実験可能

### I/O

2 軸構成。Phase 1 では Axis 0 のみ使用。

| 方向 | ポート（Axis 0） | 型 |
|---|---|---|
| IN | `VirtualMotor1Inputs.current_in` | `double` |
| IN | `controlword1` | `USHORT` |
| OUT | `VirtualMotor1Outputs.position_out` | `double` |
| OUT | `VirtualMotor1Outputs.velocity_out` | `double` |
| OUT | `statusword1` | `USHORT` |

### 内部処理

- **CiA 402 ドライブ状態機械:** `SWITCH_ON_DISABLED → READY_TO_SWITCH_ON → SWITCHED_ON → OPERATION_ENABLED → FAULT` のフル実装
- **1 慣性モータモデル:** `velocity += (dt/M) * (tau - D*velocity)`, `position += dt * velocity`
- **安全機構:** トルクリミット / 速度リミット超過で `FAULT` 自動遷移、`M ≤ 0` / `task_dt_ns == 0` ガード

### Tunable Parameters（ADS 注入）

`M`（慣性）, `D`（粘性）, `Kt`（トルク定数）, `tau_limit`, `vel_limit`, `task_dt_ns`

### 注意点

- 仕様は 1 軸記述だが実装は 2 軸。Phase 1 では Axis 0 のみ使用で問題なし。

---

## 3. ExperimentLogger（C++ TcCOM）— ✅ 実験可能（Phase 3 先行実装）

### I/O

| 方向 | ポート | 型 | Phase 1–3 ソース |
|---|---|---|---|
| IN | `torque_cmd` | `double` | DriverAdapter |
| IN | `ref_value` | `double` | ExperimentSequencer |
| IN | `ff_value` | `double` | ExperimentSequencer |
| IN | `control_input` | `double` | ControllerCore |
| IN | `error` | `double` | ControllerCore |
| IN | `motor_position` | `double` | ゼロ埋め |
| IN | `motor_velocity` | `double` | ゼロ埋め |
| IN | `motor_torque_act` | `double` | ゼロ埋め |
| IN | `load_position` | `double` | VirtualMotorCore |
| IN | `load_velocity` | `double` | VirtualMotorCore |
| OUT | `LogStatus.records_written` | `ULONG` | — |
| OUT | `LogStatus.file_size_kb` | `ULONG` | — |
| OUT | `LogStatus.error_code` | `ULONG` | — |

### 内部処理

- 96 byte 固定長 `LogRecord` × 8,000 バッファ（≈ 768 KB）
- `ITcFileAccessAsync` による非同期バイナリ書き込み
- FSM: `Idle → OpenWait → Active → WriteWait → CloseWait`
- `LogControl.logging`（ADS）で開始/停止制御

### 注意点

- `kTimestampStepNs = 1,000,000 ns` がハードコード — Phase 4 (125 µs) 移行時に要パラメータ化
- tsproj に**インスタンス未作成** — GUI でのインスタンス作成＋タスク割り当てが別途必要

---

## 4. DriverAdapter（PLC ST）— ✅ 実験可能

### I/O

| 方向 | 変数 | 型 | AT リンク |
|---|---|---|---|
| IN | `control_input` | `LREAL` | `AT %I*` ✔ |
| IN | `dist_value` | `LREAL` | `AT %I*` ✔ |
| IN | `statusword` | `UINT` | `AT %I*` ✔ |
| IN | `controlword_in` | `UINT` | `AT %I*` ✔ |
| OUT | `target_torque` | `LREAL` | `AT %Q*` ✔ |
| OUT | `controlword_out` | `UINT` | `AT %Q*` ✔ |
| OUT | `statusword_out` | `UINT` | `AT %Q*` ✔ |

### 内部処理

1. `target_torque = control_input + dist_value`（Dist Adder）
2. `enable_torque_output = FALSE` で `target_torque = 0.0`（安全遮断）
3. CW/SW 中継

### 所見

全 I/O に適切な AT リンクが設定済み。仕様完全準拠。問題なし。

---

## 5. ExperimentSequencer（PLC ST）— ⚠ AT リンク不足

### 実装済み機能

- テーブルリプレイ: `ref_table[idx]` / `ff_table[idx]` / `dist_table[idx]` → スカラ出力
- `idx` 管理、`table_len` クランプ、再生完了処理、`rearm_required` による再開始防止
- 暫定 SIL ログ: `GVL_SEQ_LOG` リングバッファ（200,000 サンプル）統合済み

### AT リンク状況

| 変数 | 方向 | AT リンク | 状態 |
|---|---|---|---|
| `ref_value` | OUT | `AT %Q*` | ✔ |
| `ff_value` | OUT | `AT %Q*` | ✔ |
| `dist_value` | OUT | `AT %Q*` | ✔ |
| `experiment_active` | IN | **なし** | ❌ **要追加 `AT %I*`** |
| `mode_flags` | IN | **なし** | ❌ **要追加 `AT %I*`**（将来用） |
| `playback_done` | OUT | **なし** | ❌ **要追加 `AT %Q*`** |

### 影響

`experiment_active` の AT リンクがないと StateMachineControl からのリアルタイム同期伝達ができず、**実験シーケンスの開始/停止が cross-PLC で連動しない**。`playback_done` も同様に StateMachineControl 側 `bSeqPlaybackDone AT %I*` とリンクできない。

---

## 6. StateMachineControl / ModeManager（PLC ST）— ⚠ AT リンク不足

### 実装済み機能

- CiA 402 ControlWord 自動生成（`FB_StateMachineControl` + `F_DecodeDriveState`）
- `mode_flags` から `servo_enable_req` / `experiment_start_req` / `seq_reset_req` デコード
- `experiment_state`（IDLE / READY / RUNNING / DONE）遷移管理
- `bSeqPlaybackDone` による再生完了検出

### AT リンク状況

| 変数 | 方向 | AT リンク | 状態 |
|---|---|---|---|
| `uiCtrlWord` | OUT | `AT %Q*` | ✔ |
| `uiStatWord` | IN | `AT %I*` | ✔ |
| `bSeqPlaybackDone` | IN | `AT %I*` | ✔ |
| `experiment_active` | OUT | **なし** | ❌ **要追加 `AT %Q*`** |
| `mode_flags` | — | **なし** | ❌（将来用、`AT %Q*` 追加推奨） |

### 影響

`experiment_active` を ExperimentSequencer にリアルタイム伝達できない。

---

## 残課題一覧（Mapping 以外）

| # | 課題 | 対象 | 深刻度 | 種別 |
|---|---|---|---|---|
| 1 | `GVL_SEQ.experiment_active` に `AT %I*` 追加 | ExperimentSequencer | **高** | コード |
| 2 | `GVL_SEQ.playback_done` に `AT %Q*` 追加 | ExperimentSequencer | **高** | コード |
| 3 | `GVL_MODE.experiment_active` に `AT %Q*` 追加 | StateMachineControl | **高** | コード |
| 4 | `GVL_SEQ.mode_flags` に `AT %I*` 追加 | ExperimentSequencer | 低 | コード |
| 5 | `GVL_MODE.mode_flags` に `AT %Q*` 追加 | StateMachineControl | 低 | コード |
| 6 | ControllerCore TMC 再読み込み（`error` 出力を tsproj に反映） | ControllerCore | 中 | GUI |
| 7 | ExperimentLogger tsproj インスタンス作成＋タスク割り当て | ExperimentLogger | 中 | GUI（Phase 3） |
| 8 | ~~ArchitectureSpec のパラメータ構造体名を実装に合わせて更新~~ | docs | ~~低~~ 解消済み |
