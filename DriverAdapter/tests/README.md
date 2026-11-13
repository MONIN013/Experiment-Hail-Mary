# DriverAdapterAlgorithm host tests

The host test fixes the DriverAdapter scan contract independently of the TwinCAT SDK: the current 1.6 A Motor/Load preset, raw engineering-unit conversion, independent signs, reset-edge position capture, current clamp/gate/rounding/saturation, invalid and non-finite scales, exact ControlWord/StatusWord relay, explicit reset, and one million deterministic fixed-memory scans.

```powershell
& 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe' `
  DriverAdapter\tests\DriverAdapterAlgorithmTests.vcxproj `
  /p:Configuration=Release /p:Platform=x64

.\.tmp\driver-adapter-tests\Release\DriverAdapterAlgorithmTests.exe
```

The same host tests can run without the TwinCAT SDK:

```sh
g++ -std=c++17 -Wall -Wextra -Werror -O2 -IDriverAdapter -ICommonLib \
  DriverAdapter/DriverAdapterAlgorithm.cpp CommonLib/TcNumeric.cpp CommonLib/TcUnits.cpp \
  DriverAdapter/tests/DriverAdapterAlgorithmTests.cpp -o /tmp/driver_tests
/tmp/driver_tests
```

Safety tests cover same-scan travel, speed and relative-twist trips, both encoders,
the equality boundary, disabled current gates, latching across new PLC enable
requests, reset edges and invalid settings. Trip forces current command, target
torque and both ControlWords to zero. Ordinary experiment resets preserve the trip.
Only a new `SafetyResetRevision`, observed with current output disabled and neither
incoming ControlWord requesting operation enable, clears it. Unsafe clear requests
are consumed and require a fresh revision after stopping. The PLC subsequently
observes drive-not-ready; MATLAB abort/reset cleanup never writes this revision.
Twist is the difference between relative encoder positions captured at reset, so
this guard does not measure shaft preload already present at reset.
