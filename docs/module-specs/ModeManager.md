# ModeManager Module Spec

> Module type: PLC ST (StateMachineControl)
> Task: PlcTask1 10 ms (Phase 1–3), SupervisionTask 1 ms (Phase 4)
> AMS Port: 852

## Summary

ModeManager は CiA 402 ドライブ状態制御・実験シーケンス管理・安全監視を担当する有限状態機械 (FSM) である。
すべての出力は **現在の FSM 状態のみ** に依存し、過渡的なフラグの組み合わせによる暗黙の状態を排除する。

### 設計原則

1. **状態依存出力**: 出力 (`experimentActive`, `resetOut`, `enableCurrentOut`, `experimentState`) は FSM 状態のみで決定する
2. **入力 Latch→Clear**: MATLAB が ADS 経由で set した要求フラグ (`resetReq`) は、PLC が立ち上がりエッジを検出し状態遷移を完了した後に **PLC 側で 0 クリア** する
3. **排他的状態遷移**: `RESETTING` 状態中は実験開始への遷移を一切許可しない
4. **Watchdog 保護**: Heartbeat タイムアウト時は `IDLE` に強制遷移し全出力を安全側に倒す

---

## FSM States (`E_ModeState`)

| 値 | 状態名 | 意味 |
|---|---|---|
| 0 | `IDLE` | サーボ OFF / 初期状態 |
| 10 | `RESETTING` | リセットパルス出力中 (全 Run 状態を禁止) |
| 20 | `SERVO_READY` | サーボ ON + ドライブ OPERATION_ENABLED, 実験待機 |
| 30 | `RUNNING` | 実験実行中 |
| 40 | `DONE` | 再生完了, 次の実験トリガ待ち |

---

## State Transition Diagram

```
                   ┌──────────────────────────┐
                   │         IDLE (0)          │
                   │ servo OFF / 初期状態      │
                   └────┬─────────────────┬────┘
                        │                 │
              servoEnable                resetEdge
             AND driveReady               │
                        │                 │
                        ▼                 ▼
              ┌──────────────┐   ┌──────────────────┐
              │ SERVO_READY  │   │   RESETTING (10)  │
              │    (20)      │◄──│ パルス出力中       │
              │ 実験待機     │   │ holdTicks 完了→   │
              └───┬──────┬───┘   │  → IDLE           │
                  │      │       └──────────────────┘
       expStartReq│   resetEdge        ▲    ▲
      AND driveReady  │               │    │
      AND !done   │      │            │    │
                  ▼      └────────────┘    │
              ┌──────────────┐             │
              │  RUNNING (30)│─resetEdge──►│
              │  実験実行中  │             │
              └───┬──────────┘             │
                  │ seqPlaybackDone        │
                  ▼                        │
              ┌──────────────┐             │
              │   DONE (40)  │─resetEdge──►│
              │ 完了/待機    │
              └───┬──────────┘
                  │ !expStartReq
                  ▼
              SERVO_READY (20)
```

### 遷移条件一覧

| 遷移元 | 遷移先 | 条件 |
|---|---|---|
| `IDLE` | `RESETTING` | `resetEdge` |
| `IDLE` | `SERVO_READY` | `servoEnable` AND `driveReady` |
| `RESETTING` | `IDLE` | `resetHoldTicks` 完了 |
| `SERVO_READY` | `IDLE` | NOT `servoEnable` OR NOT `driveReady` |
| `SERVO_READY` | `RESETTING` | `resetEdge` |
| `SERVO_READY` | `RUNNING` | `experimentStartReq` AND `driveReady` AND NOT `doneLatched` |
| `RUNNING` | `DONE` | `seqPlaybackDone` |
| `RUNNING` | `IDLE` | NOT `servoEnable` (異常離脱) |
| `RUNNING` | `RESETTING` | `resetEdge` |
| `DONE` | `SERVO_READY` | NOT `experimentStartReq` (rearm) |
| `DONE` | `IDLE` | NOT `servoEnable` |
| `DONE` | `RESETTING` | `resetEdge` |
| *any* | `IDLE` | Watchdog timeout (強制) |

---

## Inputs

| Name | Type | Source | Notes |
|---|---|---|---|
| `statWord` | `UINT` | DriverAdapter (I/O Mapping) | CiA 402 StatusWord |
| `seqPlaybackDone` | `BOOL` | ExperimentSequencer (I/O Mapping) | テーブル再生完了ラッチ |
| `GVL_MODE.modeFlags` | `UINT` | MATLAB (ADS Write) | ビットフラグ: bit0=ServoEnable, bit1=ExperimentStartReq |
| `GVL_MODE.resetReq` | `BOOL` | MATLAB (ADS Write) | リセット要求 (PLC が edge 検出後に clear) |
| `GVL_MODE.hostHeartbeatCounter` | `UDINT` | MATLAB (ADS Write) | ホスト側ハートビート |

## Outputs

| Name | Type | Dest | Notes |
|---|---|---|---|
| `ctrlWord` | `UINT` | DriverAdapter (I/O Mapping) | CiA 402 ControlWord (FB_StateMachineControl 出力) |
| `experimentActiveOut` | `BOOL` | ExperimentSequencer / ExperimentLogger (I/O Mapping) | 実験アクティブ |
| `resetOut` | `BOOL` | ExperimentSequencer / ExperimentLogger (I/O Mapping) | リセットパルス |
| `enableCurrentOut` | `BOOL` | DriverAdapter (I/O Mapping) | 電流イネーブルゲート |
| `GVL_MODE.experimentActive` | `BOOL` | MATLAB (ADS Read) | 実験アクティブ (ADS 読出し用) |
| `GVL_MODE.experimentState` | `UINT` | MATLAB (ADS Read) | FSM 状態 (IDLE=0, READY=1, RUNNING=2, DONE=3) |
| `GVL_MODE.resetAckCounter` | `UDINT` | MATLAB (ADS Read) | リセット ACK カウンタ |

---

## State-Dependent Output Table

| FSM State | `experimentActive` | `resetOut` | `enableCurrentOut` | `experimentState` |
|---|---|---|---|---|
| `IDLE` | FALSE | FALSE | FALSE | `STATE_IDLE` (0) |
| `RESETTING` | FALSE | TRUE (*pulse*) | FALSE | `STATE_IDLE` (0) |
| `SERVO_READY` | FALSE | FALSE | TRUE | `STATE_READY` (1) |
| `RUNNING` | TRUE | FALSE | TRUE | `STATE_RUNNING` (2) |
| `DONE` | FALSE | FALSE | TRUE | `STATE_DONE` (3) |

> `resetOut` は `RESETTING` 状態中のみ `TRUE` となり、`RESET_PULSE_HOLD_TICKS` (20 ticks, 現行 `PlcTask` 1 ms 設定で約 20 ms) 後に自動的に `FALSE`/`IDLE` に遷移する。

---

## Reset Handshake Protocol

```
MATLAB                              PLC (ModeManager)
  │                                     │
  │─── ADS Write: resetReq=TRUE ──────►│
  │                                     │ detect rising edge
  │                                     │ transition → RESETTING
  │                                     │ clear: GVL_MODE.resetReq := FALSE
  │                                     │ increment: resetAckCounter++
  │                                     │ output: resetOut := TRUE (pulse)
  │                                     │ clear: experimentActive := FALSE
  │                                     │ clear: modeFlags := 0
  │                                     │
  │                                     │ after RESET_PULSE_HOLD_TICKS:
  │                                     │ transition → IDLE
  │                                     │
  │◄── ADS Read: resetAckCounter ──────│
  │    (counter incremented = ACK)      │
```

---

## Watchdog

- **Arm 条件**: `modeFlags <> 0` OR `experimentActive`
- **タイムアウト**: `HEARTBEAT_TIMEOUT_TICKS` (50 ticks = 500 ms @ 10 ms task)
- **効果**: `IDLE` に強制遷移 + `modeFlags := 0` + `experimentActive := FALSE` + `watchdogTripCounter++`
- **解除**: ホスト側が `hostHeartbeatCounter` をインクリメントすると silence ticks リセット

---

## ADS Symbols (Port 852)

| Symbol | Type | R/W | Notes |
|---|---|---|---|
| `GVL_MODE.modeFlags` | `UINT` | W | ビットフラグ一括制御 |
| `GVL_MODE.resetReq` | `BOOL` | W | PLC が edge 検出後に clear |
| `GVL_MODE.hostHeartbeatCounter` | `UDINT` | W | ホスト HB |
| `GVL_MODE.experimentActive` | `BOOL` | R | FSM 出力 |
| `GVL_MODE.experimentState` | `UINT` | R | IDLE/READY/RUNNING/DONE |
| `GVL_MODE.resetAckCounter` | `UDINT` | R | Reset ACK カウンタ |
| `GVL_MODE.watchdogTripCounter` | `UDINT` | R | WD trip 回数 |

---

## Mapping (SIL)

- `statWord` ← VirtualMotorCore (I/O Mapping 経由、DriverAdapter.statusWordOut)
- `seqPlaybackDone` ← ExperimentSequencer (`GVL_SEQ.playbackDone`)
- `ctrlWord` → DriverAdapter (`controlWordIn`)
- `experimentActiveOut` → ExperimentSequencer (`GVL_SEQ.experimentActive`) / ExperimentLogger
- `resetOut` → ExperimentSequencer (`GVL_SEQ.resetReq`) / ExperimentLogger

---

## Implementation Notes

- FSM 本体は `MAIN` プログラム内で `CASE modeState OF` で実装
- CiA 402 ドライブ制御は `FB_StateMachineControl` に委譲 (変更なし)
- `E_ModeState` 列挙型を `StateMachineControl/DUTs/` に追加
- `GVL_MODE` に `modeState : E_ModeState` を追加 (デバッグ可視化用)
