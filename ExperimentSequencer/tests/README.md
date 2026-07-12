# ExperimentSequencer PLC tests

Repository root の `ExperimentSequencerTests.plcproj` は production sequencer core、adapter POU、enum を link する。書込み可能な小さい test GVL だけが deployed `AT %I*/AT %Q*` boundary を置き換え、I/O mapping なしで production state machine を検証する。

The two programs run in task order: production first, test monitor second. The scenarios cover table-length clamping, start-edge timing, repeat boundaries without a blank scan, final-sample hold, COMPLETE release, explicit abort, zero table length, zero repeat count, reset recovery, and reset priority over a simultaneous start edge.

Repository root の `TwinCATTests.sln` を TwinCAT XAE で build/activate し、ADS port 860 で次を確認する。

- `PRG_ExperimentSequencerTests.testsExecuted = TRUE`
- `PRG_ExperimentSequencerTests.testsPassed = TRUE`
- `PRG_ExperimentSequencerTests.failureCount = 0`
