# ExperimentLogger Module Spec

> Module type: C++ TcCOM (Phase 3)
> Task: VirtualMotorTask 1 ms (Phase 1-3), ControlTask 125 us (Phase 4)
> AMS Port: 351

## Summary
ExperimentLogger is a binary file logger for experiment data. In current SIL operation, logging is controlled automatically by ModeManager via `Inputs.loggingReq`.

## Inputs
| Name | Type | Source | Notes |
|---|---|---|---|
| `currentCmd` | `LREAL` | DriverAdapter | command current |
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

## Outputs
| Name | Type | Notes |
|---|---|---|
| `LogStatus.recordsWritten` | `UDINT` | written records |
| `LogStatus.fileSizeKb` | `UDINT` | file size in KB |
| `LogStatus.errorCode` | `UDINT` | 0 = OK |

## Control Parameter
| Symbol | Type | Notes |
|---|---|---|
| `ExperimentLogger_Obj1 (Module1).LogControl.filePath` | `STRING(255)` | output path |

Logging control is `Inputs.loggingReq` only (manual compatibility flag was removed).

## Runtime Behavior
1. On `loggingReq` rising edge: open file and start logging.
2. While active: append one record per cycle.
3. On `loggingReq` falling edge: flush remaining buffer and close file.
4. On `resetReq` rising edge: close session safely and reset runtime state.

## Mapping (SIL)
- `loadPosition <- DriverAdapter.positionRel` (D12: ControllerCore.positionRel から変更)
- `loadVelocity <- DriverAdapter.velocityAct` (D11: VirtualMotorCore.velocityOut から変更)
- `motorCurrentAct <- DriverAdapter.currentAct` (D13: SIL でも接続済み)
- `motorPosition/motorVelocity` are unconnected in SIL (0-fill).
