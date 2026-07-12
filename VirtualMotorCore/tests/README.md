# VirtualMotorAlgorithm host tests

The host test fixes the VirtualMotorCore scan contract independently of the TwinCAT SDK: CiA 402 transitions and status words, fault-reset edges, command/velocity/shaft-torque faults, semi-implicit integration order, raw quantization, plant-state carry-over across drive disable/re-enable, invalid-plant behavior, the exact current 0.32 N-m rated-torque fallback, explicit reset, and one million deterministic fixed-memory scans.

```powershell
& 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe' `
  VirtualMotorCore\tests\VirtualMotorAlgorithmTests.vcxproj `
  /p:Configuration=Release /p:Platform=x64

.\.tmp\virtual-motor-tests\Release\VirtualMotorAlgorithmTests.exe
```
