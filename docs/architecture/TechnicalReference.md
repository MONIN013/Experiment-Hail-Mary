# Technical Reference

> **位置づけ:** モジュール内部動作、GVL / ADS シンボル、tsproj mapping の実装寄り参照  
> **対象読者:** TwinCAT / MATLAB 実装者、デバッグ担当者  
> **更新条件:** 内部ロジック、シンボル、I/O 名、配線が変わったとき  
> **関連文書:** [SystemArchitecture](./SystemArchitecture.md) / [ExperimentProcedure](../operations/ExperimentProcedure.md) / [OpenIssues](../status/OpenIssues.md)

本ドキュメントは checked-in ソースと `ExperimentHailMary.tsproj` / `ExperimentHailMary.RealMotor.tsproj` を前提に、**現在の実装が実際に何を公開しているか**をまとめた技術参照である。運用手順は [ExperimentProcedure](../operations/ExperimentProcedure.md) を参照。

---

## 1. ExperimentSequencer

### 1.1 `GVL_SEQ` 公開変数

| 変数 | 型 | 方向 | 説明 |
|---|---|---|---|
| `refTable` | `ARRAY[0..99999] OF LREAL` | ADS Write | 位置指令テーブル |
| `ffTable` | `ARRAY[0..99999] OF LREAL` | ADS Write | FF テーブル |
| `distTable` | `ARRAY[0..99999] OF LREAL` | ADS Write | 外乱テーブル |
| `tableLen` | `UDINT` | ADS Write | 要求長 |
| `tableLenClamped` | `UDINT` | ADS Read | 実効長 |
| `repeatCount` | `UDINT` | ADS Write | trial 繰返し回数 |
| `trialIndex` | `UDINT` | ADS Read | 現在 trial |
| `idx` | `UDINT` | ADS Read | 現 trial 内インデックス |
| `refValue` | `LREAL` | 出力 | 現在の ref |
| `ffValue` | `LREAL` | 出力 | 現在の ff |
| `distValue` | `LREAL` | 出力 | 現在の dist |
| `resetReq` | `BOOL` | 入力 | ModeManager からの reset pulse |
| `experimentActive` | `BOOL` | 入力 | ModeManager 実験実行中 |
| `playbackDone` | `BOOL` | 出力 | 最終 trial 完了 |
| `seqError` | `BOOL` | 出力 | `seqState = FAULT` |
| `seqState` | `E_SeqState` | ADS Read | `IDLE / PLAYING / COMPLETE / FAULT` |

### 1.2 `PRG_ExperimentSequencer` の実際の挙動

* `resetReq` は **立ち上がりエッジ**で扱う。
* `startEdge := experimentActive AND NOT cmdActivePrev`
* `tableLenLocal = min(tableLen, N_REF_MAX, N_FF_MAX, N_DIST_MAX)`
* `tableLenLocal = 0` または `repeatCount = 0` の場合は `FAULT`
* `PLAYING` 中は `idx` を 1 サンプルずつ進める。
* trial 途中の終端では `idx := 0`, `trialIndex++`
* 最終 trial 完了で `playbackDone := TRUE`, `seqState := COMPLETE`
* `IDLE` / `FAULT` では `refValue`, `ffValue`, `distValue` をゼロへ戻す

> 現行コードには `GVL_SEQ.modeFlags`、`rearmRequired`、最終値保持ベースの旧 single-pass 実装は存在しない。

---

## 2. ControllerCore

### 2.1 Data Area I/O

| 区分 | ポート | 型 | ソース/宛先 | 説明 |
|---|---|---|---|---|
| 入力 | `refValue` | `LREAL` | `GVL_SEQ.refValue` | 位置指令 [rad] |
| 入力 | `ffValue` | `LREAL` | `GVL_SEQ.ffValue` | FF 値 [A] |
| 入力 | `positionAct` | `LREAL` | `DriverAdapter.Outputs.load.positionRel` | Load 側相対位置 [rad] |
| 入力 | `resetReq` | `BOOL` | `MAIN.resetOut` | 内部状態リセット |
| 出力 | `controlInput` | `LREAL` | DriverAdapter / ExperimentLogger | 制御出力 [A] |
| 出力 | `error` | `LREAL` | ExperimentLogger | 誤差 [rad] |

### 2.2 CycleUpdate

1. `resetReq` 立ち上がりで biquad の内部状態をクリア
2. `error = refValue - positionAct`
3. `PID -> Lead -> Notch -> Reso`
4. `controlInput = y + ffValue`
5. 非有限値は `controlInput = 0.0`

### 2.3 ADS シンボル

* `ControllerCore_Obj1 (Module1).PIDParams.*`
* `ControllerCore_Obj1 (Module1).LeadParams.*`
* `ControllerCore_Obj1 (Module1).NotchParams.*`
* `ControllerCore_Obj1 (Module1).ResoParams.*`
* `ControllerCore_Obj1 (Module1).EnableParams.*`

---

## 3. DriverAdapter

### 3.1 active 実装

`DriverAdapter_Obj1 (Module1)` は **C++ TcCOM** として `.tsproj` に組み込まれている。`DriverAdapterPLC/` の GVL / POU は現行 deployment の正本ではない。

### 3.2 `Module1Inputs`

| フィールド | 型 | 説明 |
|---|---|---|
| `motorRaw` | `ST_DriverRawSignals` | Motor raw `position/velocity/torque/status` |
| `loadRaw` | `ST_DriverRawSignals` | Load raw `position/velocity/torque/status` |
| `controlInput` | `double` | Controller 出力 [A] |
| `distValue` | `double` | 外乱 [A] |
| `motorControlWordIn` | `USHORT` | Motor CiA 402 ControlWord |
| `loadControlWordIn` | `USHORT` | Load CiA 402 ControlWord |
| `enableCurrentOutput` | `bool` | 電流ゲート |
| `playbackDone` | `bool` | same-task 完了通知 |
| `resetReq` | `bool` | オフセット再キャプチャ |

### 3.3 `Module1Outputs`

| フィールド | 型 | 説明 |
|---|---|---|
| `motor`, `load` | `ST_DriverEngineeringSignals` | 工学単位変換済み信号 |
| `currentCmd` | `double` | `clamp(controlInput + distValue)` 後の指令電流 [A] |
| `targetTorque` | `SHORT` | 指令トルク [‰ rated] |
| `motorControlWordOut`, `loadControlWordOut` | `USHORT` | relay |
| `motorStatusWordOut`, `loadStatusWordOut` | `USHORT` | relay |

### 3.4 CycleUpdate

1. `motorRaw` / `loadRaw` を `rad`, `rad/s`, `A` に変換
2. `resetReq` 立ち上がりで Motor/Load の位置オフセットを再キャプチャ
3. `motor.positionRel`, `load.positionRel` を更新
4. `currentCmd = ClampSymmetric(controlInput + distValue, MotorParams.maxCurrentA)`
5. `enableCurrentOutput && !playbackDone` のときだけ `currentCmd -> targetTorque [‰ rated]`
6. `motorControlWordOut = motorControlWordIn`, `loadControlWordOut = loadControlWordIn` を relay し、Motor/Load の `statusWord` を個別公開

### 3.5 現行 SIL 配線の注記

`.tsproj` の現行 SIL 配線では `VirtualMotorCore.Outputs.motor/*` を Motor、`VirtualMotorCore.Outputs.load/*` を Load として扱う。

* `motorRaw.positionActualValue <- VirtualMotorCore.Outputs.motor.positionActualValue`
* `motorRaw.velocityActualValue <- VirtualMotorCore.Outputs.motor.velocityActualValue`
* `motorRaw.torqueActualValue <- VirtualMotorCore.Outputs.motor.torqueActualValue`
* `motorRaw.statusWord <- VirtualMotorCore.Outputs.motor.statusWord`
* `loadRaw.positionActualValue <- VirtualMotorCore.Outputs.load.positionActualValue`
* `loadRaw.velocityActualValue <- VirtualMotorCore.Outputs.load.velocityActualValue`
* `loadRaw.torqueActualValue <- VirtualMotorCore.Outputs.load.torqueActualValue`
* `loadRaw.statusWord <- VirtualMotorCore.Outputs.load.statusWord`

`targetTorque` は `VirtualMotorCore.Inputs.motor.targetTorque` にのみ接続される。Motor/Load ControlWord は個別に relay され、Load 軸は CiA 状態追従と fault 監視のみを担当する。

---

## 4. VirtualMotorCore

### 4.1 パラメータ公開

* `PlantParameter` は `CreateSymbol="true"` のため通常の symbol browse 対象

### 4.2 主要パラメータ

| シンボル | 型 | 説明 |
|---|---|---|
| `PlantParameter.motor.*` | `LREAL/UDINT` | Motor 慣性・減衰・制限値・換算基準 |
| `PlantParameter.load.*` | `LREAL/UDINT` | Load 慣性・減衰・制限値・換算基準 |
| `PlantParameter.coupling.*` | `LREAL` | ねじり剛性・減衰 |
| `PlantParameter.taskDtNs` | `ULINT` | タスク周期 |

---

## 5. ExperimentLogger

### 5.1 入力

| 入力 | 説明 |
|---|---|
| `Inputs.record.currentCmd` | DriverAdapter clamp 後 command [A] |
| `Inputs.record.refValue`, `Inputs.record.ffValue`, `Inputs.record.distValue` | Sequencer 出力 |
| `Inputs.record.controlInput`, `Inputs.record.error` | ControllerCore 出力 |
| `Inputs.record.motor.position`, `Inputs.record.motor.velocity` | DriverAdapter motor 側信号 |
| `Inputs.record.motor.currentAct` | DriverAdapter motor 電流 |
| `Inputs.record.load.position`, `Inputs.record.load.velocity` | DriverAdapter load 側信号 |
| `Inputs.control.resetReq` | ModeManager reset |
| `Inputs.control.preArmReq` | file pre-open |
| `Inputs.control.loggingReq` | 記録 / close |
| `Inputs.control.playbackDone` | same-task 追記停止 fast-path |

### 5.2 出力

| 出力 | 説明 |
|---|---|
| `Outputs.status.recordsWritten` | 書込み済みレコード数 |
| `Outputs.status.fileSizeKb` | ファイルサイズ |
| `Outputs.status.errorCode` | エラーコード |
| `Outputs.status.fileReleased` | close 完了 |
| `Outputs.status.loggerReady` | pre-open 完了 / write 可能 |

### 5.3 バイナリ形式

1 レコード = 104 bytes

`seq`, `reservedPad0` (= schema version 2), `tNs`, `motorPosition`, `motorVelocity`, `motorCurrentAct`, `loadPosition`, `loadVelocity`, `currentCmd`, `error`, `refValue`, `ffValue`, `distValue`, `controlInput`

---

## 6. tsproj Mapping Summary

### 6.1 ModeManager ↔ ExperimentSequencer

* `MAIN.experimentActiveOut -> GVL_SEQ.experimentActive`
* `MAIN.resetOut -> GVL_SEQ.resetReq`
* `GVL_SEQ.playbackDone -> MAIN.seqPlaybackDone`

### 6.2 Sequencer / Controller / Driver

* `GVL_SEQ.refValue -> ControllerCore.Inputs.refValue`
* `GVL_SEQ.ffValue -> ControllerCore.Inputs.ffValue`
* `GVL_SEQ.distValue -> DriverAdapter.Inputs.distValue`
* `ControllerCore.Outputs.controlInput -> DriverAdapter.Inputs.controlInput`
* `DriverAdapter.Outputs.load.positionRel -> ControllerCore.Inputs.positionAct`

### 6.3 ModeManager / Driver / Logger

* `MAIN.motorCtrlWord -> DriverAdapter.Inputs.motorControlWordIn`
* `MAIN.loadCtrlWord -> DriverAdapter.Inputs.loadControlWordIn`
* `MAIN.enableCurrentOut -> DriverAdapter.Inputs.enableCurrentOutput`
* `MAIN.resetOut -> DriverAdapter.Inputs.resetReq`
* `DriverAdapter.Outputs.motorStatusWordOut -> MAIN.motorStatWord`
* `DriverAdapter.Outputs.loadStatusWordOut -> MAIN.loadStatWord`
* `MAIN.preArmOut -> ExperimentLogger.Inputs.control.preArmReq`
* `MAIN.experimentActiveOut -> ExperimentLogger.Inputs.control.loggingReq`
* `MAIN.resetOut -> ExperimentLogger.Inputs.control.resetReq`
* `ExperimentLogger.Outputs.status.loggerReady -> MAIN.loggerReadyIn`
* `ExperimentLogger.Outputs.status.fileReleased -> MAIN.loggerFileReleasedIn`
* `ExperimentLogger.Outputs.status.errorCode -> MAIN.loggerErrorCodeIn`

### 6.4 Driver / VirtualMotor / Logger

* `DriverAdapter.Outputs.targetTorque -> VirtualMotorCore.Inputs.motor.targetTorque`
* `DriverAdapter.Outputs.motorControlWordOut -> VirtualMotorCore.Inputs.motor.controlWord`
* `DriverAdapter.Outputs.loadControlWordOut -> VirtualMotorCore.Inputs.load.controlWord`
* `VirtualMotorCore.Outputs.motor.positionActualValue -> DriverAdapter.Inputs.motorRaw.positionActualValue`
* `VirtualMotorCore.Outputs.motor.velocityActualValue -> DriverAdapter.Inputs.motorRaw.velocityActualValue`
* `VirtualMotorCore.Outputs.motor.torqueActualValue -> DriverAdapter.Inputs.motorRaw.torqueActualValue`
* `VirtualMotorCore.Outputs.motor.statusWord -> DriverAdapter.Inputs.motorRaw.statusWord`
* `VirtualMotorCore.Outputs.load.positionActualValue -> DriverAdapter.Inputs.loadRaw.positionActualValue`
* `VirtualMotorCore.Outputs.load.velocityActualValue -> DriverAdapter.Inputs.loadRaw.velocityActualValue`
* `VirtualMotorCore.Outputs.load.torqueActualValue -> DriverAdapter.Inputs.loadRaw.torqueActualValue`
* `VirtualMotorCore.Outputs.load.statusWord -> DriverAdapter.Inputs.loadRaw.statusWord`
* `DriverAdapter.Outputs.currentCmd -> ExperimentLogger.Inputs.record.currentCmd`
* `DriverAdapter.Outputs.load.positionRel -> ExperimentLogger.Inputs.record.load.position`
* `DriverAdapter.Outputs.load.velocityAct -> ExperimentLogger.Inputs.record.load.velocity`
* `DriverAdapter.Outputs.motor.currentAct -> ExperimentLogger.Inputs.record.motor.currentAct`
* `DriverAdapter.Outputs.motor.positionRel -> ExperimentLogger.Inputs.record.motor.position`
* `DriverAdapter.Outputs.motor.velocityAct -> ExperimentLogger.Inputs.record.motor.velocity`

---

## 7. ADS Port Reference

| Port | 主用途 | 状態 |
|---|---|---|
| `351` | ControllerCore / DriverAdapter / VirtualMotorCore / ExperimentLogger | active |
| `852` | ModeManager (`GVL_MODE`, `MAIN.*`) | active |
| `853` | ExperimentSequencer (`GVL_SEQ`) | active |
| `851` | discovery 用の明示 probe | active orchestration の正本ではない |

> `851` を見る場合は discovery 用スクリプトのローカル指定でのみ扱う。現行の active 契約と verify の正本は `351/852/853` である。
