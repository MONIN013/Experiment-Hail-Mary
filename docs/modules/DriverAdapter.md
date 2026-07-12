# DriverAdapter

> **位置づけ:** Driver 境界の変換・中継・差異吸収を定義する active C++ TcCOM モジュール仕様  
> **対象読者:** TcCOM 実装者、Drive I/O を変更する設計者  
> **更新条件:** I/O 契約、変換式、Driver 抽象化が変わったとき  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) / [TechnicalReference](../architecture/TechnicalReference.md) / [VirtualMotorCore](./VirtualMotorCore.md)

---

## 1. 概要

DriverAdapter は **ドライバ差異吸収層** である。現行の active 実装は TwinCAT の **C++ TcCOM** (`DriverAdapter_Obj1 (Module1)`) であり、Drive 境界の raw 信号を工学単位へ変換し、上流制御へ統一 I/F を提供する。

`DriverAdapterAlgorithm` がraw変換、reset edgeとMotor/Load位置offset、current clamp/gate/量子化、ControlWord/StatusWord relayを固定メモリの純粋C++として所有する。TcCOM `Module1` はgenerated ADS型とのfield-by-field変換と8 kHz cyclic呼出しを担当する。

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
| `currentCmd` | `LREAL` | `clamp(controlInput + distValue)` 後の指令電流 [A] |
| `motorControlWordOut` | `UINT` | Motor ControlWord relay |
| `loadControlWordOut` | `UINT` | Load ControlWord relay |
| `motorStatusWordOut` | `UINT` | Motor StatusWord relay |
| `loadStatusWordOut` | `UINT` | Load StatusWord relay |

#### Drive 側 raw

| フィールド | 型 | 説明 |
|---|---|---|
| `targetTorque` | `INT` | Motor 側指令 [‰ rated] |

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
5. `enableCurrentOutput = FALSE` または `playbackDone = TRUE` のとき `targetTorque := 0` にする。
6. 有効時は `currentCmd` を `targetTorque [‰ rated]` に変換し、`INT16` へ飽和させる。
7. `motorControlWordIn/loadControlWordIn` をそれぞれ `motorControlWordOut/loadControlWordOut` へ relay し、`motorRaw.statusWord/loadRaw.statusWord` を `motorStatusWordOut/loadStatusWordOut` として公開する。

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

---

## 7. 設計メモ

DriverAdapter の主目的は **Driver 差異を上流制御へ漏らさないこと** である。したがって build-time 固定ではなく、Motor/Load ごとの差分を parameter struct と raw/engineering 変換に閉じ込める。
