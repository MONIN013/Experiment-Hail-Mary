# Technical Reference

> **位置づけ:** モジュール内部動作、GVL / ADS シンボル、tsproj mapping の実装寄り参照  
> **対象読者:** TwinCAT / MATLAB 実装者、デバッグ担当者  
> **更新条件:** 内部ロジック、シンボル、I/O 名、配線が変わったとき  
> **関連文書:** [SystemArchitecture](./SystemArchitecture.md) / [ExperimentProcedure](../operations/ExperimentProcedure.md)

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

`FB_ExperimentSequencerCore` が edge/FSM/index/repeat/output保持を所有し、`PRG_ExperimentSequencer` は `GVL_SEQ` table境界と現在sample読出しを担当する。開始要求の立上りscanは `IDLE -> PLAYING` だけを行い、table index 0 は次scanに出力する。

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
| 出力 | `appliedRevision` | `UDINT` | MATLAB / 診断 | active 設定として受理した revision |
| 出力 | `processedRevision` | `UDINT` | MATLAB / 診断 | 検証を完了した最新 revision |
| 出力 | `parameterErrorCode` | `UDINT` | MATLAB / 診断 | 最後の parameter apply 結果。`0` は成功、非 0 は reject |

### 2.2 CycleUpdate

1. `resetReq` 立ち上がりで全 SOS 段の内部状態をクリア
2. `error = refValue - positionAct`
3. active 設定の `sectionCount` 段を SOS 0 から順に cascade
4. `controlInput = u_fb + ffValue`
5. 非有限な入力・係数・状態更新・最終出力は `controlInput = 0.0` に倒す
6. biquad の係数または状態更新が非有限になった段は、その段の内部状態を 0 に戻して次周期から回復可能にする
7. `error` の入力または減算結果が非有限の場合は `error = 0.0`

`sectionCount = 0` は feedback identity とし、`u_fb = error` とする。SOS は最大 10 段であり、表現できる離散 Controller は最大 20 次である。

### 2.3 SOS parameter contract

MATLAB 側の公開形式は標準 SOS 行列と同じ `N x 6` の `[b0 b1 b2 a0 a1 a2]` とする。ControllerCore へは各段の `a0` を 1 に正規化し、段優先の `[b0, b1, b2, a1, a2]` を 10 段分、計 50 `LREAL` で送る。

| パラメータ | 型 | 意味 |
|---|---|---|
| `coefficients` | `ARRAY[0..49] OF LREAL` | 10 段分の正規化済み SOS 係数 |
| `sectionCount` | `UDINT` | 使用する先頭 SOS 段数。`0..10` |
| `applyRevision` | `UDINT` | staging 設定を active 化する revision |

MATLAB は `coefficients` と `sectionCount` を書いた後、`applyRevision` を最後に書く。ControllerCore は `applyRevision` の変化時だけ staging 値を検証し、検証に通った設定を active copy へ反映して全 10 段の内部状態をリセットする。検証完了時は成否にかかわらず `Outputs.processedRevision` を更新する。成功時はさらに `Outputs.appliedRevision` を更新して `Outputs.parameterErrorCode = 0` とし、検証失敗時は `parameterErrorCode` を非 0 にして従来の active copy と内部状態を維持する。これにより ADS 配列書込み途中、不正な係数、または以前の reject status を新 revision の結果として誤認しない。

### 2.4 ADS シンボル

* `ControllerCore_Obj1 (Module1).SosCoefficients`
* `ControllerCore_Obj1 (Module1).SosSectionCount`
* `ControllerCore_Obj1 (Module1).SosApplyRevision`
* `ControllerCore_Obj1 (Module1).Outputs.appliedRevision`
* `ControllerCore_Obj1 (Module1).Outputs.processedRevision`
* `ControllerCore_Obj1 (Module1).Outputs.parameterErrorCode`

---

## 3. DriverAdapter

### 3.1 active 実装

`DriverAdapter_Obj1 (Module1)` は **C++ TcCOM** として `.tsproj` に組み込まれており、DriverAdapter の唯一の実装正本である。

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

`DriverAdapterAlgorithm` が以下のscan処理とreset-edge位置offsetを所有し、TcCOM `Module1` はgenerated ADS型とのfield変換だけを行う。

1. `motorRaw` / `loadRaw` を `rad`, `rad/s`, `A` に変換
2. `resetReq` 立ち上がりで Motor/Load の位置オフセットを再キャプチャ
3. `motor.positionRel`, `load.positionRel` を更新
4. `currentCmd = ClampSymmetric(controlInput + distValue, MotorParams.maxCurrentA)`
5. `enableCurrentOutput && !playbackDone` のときだけ `currentCmd -> targetTorque [‰ rated]`
6. `motorControlWordOut = motorControlWordIn`, `loadControlWordOut = loadControlWordIn` を relay し、Motor/Load の `statusWord` を個別公開

### 3.5 Drive endpoint Mapping契約

両`.tsproj`はDriverAdapter末端の11 Linkだけを交換する。VM variantのOwnerは`TIXC^VirtualMotorCore^VirtualMotorCore_Obj1 (Module1)`、RealMotor scaffoldのOwnerは`TIID^RealMotorPdo^RealMotorPdo Instance`である。RealMotor側はI/O tree未確定のため現時点ではactivateできない。

* `motorRaw.positionActualValue <- VirtualMotorCore.Outputs.motor.positionActualValue`
* `motorRaw.velocityActualValue <- VirtualMotorCore.Outputs.motor.velocityActualValue`
* `motorRaw.torqueActualValue <- VirtualMotorCore.Outputs.motor.torqueActualValue`
* `motorRaw.statusWord <- VirtualMotorCore.Outputs.motor.statusWord`
* `loadRaw.positionActualValue <- VirtualMotorCore.Outputs.load.positionActualValue`
* `loadRaw.velocityActualValue <- VirtualMotorCore.Outputs.load.velocityActualValue`
* `loadRaw.torqueActualValue <- VirtualMotorCore.Outputs.load.torqueActualValue`
* `loadRaw.statusWord <- VirtualMotorCore.Outputs.load.statusWord`

VMでは`targetTorque`を`VirtualMotorCore.Inputs.motor.targetTorque`に接続する。実機PDOも同じINT/UINT/DINT境界を実装し、Motor/Load ControlWordを個別relayする。

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
| `Outputs.status.recordsWritten` | RAM buffer に正常受理したレコード数 |
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

### 6.4 Driver / Drive endpoint / Logger

以下の11 Linkは両variantで同一で、右辺OwnerだけがVirtualMotorCoreまたはRealMotorPdoへ切り替わる。

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

期待型はposition/velocity=`DINT`、torque/targetTorque=`INT`、status/controlWord=`UINT`とする。RealMotor PDO取込み後にこの型一致をXAE上で検証する。
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

### 7.1 PLC unit-test system

Repository root の `TwinCATTests.sln` / `TwinCATTests.tsproj` は production VM と同じ target NetId を使う専用 test configuration である。XAE で build/activate し、次の ADS port から各 `PRG_*Tests.testsExecuted`、`testsPassed`、`failureCount` を読む。検証後は必ず `ExperimentHailMary.tsproj` を再 activate/restart する。

| Port | Test project |
|---:|---|
| `860` | `ExperimentSequencerTests` |
| `861` | `HeartbeatWatchdogTests` |
| `862` | `ModeOutputsTests` |
| `863` | `ModeManagerCoreTests` |
| `864` | `DriveStateTests` |
