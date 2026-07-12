# Heartbeat watchdog PLC tests

Repository root の `HeartbeatWatchdogTests.plcproj` は production `FB_HeartbeatWatchdog.TcPOU` を複製せず link する。test program は function block を繰り返し呼び、次を検証する。

- disabled counter synchronization;
- timeout on exactly the configured scan;
- one-scan `tripEdge` behavior;
- heartbeat recovery;
- disable/rearm and a second trip;
- zero-tick timeout behavior.

Repository root の `TwinCATTests.sln` を TwinCAT XAE で build/activate し、ADS port 861 で確認する。

- `PRG_HeartbeatWatchdogTests.testsExecuted = TRUE`
- `PRG_HeartbeatWatchdogTests.testsPassed = TRUE`
- `PRG_HeartbeatWatchdogTests.failureCount = 0`

## Mode output policy

Repository root の `ModeOutputsTests.plcproj` は production `E_ModeState`、`ST_ModeOutputs`、`GVL_MODE`、`F_DeriveModeOutputs` を link する。5 state の全 output table と、連続評価で前 state の field を保持しないことを検証する。

ADS port 862 で確認する。

- `PRG_ModeOutputsTests.testsExecuted = TRUE`
- `PRG_ModeOutputsTests.testsPassed = TRUE`
- `PRG_ModeOutputsTests.failureCount = 0`

## Mode manager core

Repository root の `ModeManagerCoreTests.plcproj` は production mode enum、action DUT、heartbeat watchdog、`FB_ModeManagerCore` を link する。request latch、readiness gate、explicit abort、明示 reset までの DONE latch、drive-loss priority、2 scan reset pulse、reset/watchdog priority、one-shot action pulse を検証する。

ADS port 863 で確認する。

- `PRG_ModeManagerCoreTests.testsExecuted = TRUE`
- `PRG_ModeManagerCoreTests.testsPassed = TRUE`
- `PRG_ModeManagerCoreTests.failureCount = 0`

## Drive state control

Repository root の `DriveStateTests.plcproj` は production `E_DriveState`、`F_DecodeDriveState`、`FB_StateMachineControl` を link する。status decode、disable、shutdown、switch-on、enable-op、1 scan fault reset、再 fault、UNKNOWN safe command を検証する。

ADS port 864 で確認する。

- `PRG_DriveStateTests.testsExecuted = TRUE`
- `PRG_DriveStateTests.testsPassed = TRUE`
- `PRG_DriveStateTests.failureCount = 0`
