# ExperimentLogger Module Spec

> Module type: C++ TcCOM (Phase 3)
> Task: VirtualMotorTask 1 ms (Phase 1-3), ControlTask 125 us (Phase 4)
> AMS Port: 351

## Summary
ExperimentLogger is a binary file logger for experiment data. In current SIL operation, logging is controlled automatically by ModeManager via `Inputs.loggingReq`.

## Inputs
| Name | Type | Source | Notes |
|---|---|---|---|
| `torqueCmd` | `LREAL` | DriverAdapter | command torque |
| `refValue` | `LREAL` | ExperimentSequencer | reference |
| `ffValue` | `LREAL` | ExperimentSequencer | feedforward |
| `controlInput` | `LREAL` | ControllerCore | controller output |
| `error` | `LREAL` | ControllerCore | `ref - loadPosition` |
| `motorPosition` | `LREAL` | (Phase 4) | SIL: unconnected (0) |
| `motorVelocity` | `LREAL` | (Phase 4) | SIL: unconnected (0) |
| `motorTorqueAct` | `LREAL` | (Phase 4) | SIL: unconnected (0) |
| `loadPosition` | `LREAL` | ControllerCore `positionRel` | zero-based per run |
| `loadVelocity` | `LREAL` | VirtualMotor1 `velocityOut` | SIL load velocity |
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
| `ExperimentLogger_Obj1 (Module1).LogControl.logging` | `BOOL` | manual compatibility control (deprecated) |

Primary control path is `Inputs.loggingReq`. `LogControl.logging` is kept for backward compatibility.

## Runtime Behavior
1. On `loggingReq` rising edge: open file and start logging.
2. While active: append one record per cycle.
3. On `loggingReq` falling edge: flush remaining buffer and close file.
4. On `resetReq` rising edge: close session safely and reset runtime state.

## Mapping (SIL)
- `loadPosition <- ControllerCore.Outputs.positionRel`
- `loadVelocity <- VirtualMotorCore.Outputs.VirtualMotor1Outputs.velocityOut`
- `motorPosition/motorVelocity/motorTorqueAct` are unconnected in SIL (0-fill).
