# ControllerAlgorithm host tests

These tests compile the allocation-free controller algorithm without the TwinCAT SDK and compare the fixed ten-section SOS cascade against an independent reference implementation.

```powershell
& 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe' `
  ControllerCore\tests\ControllerAlgorithmTests.vcxproj `
  /p:Configuration=Release /p:Platform=x64

.\.tmp\cpp-tests\Release\ControllerAlgorithmTests.exe
```

The suite also verifies revision commits, rejected-payload isolation, identity and zero controllers, state reset, and fail-safe recovery from non-finite inputs, state updates, and output overflow.

HIGS checks cover all three digital modes, sector invariance, odd symmetry,
insertion before/between/after SOS sections, reset, rejected-parameter isolation,
and the sampling bound. A quadratic-sector reference independently checks 20,000
samples against the interval-based implementation.

Without the TwinCAT SDK, the same numerical core can be checked on Linux:

```sh
g++ -std=c++17 -Wall -Wextra -Werror -O2 -IControllerCore \
  ControllerCore/ControllerAlgorithm.cpp ControllerCore/tests/ControllerAlgorithmTests.cpp \
  -o /tmp/controller_tests
/tmp/controller_tests
```

This host test does not build the TwinCAT module or validate a hardware deployment.
