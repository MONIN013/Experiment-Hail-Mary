# 実装済み Flag 一覧（2026-02-25）

> 目的: 現在の各モジュール実装に存在する `Flag`（bit フラグ / BOOL フラグ）を、実装コード基準で整理する。

---

## 結論（要点）

- 中核の **bit フラグ** は `StateMachineControl` の `GVL_MODE.mode_flags`。
- 実験の開始/実行/完了連携は主に `experiment_active` / `playback_done` で構成。
- `ControllerCore` はフィルタ enable フラグ群、`ExperimentLogger` は logging フラグを持つ。

---

## 1. StateMachineControl / ModeManager（PLC ST）

### 1.1 公開 Flag（GVL_MODE）

| 変数 | 型 | 種別 | 役割 |
|---|---|---|---|
| `GVL_MODE.mode_flags` | `UINT` | bitmask | 動作要求フラグ群 |
| `GVL_MODE.experiment_active` | `BOOL` | 状態フラグ | 実験実行中 |
| `GVL_MODE.experiment_state` | `UINT` | 状態値 | `IDLE/READY/RUNNING/DONE` |

参照:
- `StateMachineControl/GVLs/GVL_MODE.TcGVL:17`
- `StateMachineControl/GVLs/GVL_MODE.TcGVL:18`
- `StateMachineControl/GVLs/GVL_MODE.TcGVL:19`

### 1.2 `mode_flags` の bit 定義（実装済み）

| 定数 | 値 | bit | 意味 |
|---|---:|---:|---|
| `MODEF_SERVO_ENABLE` | `16#0001` | 0 | サーボ有効要求 |
| `MODEF_EXPERIMENT_START_REQ` | `16#0002` | 1 | 実験開始要求 |
| `MODEF_RESET_SEQ_REQ` | `16#0004` | 2 | Sequencer リセット要求 |

参照:
- `StateMachineControl/GVLs/GVL_MODE.TcGVL:6`
- `StateMachineControl/GVLs/GVL_MODE.TcGVL:7`
- `StateMachineControl/GVLs/GVL_MODE.TcGVL:8`

### 1.3 `MAIN` 内での内部フラグ（デコード結果）

`GVL_MODE.mode_flags` から以下に分解して使用:

- `servo_enable_req : BOOL`
- `experiment_start_req : BOOL`
- `seq_reset_req : BOOL`

完了通知入力:

- `bSeqPlaybackDone AT%I* : BOOL`

参照:
- `StateMachineControl/POUs/MAIN.TcPOU:8`
- `StateMachineControl/POUs/MAIN.TcPOU:22`

---

## 2. ExperimentSequencer（PLC ST）

### 2.1 公開 Flag（GVL_SEQ）

| 変数 | 型 | 種別 | 役割 |
|---|---|---|---|
| `GVL_SEQ.mode_flags` | `UINT` | bitmask（将来用受け口） | ModeManager フラグ受け |
| `GVL_SEQ.reset_req` | `BOOL` | 要求フラグ | Sequencer 内部リセット |
| `GVL_SEQ.experiment_active` | `BOOL` | 実行フラグ | 再生開始/継続コマンド |
| `GVL_SEQ.playback_done` | `BOOL` | 完了フラグ | テーブル再生完了通知 |

参照:
- `ExperimentSequencer/GVLs/GVL_SEQ.TcGVL:27`
- `ExperimentSequencer/GVLs/GVL_SEQ.TcGVL:28`
- `ExperimentSequencer/GVLs/GVL_SEQ.TcGVL:29`
- `ExperimentSequencer/GVLs/GVL_SEQ.TcGVL:30`

### 2.2 POU 内の内部制御フラグ（主要）

`PRG_ExperimentSequencer` 内で再生制御に使用:

- `cmd_active_prev`
- `start_edge`
- `playback_running`
- `rearm_required`
- `sample_emitted_this_scan`

参照:
- `ExperimentSequencer/POUs/PRG_ExperimentSequencer.TcPOU`

---

## 3. DriverAdapter（PLC ST）

### 3.1 公開 Flag（GVL_DRV）

| 変数 | 型 | 種別 | 役割 |
|---|---|---|---|
| `GVL_DRV.enable_torque_output` | `BOOL` | 安全フラグ | `FALSE` 時に `target_torque = 0.0` |

参照:
- `DriverAdapter/GVLs/GVL_DRV.TcGVL:27`
- `DriverAdapter/POUs/PRG_DriverAdapter.TcPOU:12`

---

## 4. ControllerCore（C++ TcCOM）

### 4.1 ADS パラメータの enable フラグ群

`ST_FilterEnable` として公開されている制御ブロック enable フラグ:

| フィールド | 型 | 役割 |
|---|---|---|
| `enable_pid` | `bool` | PID 段有効 |
| `enable_lead` | `bool` | Lead 段有効 |
| `enable_notch` | `bool` | Notch 段有効 |
| `enable_reso` | `bool` | Reso 段有効 |

参照:
- `ControllerCore/ControllerCoreServices.h:60`
- `ControllerCore/ControllerCoreServices.h:62`
- `ControllerCore/ControllerCoreServices.h:63`
- `ControllerCore/ControllerCoreServices.h:64`
- `ControllerCore/ControllerCoreServices.h:65`

適用箇所（各段の有効/バイパス判定）:

- `ControllerCore/Module1.cpp:236`
- `ControllerCore/Module1.cpp:241`
- `ControllerCore/Module1.cpp:252`
- `ControllerCore/Module1.cpp:260`

---

## 5. ExperimentLogger（C++ TcCOM）

### 5.1 ロギング制御フラグ

| 変数 | 型 | 種別 | 役割 |
|---|---|---|---|
| `LogControl.logging` | `bool` | コマンドフラグ | ログ開始/停止 |

参照:
- `ExperimentLogger/ExperimentLoggerServices.h:49`

内部では立上り/立下りエッジ検出に使用:

- `ExperimentLogger/Module1.cpp:228`

---

## 6. VirtualMotorCore（C++ TcCOM）

- 公開 I/F としての明示的な `BOOL`/`bitmask` Flag は基本なし。
- 状態管理は `controlword` / `statusword`（CiA 402）と内部状態機械で実装。

参照:
- `VirtualMotorCore/VirtualMotorCoreServices.h`

---

## 7. 補足（現状の実装上の注意）

- `mode_flags` / `experiment_active` / `playback_done` はコード定義済みだが、PLC 間リアルタイム連携には `AT %I* / %Q*` リンク不足の箇所がある（詳細は `docs/ModuleReadiness_2026-02-25.md` 参照）。
- 特に `StateMachineControl ↔ ExperimentSequencer` の連携では `experiment_active` と `playback_done` の接続状態が重要。

---
---

# 妥当性レビュー・修正案・改定規格

> 以下は上記 §1–§7 の実装済みフラグ一覧に対する妥当性検証結果と、
> **ADS → ModeManager 一元制御** および **統合リセット仕様** の改定案である。

---

## 8. 妥当性レビュー（実装コードとの突合）

### 8.1 検証結果サマリ

| セクション | 対象 | 判定 | 備考 |
|---|---|---|---|
| §1 GVL_MODE | bit定義・状態変数 | ✅ 正確 | `MODEF_*` 定数、`mode_flags`/`experiment_active`/`experiment_state` すべて実装と一致 |
| §1 MAIN | デコード・状態遷移 | ✅ 正確 | `servo_enable_req`/`experiment_start_req`/`seq_reset_req` のデコード、`bSeqPlaybackDone` 入力を確認 |
| §2 GVL_SEQ | 公開フラグ | ✅ 正確 | `mode_flags`/`reset_req`/`experiment_active`/`playback_done` + `table_len_clamped` |
| §2 PRG | 内部制御フラグ | ✅ 正確 | `cmd_active_prev`/`start_edge`/`playback_running`/`rearm_required`/`sample_emitted_this_scan` |
| §3 GVL_DRV | 安全フラグ | ✅ 正確 | `enable_torque_output` のゲーティング実装を確認 |
| §4 ControllerCore | enable フラグ群 | ✅ 正確 | `ST_FilterEnable` の 4 フィールド、`StepController` 内の条件分岐を確認 |
| §5 ExperimentLogger | logging フラグ | ✅ 正確 | `LogControl.logging` のエッジ検出 (`risingEdge`/`fallingEdge`) を確認 |
| §6 VirtualMotorCore | なし | ✅ 正確 | CiA 402 `controlword`/`statusword` のみ（BOOL flag なし） |

### 8.2 既知の問題点

| # | 問題 | 影響 | 該当コード |
|---|---|---|---|
| P1 | `GVL_SEQ.experiment_active` に `AT %I*` なし | ModeManager → Sequencer のリアルタイム同期伝達不可 | `ExperimentSequencer/GVLs/GVL_SEQ.TcGVL` |
| P2 | `GVL_SEQ.playback_done` に `AT %Q*` なし | Sequencer → ModeManager の完了通知不可 | `ExperimentSequencer/GVLs/GVL_SEQ.TcGVL` |
| P3 | `GVL_SEQ.reset_req` に `AT %I*` なし | ModeManager からのリセット伝達不可 | `ExperimentSequencer/GVLs/GVL_SEQ.TcGVL` |
| P4 | ModeManager の `experiment_active` に `AT %Q*` なし | 外部モジュールへの出力マッピング不可 | `StateMachineControl/POUs/MAIN.TcPOU` |
| P5 | `PRG_ExperimentSequencer` の reset 処理が `table_len := 0` を含む | リセット時にテーブルデータが失われる（テーブル保持の設計意図に反する） | `ExperimentSequencer/POUs/PRG_ExperimentSequencer.TcPOU` |
| P6 | ControllerCore に外部リセット入力 (`reset_req`) なし | ModeManager からのリアルタイムリセット伝達手段がない | `ControllerCore/ControllerCoreServices.h` |
| P7 | ExperimentLogger に外部リセット入力 (`reset_req`) なし | ModeManager からのリアルタイムリセット伝達手段がない | `ExperimentLogger/ExperimentLoggerServices.h` |
| P8 | `GVL_DRV.enable_torque_output` に `AT %I*` なし | ModeManager からの安全フラグ伝達不可（現在は直接 ADS 書き込み想定） | `DriverAdapter/GVLs/GVL_DRV.TcGVL` |

---

## 9. 改定案: ADS → ModeManager 一元制御

### 9.1 設計原則

```
┌─────────────────────────────────────────────────────────┐
│  制御フラグ      → ModeManager 経由で一元管理           │
│  チューナブルパラメータ → 各モジュール ADS 直接書き込み  │
└─────────────────────────────────────────────────────────┘
```

- **Flag（制御フラグ）**: 実験の開始/停止/リセット等の **動作制御** に関するフラグ。
  `GVL_MODE.mode_flags` を唯一の ADS 書き込みエントリポイントとし、ModeManager が各モジュールへ浸透させる。
- **Parameter（チューナブルパラメータ）**: フィルタ係数・テーブルデータ・ファイルパス等の **構成パラメータ**。
  各モジュールの ADS シンボルに直接書き込み。ModeManager を経由しない。

### 9.2 `mode_flags` ビットマップ（改定）

| bit | 定数名 | 値 | トリガ型 | 意味 |
|----:|---|---:|---|---|
| 0 | `MODEF_SERVO_ENABLE` | `16#0001` | レベル | サーボ有効要求。CiA 402 SM 駆動 + トルク出力ゲート |
| 1 | `MODEF_EXPERIMENT_START_REQ` | `16#0002` | レベル | 実験開始要求。`experiment_active` 状態遷移を駆動 |
| 2 | `MODEF_RESET_REQ` | `16#0004` | **ワンショット** | 統合リセット要求（§10 参照）。ModeManager が 1 scan assert 後に自動クリア |
| 3–15 | *(reserved)* | — | — | 将来拡張用 |

> **変更点:** 旧 `MODEF_RESET_SEQ_REQ`（bit 2）を `MODEF_RESET_REQ` に改名・用途拡大。
> Sequencer のみのリセットから **全モジュール統合リセット** に変更。

> **ワンショット動作:** MATLAB が bit 2 を SET → ModeManager が検出し、各モジュールへリセット信号を
> 1 scan 間 assert → ModeManager が `mode_flags` の bit 2 を自動クリア。
> MATLAB 側でのクリア操作は不要。

### 9.3 ModeManager 出力変数（改定）

ModeManager (MAIN) が以下の `AT %Q*` 変数を公開し、tsproj Mapping で各モジュールに接続する:

| 出力変数 | 型 | 宛先 | 導出元 |
|---|---|---|---|
| `bExperimentActive AT %Q*` | `BOOL` | ExperimentSequencer (`GVL_SEQ.experiment_active AT %I*`) | 既存の `experiment_active` 状態遷移ロジック |
| `bResetOut AT %Q*` | `BOOL` | ExperimentSequencer, ControllerCore, ExperimentLogger | `MODEF_RESET_REQ` 立上りエッジ → 1 scan パルス |
| `bEnableTorqueOut AT %Q*` | `BOOL` | DriverAdapter (`GVL_DRV.enable_torque_output AT %I*`) | `servo_enable_req AND drive_ready` |
| `uiCtrlWord AT %Q*` | `UINT` | DriverAdapter (`GVL_DRV.controlword_in AT %I*`) | 既存 CiA 402 SM 出力 |

> **注記:** `bSeqPlaybackDone AT %I*` (既存) は ExperimentSequencer の `GVL_SEQ.playback_done AT %Q*` から受信。

### 9.4 Flag 浸透フロー図

```
MATLAB ──ADS Write──► GVL_MODE.mode_flags (UINT)
                          │
                          ▼
              ┌───────────────────────┐
              │  ModeManager (MAIN)   │  PlcTask1 (10 ms)
              │                       │
              │  ビットデコード:       │
              │  bit0 → servo_enable  │
              │  bit1 → exp_start     │
              │  bit2 → reset (1shot) │
              │                       │
              │  状態遷移:            │
              │  → experiment_active  │
              │  → experiment_state   │
              │                       │
              │  出力:                │
              │  bExperimentActive ───────► GVL_SEQ.experiment_active (AT%I*)
              │  bResetOut ──────────────┬► GVL_SEQ.reset_req (AT%I*)
              │                          ├► ControllerCore.Inputs.reset_req
              │                          └► ExperimentLogger.Inputs.reset_req
              │  bEnableTorqueOut ────────► GVL_DRV.enable_torque_output (AT%I*)
              │  uiCtrlWord ─────────────► GVL_DRV.controlword_in (AT%I*)
              └───────────────────────┘
                          ▲
              GVL_SEQ.playback_done (AT%Q*) ──► bSeqPlaybackDone (AT%I*)
              GVL_DRV.statusword (既存) ───────► uiStatWord (AT%I*)
```

### 9.5 ADS 直接書き込み対象（パラメータ、ModeManager 非経由）

| モジュール | ADS シンボル | 内容 |
|---|---|---|
| ControllerCore | `*.PIDParams`, `*.LeadParams`, `*.NotchParams`, `*.ResoParams` | biquad 係数 |
| ControllerCore | `*.EnableParams` | フィルタ enable/bypass |
| ExperimentSequencer | `GVL_SEQ.ref_table`, `GVL_SEQ.ff_table`, `GVL_SEQ.dist_table` | 指令値テーブル |
| ExperimentSequencer | `GVL_SEQ.table_len` | テーブル有効長 |
| ExperimentLogger | `*.LogControl.file_path` | ログファイルパス |
| ExperimentLogger | `*.LogControl.logging` | ロギング開始/停止 |
| VirtualMotorCore | `*.VirtualMotor1Parameter.*` | モータパラメータ (M, D, Kt 等) |

> `ST_FilterEnable` は「制御ブロックの構成パラメータ」として扱い、ModeManager を経由しない。
> 実験中でも ADS で個別にフィルタの有効/無効を切り替え可能。

---

## 10. 改定案: 統合リセット仕様

### 10.1 設計思想

リセットの目的は **「同一実験構成で次の実験を開始できる状態に戻す」** ことである。

- **リセット対象:** ランタイム状態（フィルタ過渡メモリ、再生インデックス、ログセッション）
- **保持対象:** 実験構成（制御パラメータ、指令値テーブル、FF テーブル、ファイルパス）

### 10.2 リセット対象 / 保持対象マトリクス

| モジュール | リセット対象 | 保持対象（ADS 個別変更可） |
|---|---|---|
| **ExperimentSequencer** | `idx → 0`, `playback_done → FALSE`, 内部制御フラグ (`playback_running`, `rearm_required`, `cmd_active_prev`), SIL ログ (`GVL_SEQ_LOG`) | `ref_table[]`, `ff_table[]`, `dist_table[]`, `table_len` |
| **ControllerCore** | biquad 内部状態 (`m_pidS1/S2`, `m_leadS1/S2`, `m_notchS1/S2`, `m_resoS1/S2`) | `ST_PID`, `ST_PhaseLead`, `ST_Notch`, `ST_Reso` 係数, `ST_FilterEnable` |
| **ExperimentLogger** | ログセッション終了 + ランタイム状態 (`m_seq`, `m_bufferCount`, `m_recordsWritten`, `m_bytesWritten`) → ファイルクローズ | `LogControl.file_path` |
| **DriverAdapter** | *(なし — 安全フラグは ModeManager 直結)* | `enable_torque_output`（ModeManager の `bEnableTorqueOut` による） |
| **VirtualMotorCore** | *(ModeManager 管轄外; CiA 402 fault reset で個別対応)* | `M`, `D`, `Kt`, `tau_limit`, `vel_limit` |

### 10.3 ExperimentSequencer リセット動作（改定）

現行の `reset_req` 処理は `table_len := 0` を含んでおり、テーブルデータが実質失われる。
以下のように改定する:

```structured-text
(* === 改定リセット処理 === *)
IF GVL_SEQ.reset_req THEN
    (* ランタイム状態のみリセット — テーブルデータ・table_len は保持 *)
    GVL_SEQ.idx := 0;
    GVL_SEQ.ref_value := 0.0;
    GVL_SEQ.ff_value := 0.0;
    GVL_SEQ.dist_value := 0.0;
    GVL_SEQ.playback_done := FALSE;
    playback_running := FALSE;
    rearm_required := FALSE;
    cmd_active_prev := GVL_SEQ.experiment_active;

    (* SIL ログのみリセット *)
    GVL_SEQ_LOG.seq := 0;
    GVL_SEQ_LOG.t_ns := 0;
    GVL_SEQ_LOG.wr_idx := 0;
    GVL_SEQ_LOG.rd_idx := 0;
    GVL_SEQ_LOG.overflow := FALSE;

    GVL_SEQ.reset_req := FALSE;
END_IF

(* 注: 以下は削除 *)
(* GVL_SEQ.table_len := 0;         ← 削除 *)
(* GVL_SEQ.table_len_clamped := 0; ← 削除 *)
```

> **根拠:** テーブルデータと `table_len` は MATLAB から ADS で書き込まれる実験構成の一部であり、
> リセットで消去すべきではない。`table_len_clamped` は次回のテーブル再生時に `table_len` から再計算される。

### 10.4 ControllerCore リセット動作（新規追加）

`Module1Inputs` に `reset_req` フィールドを追加し、`CycleUpdate` 内で立上りエッジ検出:

```cpp
// --- ControllerCoreServices.h (Module1Inputs 改定) ---
typedef struct _Module1Inputs
{
    double ref_value;
    double ff_value;
    double position_act;
    bool   reset_req;       // ← 追加: ModeManager からのリセット要求
} Module1Inputs, *PModule1Inputs;

// --- Module1.h (メンバ追加) ---
bool m_prevResetReq;        // ← 追加: エッジ検出用

// --- Module1.cpp (CycleUpdate 冒頭に追加) ---
HRESULT CModule1::CycleUpdate(ITcTask* ipTask, ITcUnknown* ipCaller, ULONG_PTR context)
{
    const bool resetEdge = m_Inputs.reset_req && !m_prevResetReq;
    m_prevResetReq = m_Inputs.reset_req;
    if (resetEdge)
    {
        ResetRuntimeStates();   // 既存: s1/s2 ゼロクリア
    }
    // ... 以下既存ロジック ...
}
```

> **パラメータは保持:** `ResetRuntimeStates()` は biquad 内部状態 (s1/s2) のみをクリアする。
> `ST_PID`, `ST_PhaseLead`, `ST_Notch`, `ST_Reso` の係数と `ST_FilterEnable` には触れない。

### 10.5 ExperimentLogger リセット動作（新規追加）

`Module1Inputs` に `reset_req` フィールドを追加し、`CycleUpdate` 内で立上りエッジ検出:

```cpp
// --- ExperimentLoggerServices.h (Module1Inputs 改定) ---
typedef struct _Module1Inputs
{
    double torque_cmd;
    double ref_value;
    double ff_value;
    double control_input;
    double error;
    double motor_position;
    double motor_velocity;
    double motor_torque_act;
    double load_position;
    double load_velocity;
    bool   reset_req;       // ← 追加: ModeManager からのリセット要求
} Module1Inputs, *PModule1Inputs;

// --- Module1.cpp (CycleUpdate 冒頭に追加) ---
const bool resetEdge = m_Inputs.reset_req && !m_prevResetReq;
m_prevResetReq = m_Inputs.reset_req;
if (resetEdge)
{
    CloseLogFile(true);     // 残余バッファ flush + ファイルクローズ
    ResetRuntimeState();    // 既存: seq, buffer, records_written 等クリア
}
```

> **`LogControl.file_path` は保持:** リセットはランタイム状態のみ。
> `LogControl.logging` は ADS から独立制御可能。リセット後に `logging = true` を再設定すれば新セッション開始。

### 10.6 ModeManager リセット出力ロジック（改定）

```structured-text
(* --- MAIN 内 リセットワンショット処理 --- *)
VAR
    reset_req_prev : BOOL := FALSE;
    reset_edge : BOOL := FALSE;
    bResetOut AT %Q* : BOOL := FALSE;     (* 各モジュールへマッピング *)
END_VAR

(* ビットデコード *)
reset_req := (GVL_MODE.mode_flags AND GVL_MODE.MODEF_RESET_REQ) <> 0;

(* 立上りエッジ検出 *)
reset_edge := reset_req AND NOT reset_req_prev;
reset_req_prev := reset_req;

(* ワンショット出力 *)
bResetOut := reset_edge;

(* mode_flags 自動クリア *)
IF reset_edge THEN
    GVL_MODE.mode_flags := GVL_MODE.mode_flags AND NOT GVL_MODE.MODEF_RESET_REQ;
    done_latched := FALSE;
END_IF
```

---

## 11. AT リンク改定一覧

### 11.1 追加が必要な AT リンク

| モジュール | 変数 | 方向 | AT 宣言 | 改定前 |
|---|---|---|---|---|
| StateMachineControl/MAIN | `bExperimentActive` | OUT | `AT %Q*` | 変数なし（新規追加） |
| StateMachineControl/MAIN | `bResetOut` | OUT | `AT %Q*` | 変数なし（新規追加） |
| StateMachineControl/MAIN | `bEnableTorqueOut` | OUT | `AT %Q*` | 変数なし（新規追加） |
| ExperimentSequencer/GVL_SEQ | `experiment_active` | IN | `AT %I*` | AT なし |
| ExperimentSequencer/GVL_SEQ | `reset_req` | IN | `AT %I*` | AT なし |
| ExperimentSequencer/GVL_SEQ | `playback_done` | OUT | `AT %Q*` | AT なし |
| DriverAdapter/GVL_DRV | `enable_torque_output` | IN | `AT %I*` | AT なし |

### 11.2 C++ TcCOM Data Area 変更

| モジュール | 構造体 | 追加フィールド | 型 | 備考 |
|---|---|---|---|---|
| ControllerCore | `Module1Inputs` | `reset_req` | `bool` | TMC 再定義 + tsproj Mapping 追加 |
| ExperimentLogger | `Module1Inputs` | `reset_req` | `bool` | TMC 再定義 + tsproj Mapping 追加 |

### 11.3 tsproj Mapping 追加（概要）

```
ModeManager.bExperimentActive   →  ExperimentSequencer.GVL_SEQ.experiment_active
ModeManager.bResetOut           →  ExperimentSequencer.GVL_SEQ.reset_req
ModeManager.bResetOut           →  ControllerCore.Inputs.reset_req
ModeManager.bResetOut           →  ExperimentLogger.Inputs.reset_req
ModeManager.bEnableTorqueOut    →  DriverAdapter.GVL_DRV.enable_torque_output
ModeManager.uiCtrlWord          →  DriverAdapter.GVL_DRV.controlword_in
ExperimentSequencer.GVL_SEQ.playback_done  →  ModeManager.bSeqPlaybackDone
```

---

## 12. MATLAB 実験ワークフロー（改定後）

```
1. パラメータ設定（ADS 直接、ModeManager 非経由）
   ├─ ControllerCore: PID/Lead/Notch/Reso 係数, EnableParams
   ├─ ExperimentSequencer: ref_table, ff_table, dist_table, table_len
   ├─ ExperimentLogger: file_path
   └─ VirtualMotorCore: M, D, Kt 等

2. リセット
   └─ mode_flags |= MODEF_RESET_REQ  (bit 2 SET)
      → ModeManager が 1 scan で全モジュールにリセット伝達
      → mode_flags bit 2 自動クリア

3. サーボ ON
   └─ mode_flags |= MODEF_SERVO_ENABLE  (bit 0 SET)
      → ModeManager → CiA 402 OPERATION_ENABLED → bEnableTorqueOut = TRUE

4. ロギング開始（必要に応じて）
   └─ ExperimentLogger.LogControl.logging = true  (ADS 直接)

5. 実験開始
   └─ mode_flags |= MODEF_EXPERIMENT_START_REQ  (bit 1 SET)
      → ModeManager → experiment_active = TRUE → Sequencer 再生開始

6. 実験終了待ち
   └─ experiment_state == STATE_DONE を ADS ポーリング
      (playback_done → ModeManager が experiment_active = FALSE)

7. ロギング停止
   └─ ExperimentLogger.LogControl.logging = false  (ADS 直接)

8. 次の実験（パラメータ変更のみ）
   └─ 手順 1 で必要なパラメータのみ変更 → 手順 2 から繰り返し
```

> **ポイント:** テーブル・パラメータを変えずに連続実験する場合、手順 2 (リセット) → 5 (実験開始) だけで次の実験を開始できる。
> テーブルやパラメータはリセットで消去されないため、再書き込み不要。

