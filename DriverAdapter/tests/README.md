# DriverAdapterAlgorithm host tests

The host test fixes the DriverAdapter scan contract independently of the TwinCAT SDK: the current 1.6 A Motor/Load preset, raw engineering-unit conversion, independent signs, reset-edge position capture, current clamp/gate/rounding/saturation, invalid and non-finite scales, exact ControlWord/StatusWord relay, explicit reset, and one million deterministic fixed-memory scans.

```powershell
& 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe' `
  DriverAdapter\tests\DriverAdapterAlgorithmTests.vcxproj `
  /p:Configuration=Release /p:Platform=x64

.\.tmp\driver-adapter-tests\Release\DriverAdapterAlgorithmTests.exe
```
