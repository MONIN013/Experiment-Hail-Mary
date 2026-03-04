# ExperimentLogger Module Spec

> Module type: C++ TcCOM (Phase 3)
> Task: VirtualMotorTask 1 ms (Phase 1-3), ControlTask 125 us (Phase 4)
> AMS Port: 351

## Summary
ExperimentLogger is a binary file logger for experiment data. `Inputs.loggingReq` controls file open/close via ModeManager, and `Inputs.playbackDone` provides a same-task fast path that stops record appends immediately when playback completes.

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
| `loggingReq` | `BOOL` | ModeManager `experimentActiveOut` | auto logging trigger |
| `playbackDone` | `BOOL` | ExperimentSequencer `GVL_SEQ.playbackDone` | same-task write-stop fast path |

## Outputs
| Name | Type | Notes |
|---|---|---|
| `LogStatus.recordsWritten` | `UDINT` | written records |
| `LogStatus.fileSizeKb` | `UDINT` | file size in KB |
| `LogStatus.errorCode` | `UDINT` | 0 = OK |

## Control Parameter
| Symbol | Type | Notes |
|---|---|---|
| `ExperimentLogger_Obj1 (Module1).LogControl.filePath` | `STRING(255)` | output path; parent directory must already exist |

`Inputs.loggingReq` controls file open/close. `Inputs.playbackDone` suppresses new record appends immediately without taking over session close ownership from ModeManager.

## Runtime Behavior
1. On `loggingReq` rising edge: reset session runtime state, begin file open, and enter the active logging session once the async open completes.
2. While `loggingReq = TRUE`, `playbackDone = FALSE`, and the file FSM is active: append one full `LogRecord` per cycle.
3. On `playbackDone = TRUE`: stop appending within the same task scan.
4. On `loggingReq` falling edge: flush remaining buffer and close the file.
5. On `resetReq` rising edge: stop the session safely and reset runtime state once any pending async close completes.

## Mapping (SIL)
- `loadPosition <- DriverAdapter.positionRel` (D12: ControllerCore.positionRel から変更)
- `loadVelocity <- DriverAdapter.velocityAct` (D11: VirtualMotorCore.velocityOut から変更)
- `motorCurrentAct <- DriverAdapter.currentAct` (D13: SIL でも接続済み)
- `playbackDone <- ExperimentSequencer.GVL_SEQ.playbackDone` (H6: same-task fast-path stop)
- `motorPosition/motorVelocity` are unconnected in SIL (0-fill).
