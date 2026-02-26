# Module 不整合メモ（2026-02-26）

`ArchitectureSpec.md` と現行実装/`tsproj` を見比べた、ざっくり差分メモ。

## 先に結論

- 実装自体はかなり揃っている
- 主要な不整合は「タスク配置」と「統合設定（ExperimentLogger の CyclicCaller 未設定）」
- `ExperimentLogger` のタイムスタンプ刻み 1ms 固定問題は **解消済み**（タスク周期自動取得）

## 未解消の不整合（優先度順）

### 1. `ExperimentSequencer` / `DriverAdapter` が `VirtualMotorTask` に載っていない

- docs では Phase 1–3 は `ControllerCore, ExperimentSequencer, DriverAdapter, VirtualMotorCore` を `VirtualMotorTask` (1 ms) に配置する想定
  - `docs/ArchitectureSpec.md:496`
- 現在の `tsproj` では `ExperimentSequencer` / `DriverAdapter` は `#x02010060`（`PlcTask2`）に割当
  - `ExperimentHailMary.tsproj:279`
  - `ExperimentHailMary.tsproj:390`
  - `ExperimentHailMary.tsproj:448`
- 一方 `ControllerCore` / `VirtualMotorCore` は `#x02010040`（`VirtualMotorTask`）側
  - `ExperimentHailMary.tsproj:273`
  - `ExperimentHailMary.tsproj:647`
  - `ExperimentHailMary.tsproj:669`

影響:
- docs の「同一 1ms RT チェーン」前提から外れる
- サンプル時刻整合/遅延評価の前提が崩れる可能性あり

### 2. `ExperimentLogger` インスタンスはあるが `CyclicCaller` 未設定

- インスタンス自体は `tsproj` に存在
  - `ExperimentHailMary.tsproj:903`
- ただし `CyclicCaller` が `#x00000000`（未接続）
  - `ExperimentHailMary.tsproj:1070`
  - `ExperimentHailMary.tsproj:1071`
- docs の想定では Phase 3 以降は RT タスク上で動作
  - `docs/ArchitectureSpec.md:26`
  - `docs/ArchitectureSpec.md:496`

影響:
- `CycleUpdate()` が回らず、ロギング実動作しない（統合未完）

### 3. `ControllerCore` の `enablePid` 初期値が docs と不一致

- docs では `EnableParams.enable_pid` のデフォルトは `true`
  - `docs/ArchitectureSpec.md:144`
- `tsproj` 初期値は `FALSE`
  - `ExperimentHailMary.tsproj:857`
- 実装も `m_EnableParams` をゼロ初期化しているため初期値は `false`
  - `ControllerCore/Module1.cpp:102`

影響:
- 初期起動時に PID がバイパスされる（意図しない「全部スルー」状態になりやすい）

### 4. `ExperimentSequencer.modeFlags` が docs の I/O 接続前提とズレ

- docs では `ModeManager.mode_flags -> ExperimentSequencer.mode_flags` を定義
  - `docs/ArchitectureSpec.md:188`
  - `docs/ArchitectureSpec.md:289`
- 実装側 `GVL_SEQ.modeFlags` は存在するが `AT %I*` ではない
  - `ExperimentSequencer/GVLs/GVL_SEQ.TcGVL:27`
- `experimentActive` / `playbackDone` は AT リンクあり
  - `ExperimentSequencer/GVLs/GVL_SEQ.TcGVL:33`
  - `ExperimentSequencer/GVLs/GVL_SEQ.TcGVL:36`

影響:
- 現状ロジックは `experimentActive` 主体で動くが、docs 記載の Mode flag 連携前提とは一致しない

### 5. `VirtualMotorCore` の公開名が docs 記載とズレ（命名差）

- 実装は 2 軸構成 + `mass/damping/torqueConstant` 命名
  - `VirtualMotorCore/VirtualMotorCoreServices.h:33`
  - `VirtualMotorCore/VirtualMotorCoreServices.h:65`
  - `VirtualMotorCore/VirtualMotorCoreServices.h:75`
- docs 側の記載は単軸寄り + `M/D/Kt` 表記
  - `docs/ArchitectureSpec.md:453`
  - `docs/ArchitectureSpec.md:268`

影響:
- マッピング/ADS スクリプトを docs の名前で書くとズレる
- 実装が悪いというより docs 更新不足寄り

## 解消済み（今回反映）

### `ExperimentLogger` のタイムスタンプ刻み

- 以前: 1ms 固定 (`kTimestampStepNs`)
- 現在: `ITcTask::GetCycleTime()` からタスク周期を自動取得
  - `ExperimentLogger/Module1.cpp:365`
  - `ExperimentLogger/Module1.cpp:487`
- フォールバックは 1ms
  - `ExperimentLogger/Module1.h:91`

## 次に直す順番（雑に）

1. `ExperimentSequencer` / `DriverAdapter` を `VirtualMotorTask` 側へ統合
2. `ExperimentLogger` の `CyclicCaller` を設定（Phase 3 使用時）
3. `ControllerCore.enablePid` の初期値を docs か実装のどちらかに統一
4. docs の `VirtualMotorCore` 命名・I/O 表記を現実装に合わせて更新
