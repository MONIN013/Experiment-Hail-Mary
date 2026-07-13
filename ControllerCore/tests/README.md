# ControllerAlgorithm host tests

These tests compile the allocation-free controller algorithm without the TwinCAT SDK and compare the fixed ten-section SOS cascade against an independent reference implementation.

```powershell
& 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe' `
  ControllerCore\tests\ControllerAlgorithmTests.vcxproj `
  /p:Configuration=Release /p:Platform=x64

.\.tmp\cpp-tests\Release\ControllerAlgorithmTests.exe
```

The suite also verifies revision commits, rejected-payload isolation, identity and zero controllers, state reset, and fail-safe recovery from non-finite inputs, state updates, and output overflow.
