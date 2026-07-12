# LoggerRecord host tests

The host test fixes the logger binary schema and ping-pong buffer invariants independently of the TwinCAT SDK. It verifies the 104-byte packed layout, schema version, timestamp construction, field mapping, serialized offsets, 8000-record boundary, pending-write append, commit, clear, and reset behavior. Rollback is accepted only before the new active face receives records; once it has data, rollback is rejected without changing the drainable pending state.

```powershell
& 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe' `
  ExperimentLogger\tests\LoggerRecordTests.vcxproj `
  /p:Configuration=Release /p:Platform=x64

.\.tmp\logger-tests\Release\LoggerRecordTests.exe
```
