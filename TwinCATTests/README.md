# TwinCAT PLC test system

repository root の `TwinCATTests.sln` / `TwinCATTests.tsproj` は、production VM 構成とは分離した PLC unit-test 専用 system である。production VM と同じ target NetId を使うが、PLC ADS port は 860～864 に分離する。

| ADS port | PLC project |
|---:|---|
| 860 | ExperimentSequencerTests |
| 861 | HeartbeatWatchdogTests |
| 862 | ModeOutputsTests |
| 863 | ModeManagerCoreTests |
| 864 | DriveStateTests |

全 project の `PRG_*Tests.testsPassed` と `failureCount` を ADS で読み取り、検証後は production `ExperimentHailMary.tsproj` を再度 activate する。
