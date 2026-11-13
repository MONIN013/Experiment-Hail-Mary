# DriverAdapter

> **位置づけ:** Driver 境界の変換・中継・差異吸収を定義する active C++ TcCOM モジュール仕様  
> **対象読者:** TcCOM 実装者、Drive I/O を変更する設計者  
> **更新条件:** I/O 契約、変換式、Driver 抽象化が変わったとき  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) / [TechnicalReference](../architecture/TechnicalReference.md) / [VirtualMotorCore](./VirtualMotorCore.md) / [HigsExperiment](../operations/HigsExperiment.md)

---

## 1. 概要

DriverAdapter は **ドライバ差異吸収層** である。現行の active 実装は TwinCAT の **C++ TcCOM** (`DriverAdapter_Obj1 (Module1)`) であり、Drive 境界の raw 信号を工学単位へ変換し、上流制御へ統一 I/F を提供する。

`DriverAdapterAlgorithm` が raw 変換、reset edge と Motor/Load 位置 offset、current clamp/gate/量子化、ControlWord/StatusWord relay、位置・速度・ねじれの保護を固定メモリの純粋 C++ として所有する。TcCOM `Module1` は generated ADS 型との field-by-field 変換と 8 kHz cyclic 呼出しを担当する。

本モジュールは **Motor + Load の 2 チャネル専用** とし、外部契約は current ベース `[A]` を維持する。Drive 境界では `targetTorque` / `torqueActualValue` を **`‰ rated`** 整数値で扱う。

> DriverAdapter の正本は C++ TcCOM `DriverAdapter/` であり、両 TwinCAT project は同じモジュール契約を使用する。

---

## 2. 機能一覧

| # | 機能 | 説明 |
|---|---|---|
| 1 | Motor raw → 工学単位変換 | `position`, `velocity`, `torque/status` を Motor 側で変換する |
| 2 | Load raw → 工学単位変換 | `position`, `velocity`, `torque/status` を Load 側で変換する |
| 3 | 相対位置化 | `resetReq` 立上りで Motor/Load の位置オフセットを再キャプチャする |
| 4 | 外乱加算 | `controlInput + distValue` を current `[A]` で合成する |
| 5 | 電流クランプ | `MotorParams.maxCurrentA` で `currentCmd` を制限する |
| 6 | 電流ゲート | `enableCurrentOutput = FALSE` または `playbackDone = TRUE` のとき `targetTorque := 0` |
| 7 | CW/SW relay | `motorControlWordIn/loadControlWordIn` を個別 relay し、Motor/Load の `statusWord` を個別公開する |
| 8 | 保護停止 | 位置・速度・ねじれの上限超過を保持し、指令電流と両軸の ControlWord を 0 にする |

---

## 3. パラメータ

### 3.1 `MotorParams`

| フィールド | 型 | 単位 | 説明 |
|---|---|---|---|
| `encoderResolution` | `UDINT` | pulses/rev | Motor 側エンコーダ分解能 |
| `ratedCurrentA` | `LREAL` | A | Motor 定格電流 |
| `maxCurrentA` | `LREAL` | A | 電流クランプ上限 |
| `positionSign` | `DINT` | -1/+1 | 位置符号 |
| `velocitySign` | `DINT` | -1/+1 | 速度符号 |
| `currentSign` | `DINT` | -1/+1 | 電流符号 |
| `enableRelativePosition` | `BOOL` | - | 相対位置化の有効化 |

### 3.2 `LoadParams`

| フィールド | 型 | 単位 | 説明 |
|---|---|---|---|
| `encoderResolution` | `UDINT` | pulses/rev | Load 側エンコーダ分解能 |
| `ratedCurrentA` | `LREAL` | A | Load 側電流換算基準 |
| `maxCurrentA` | `LREAL` | A | Load 側クランプ上限 |
| `positionSign` | `DINT` | -1/+1 | 位置符号 |
| `velocitySign` | `DINT` | -1/+1 | 速度符号 |
| `currentSign` | `DINT` | -1/+1 | 電流符号 |
| `enableRelativePosition` | `BOOL` | - | 相対位置化の有効化 |

> `ratedCurrentA <= 0` または `encoderResolution <= 0` の場合、そのチャネルの該当変換は 0 出力へ倒す。
> 現行既定は `MADLT11BF + MHMF011L1A2` 相当で、Motor/Load とも `encoderResolution=8388608`、`ratedCurrentA=1.6`、`maxCurrentA=1.6` とする。

### 3.3 `SafetyLimits`

`ST_DriverSafetyLimits` の各値は `LREAL` で、既定値はすべて `0`。各項目の `0` はその保護を無効にする。設定は電流出力を停止してから書き込み、readback で確認する。

| フィールド | 単位 | 上限の対象 |
|---|---|---|
| `maxPositionRad` | rad | Motor / Load の `abs(positionRel)` |
| `maxVelocityRadS` | rad/s | Motor / Load の `abs(velocityAct)` |
| `maxTwistRad` | rad | `abs(motor.positionRel - load.positionRel)` |

上限と等しい値は許容する。負値・NaN・Inf は無効化として扱わず、電流ゲートが開いた周期に保護停止する。いずれかの保護が有効なときは、片方でも `encoderResolution=0` なら同様に停止する。

### 3.4 `SafetyResetRevision`

`UDINT`、既定値 `0`。通常の `resetReq` は位置オフセットだけを更新し、保護停止のラッチを解除しない。解除は `SafetyResetRevision` の変化を観測した周期に、次の条件がすべて成立するときだけ行う。

- `enableCurrentOutput = FALSE`
- `(motorControlWordIn AND 16#000F) <> 16#000F`
- `(loadControlWordIn AND 16#000F) <> 16#000F`

条件を満たさない解除要求も処理済みとする。停止後に同じ revision で自動解除されることはなく、再度 revision を更新する必要がある。MATLAB の通常終了・abort・cleanup ではこの値を書かない。停止原因を確認した操作者が XAE から明示的に更新する手順は [HigsExperiment](../operations/HigsExperiment.md) を参照。

---

## 4. I/O 仕様

### 4.1 入力 (`Module1Inputs`)

#### Motor raw

| フィールド | 型 | 説明 |
|---|---|---|
| `motorRaw.positionActualValue` | `DINT` | Motor 実位置 [pulses] |
| `motorRaw.velocityActualValue` | `DINT` | Motor 実速度 [pulses/s] |
| `motorRaw.torqueActualValue` | `INT` | Motor 実トルク [‰ rated] |
| `motorRaw.statusWord` | `UINT` | Motor StatusWord |

#### Load raw

| フィールド | 型 | 説明 |
|---|---|---|
| `loadRaw.positionActualValue` | `DINT` | Load 実位置 [pulses] |
| `loadRaw.velocityActualValue` | `DINT` | Load 実速度 [pulses/s] |
| `loadRaw.torqueActualValue` | `INT` | Load 実トルク [‰ rated] |
| `loadRaw.statusWord` | `UINT` | Load StatusWord |

#### 制御側

| フィールド | 型 | 説明 |
|---|---|---|
| `controlInput` | `LREAL` | Controller 出力 [A] |
| `distValue` | `LREAL` | 外乱 [A] |
| `motorControlWordIn` | `UINT` | Motor CiA 402 ControlWord |
| `loadControlWordIn` | `UINT` | Load CiA 402 ControlWord |
| `enableCurrentOutput` | `BOOL` | 電流ゲート |
| `playbackDone` | `BOOL` | same-task 完了通知 |
| `resetReq` | `BOOL` | オフセット再キャプチャ要求 |

### 4.2 出力 (`Module1Outputs`)

#### 工学単位

| フィールド | 型 | 説明 |
|---|---|---|
| `motor.positionAbs` | `LREAL` | Motor 絶対位置 [rad] |
| `motor.positionRel` | `LREAL` | Motor 相対位置 [rad] |
| `motor.velocityAct` | `LREAL` | Motor 速度 [rad/s] |
| `motor.currentAct` | `LREAL` | Motor 実電流 [A] |
| `load.positionAbs` | `LREAL` | Load 絶対位置 [rad] |
| `load.positionRel` | `LREAL` | Load 相対位置 [rad] |
| `load.velocityAct` | `LREAL` | Load 速度 [rad/s] |
| `load.currentAct` | `LREAL` | Load 実電流 [A] |
| `currentCmd` | `LREAL` | `clamp(controlInput + distValue)` 後の指令電流 [A]。保護停止中は 0 |
| `motorControlWordOut` | `UINT` | Motor ControlWord relay。保護停止中は 0 |
| `loadControlWordOut` | `UINT` | Load ControlWord relay。保護停止中は 0 |
| `motorStatusWordOut` | `UINT` | Motor StatusWord relay |
| `loadStatusWordOut` | `UINT` | Load StatusWord relay |
| `safetyTrip` | `BOOL` | 保護停止のラッチが有効 |
| `safetyCode` | `UDINT` | 保持している停止原因。コードは 5.3 参照 |

#### Drive 側 raw

| フィールド | 型 | 説明 |
|---|---|---|
| `targetTorque` | `INT` | Motor 側指令 [‰ rated]。電流ゲート閉鎖時と保護停止中は 0 |

---

## 5. 変換ロジック

### 5.1 基本式

| 方向 | 変換 | 数式 |
|---|---|---|
| raw → rad | position | `theta = sign * raw * 2pi / encoderResolution` |
| raw → rad/s | velocity | `omega = sign * raw * 2pi / encoderResolution` |
| raw → A | current | `current = sign * torquePermille * ratedCurrentA / 1000` |
| A → permille | targetTorque | `permille = sign * currentCmd * 1000 / ratedCurrentA` |

### 5.2 実行順

1. `motorRaw`, `loadRaw` を工学単位へ変換する。
2. `resetReq` 立上りで Motor/Load の位置オフセットを再キャプチャする。
3. `enableRelativePosition` が有効なら相対位置を公開する。
4. `currentCmd = clamp(controlInput + distValue, +/- MotorParams.maxCurrentA)` を計算する。
5. `SafetyResetRevision` に変化があれば、3.4 の条件で保護ラッチの解除を評価する。
6. `enableCurrentOutput && !playbackDone` のときに `SafetyLimits` を評価し、違反があれば停止原因を保持する。
7. 電流ゲートが開いていれば `currentCmd` を `targetTorque [‰ rated]` に変換して `INT16` へ飽和させ、閉じていれば `targetTorque := 0` にする。
8. 両軸の ControlWord / StatusWord を個別 relay する。保護ラッチが有効なら、その周期から `currentCmd`、`targetTorque`、両軸の `ControlWordOut` を 0 にする。

### 5.3 保護停止の保持

| `safetyCode` | 意味 |
|---:|---|
| 0 | ラッチなし |
| 1 | Motor / Load の位置上限超過 |
| 2 | Motor / Load の速度上限超過 |
| 3 | ねじれ上限超過 |
| 4 | 保護設定が負値・非有限、または保護有効時の位置換算基準が無効 |

判定はコード 4、1、2、3 の順に行い、最初に検出した原因を保持する。ラッチ後は電流ゲートを閉じたり上限を変更したりしても解除されず、PLC からの enable 要求も両軸の ControlWord 出力で遮断する。

`enableRelativePosition=TRUE` の位置上限は reset 時の位置からの変位、ねじれ上限は両軸の相対変位の差を対象とする。reset 時に存在した初期ねじれは測らない。`enableRelativePosition=FALSE` の軸では `positionRel` に絶対位置が入る。

---

## 6. SIL 配線の注記

現行の checked-in `.tsproj` では、SIL 時に `VirtualMotorCore.Outputs.motor/*` を Motor、`VirtualMotorCore.Outputs.load/*` を Load として以下が配線される。

```text
VirtualMotorCore.Outputs.motor.positionActualValue -> motorRaw.positionActualValue
VirtualMotorCore.Outputs.motor.velocityActualValue -> motorRaw.velocityActualValue
VirtualMotorCore.Outputs.motor.torqueActualValue   -> motorRaw.torqueActualValue
VirtualMotorCore.Outputs.motor.statusWord          -> motorRaw.statusWord

VirtualMotorCore.Outputs.load.positionActualValue -> loadRaw.positionActualValue
VirtualMotorCore.Outputs.load.velocityActualValue -> loadRaw.velocityActualValue
VirtualMotorCore.Outputs.load.torqueActualValue   -> loadRaw.torqueActualValue
VirtualMotorCore.Outputs.load.statusWord          -> loadRaw.statusWord

targetTorque         -> VirtualMotorCore.Inputs.motor.targetTorque
motorControlWordOut  -> VirtualMotorCore.Inputs.motor.controlWord
loadControlWordOut   -> VirtualMotorCore.Inputs.load.controlWord
```

`targetTorque` は Motor 軸だけを駆動し、Load 軸には直接トルクを入れない。Load 側 ControlWord は CiA 状態追従と fault 監視のために独立 relay される。

`ExperimentHailMary.RealMotor.tsproj` は `<Io/>` が空の scaffold で、末端の 11 Link を `TIID^RealMotorPdo^RealMotorPdo Instance` に向けている。実機 PDO の取り込みと型・単位・符号の確認が必要であり、このファイルだけで実機配線が完了しているとは扱わない。

---

## 7. 設計メモ

DriverAdapter の主目的は **Driver 差異を上流制御へ漏らさないこと** である。したがって build-time 固定ではなく、Motor/Load ごとの差分を parameter struct と raw/engineering 変換に閉じ込める。

保護出力を追加した現行 TMC は、変更前の `.tmx` と組み合わせて使わない。Windows / TwinCAT SDK で DriverAdapter を再ビルドし、新しい TMC を XAE に反映してから構成を activate する。実機での準備と確認は [HigsExperiment](../operations/HigsExperiment.md) にまとめる。
