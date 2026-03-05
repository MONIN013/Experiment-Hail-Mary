# ExperimentLogger Module Spec

> Module type: C++ TcCOM (Phase 3)
> Task: VirtualMotorTask 1 ms (Phase 1-3), ControlTask 125 us (Phase 4)
> AMS Port: 351

## Summary
ExperimentLogger is a binary file logger for experiment data. `Inputs.preArmReq` pre-opens the file in `SERVO_READY`, `Inputs.loggingReq` gates record append and session close, and `Inputs.playbackDone` provides a same-task fast path that stops record appends immediately when playback completes.

## Inputs
| Name | Type | Source | Notes |
|---|---|---|---|
| `currentCmd` | `LREAL` | DriverAdapter | command current [A]; `% rated` drive signals are converted back to current units before logging |
| `refValue` | `LREAL` | ExperimentSequencer | reference |
| `ffValue` | `LREAL` | ExperimentSequencer | feedforward |
| `controlInput` | `LREAL` | ControllerCore | controller output |
| `error` | `LREAL` | ControllerCore | `ref - loadPosition` |
| `motorPosition` | `LREAL` | (Phase 4) | SIL: unconnected (0) |
| `motorVelocity` | `LREAL` | (Phase 4) | SIL: unconnected (0) |
| `motorCurrentAct` | `LREAL` | DriverAdapter `currentAct` (D13) | motor current (SIL: via VirtualMotorCore → DriverAdapter) |
| `loadPosition` | `LREAL` | DriverAdapter `positionRel` (D12) | zero-based per run |
| `loadVelocity` | `LREAL` | DriverAdapter `velocityAct` (D11) | SIL load velocity |
| `resetReq` | `BOOL` | ModeManager | reset edge |
| `loggingReq` | `BOOL` | ModeManager `experimentActiveOut` | append gate and session close trigger |
| `preArmReq` | `BOOL` | ModeManager `preArmOut` | pre-open trigger in `SERVO_READY` |
| `playbackDone` | `BOOL` | ExperimentSequencer `GVL_SEQ.playbackDone` | same-task write-stop fast path |

## Outputs
| Name | Type | Notes |
|---|---|---|
| `LogStatus.recordsWritten` | `UDINT` | written records |
| `LogStatus.fileSizeKb` | `UDINT` | file size in KB |
| `LogStatus.errorCode` | `UDINT` | 0 = OK, otherwise internal `0xE000000x` code or underlying HRESULT |
| `loggerReady` | `BOOL` | `ACTIVE` かつ有効 file handle 保持、close/error pending なしのとき `TRUE`。ModeManager が `SERVO_READY → RUNNING` 遷移前の確認に使用 |

## Control Parameter
| Symbol | Type | Notes |
|---|---|---|
| `ExperimentLogger_Obj1 (Module1).LogControl.filePath` | `STRING(255)` | output path; parent directory must already exist |

`Inputs.preArmReq` is the only file-open trigger. `Inputs.loggingReq` no longer opens the file and is invalid unless the logger is already `ACTIVE`. `Inputs.playbackDone` suppresses new record appends immediately without taking over session close ownership from ModeManager.

## Runtime Behavior
1. On `preArmReq` rising edge: reset session runtime state, begin file open, and enter the pre-armed `ACTIVE` state once the async open completes.
2. On `loggingReq` rising edge: require the file FSM to already be `ACTIVE`; otherwise raise an error and mark the session failed.
3. While `loggingReq = TRUE`, `playbackDone = FALSE`, and the session is not failed: append one full `LogRecord` per cycle. During `WRITE_WAIT`, records continue to accumulate in a second in-memory buffer.
4. On `playbackDone = TRUE`: stop appending within the same task scan.
5. On `loggingReq` falling edge: flush remaining buffer and close the file.
6. On `preArmReq` falling edge while `loggingReq = FALSE`: close any pre-opened file that never entered an active run.
7. On `resetReq` rising edge: stop the session safely and reset runtime state once any pending async close completes.
8. Async `OPEN_WAIT` / `WRITE_WAIT` / `CLOSE_WAIT` failures must not remain latched in a wait state. The module aborts the session, releases `ITcFileAccessAsync`, transitions to `ERROR` (or `IDLE` after reset teardown), and preserves the raw failure code in `errorCode`.
9. `OPEN_WAIT` completion validates the returned file handle before declaring the logger ready. A completed open without a valid handle is treated as a hard failure.
10. On `loggingReq` falling edge, buffered records are drained in order (`Write -> Write -> ... -> Close`) so records captured during `WRITE_WAIT` are not dropped.

## Mapping (SIL)
- `loadPosition <- DriverAdapter.positionRel` (D12: ControllerCore.positionRel から変更)
- `loadVelocity <- DriverAdapter.velocityAct` (D11: VirtualMotorCore.velocityOut から変更)
- `motorCurrentAct <- DriverAdapter.currentAct` (D13: SIL でも接続済み)
- `preArmReq <- ModeManager.preArmOut` (Issue #12: pre-open in `SERVO_READY`)
- `playbackDone <- ExperimentSequencer.GVL_SEQ.playbackDone` (H6: same-task fast-path stop)
- `motorPosition/motorVelocity` are unconnected in SIL (0-fill).
