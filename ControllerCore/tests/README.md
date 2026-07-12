# ControllerAlgorithm host tests

These tests compile the allocation-free controller algorithm without the TwinCAT SDK and compare finite-input behavior against the pre-extraction implementation.

```powershell
& 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe' `
  ControllerCore\tests\ControllerAlgorithmTests.vcxproj `
  /p:Configuration=Release /p:Platform=x64

.\.tmp\cpp-tests\Release\ControllerAlgorithmTests.exe
```

The suite also verifies reset behavior and fail-safe recovery from non-finite inputs, coefficients, state updates, and output overflow.
