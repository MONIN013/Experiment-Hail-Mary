# ControllerAlgorithm host tests

Build the allocation-free controller core and its direct-cascade reference tests without the TwinCAT SDK:

```powershell
& 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe' `
  ControllerCore\tests\ControllerAlgorithmTests.vcxproj `
  /p:Configuration=Release /p:Platform=x64

.\.tmp\cpp-tests\Release\ControllerAlgorithmTests.exe
```

The suite compares the two-HIGS implementation against a direct PI-lead / Butterworth cascade at 100 Hz and 8 kHz across 12,000 samples, including reset. It checks both HIGS elements against independent trimodal references through modes 1, 2, and 3; linear mode is checked separately with mode 0 diagnostics. It also covers section layout, independent state, both parameter validators, revision reset and rejection behavior, non-finite input, stage overflow recovery, and final-output overflow.

The separate host simulation regression links the runtime core to its simulation adapter and checks the 100,000-sample linear comparator, four-mode trajectories, diagnostics, and simulation ABI. Build and run it with:

```sh
g++ -std=c++17 -Wall -Wextra -Werror -O2 -IControllerCore \
  ControllerCore/ControllerAlgorithm.cpp simulations/higs_host.cpp simulations/higs_regression.cpp \
  -o /tmp/higs_regression
/tmp/higs_regression
```

These host checks do not build the TwinCAT module or validate a hardware deployment.
