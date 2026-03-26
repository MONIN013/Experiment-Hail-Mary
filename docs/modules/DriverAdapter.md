# DriverAdapter

> **位置づけ:** Driver 境界の変換・中継・差異吸収を定義する C++ TcCOM モジュール仕様  
> **対象読者:** TcCOM 実装者、Drive I/O を変更する設計者  
> **更新条件:** I/O 契約、変換式、Driver 抽象化が変わったとき  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) §2B / [VirtualMotorCore](./VirtualMotorCore.md) / [OpenIssues](../status/OpenIssues.md)

---

## 1. 概要

DriverAdapter は **ドライバ差異吸収層** である。  
TwinCAT の C++ TcCOM として実装し、Drive 境界の raw 信号を工学単位へ変換し、上流制御へ統一 I/F を提供する。

本モジュールは **Motor + Load の 2 チャネル専用** とし、内部ではそれぞれの raw 入力を独立に扱う。
外部契約は current ベース `[A]` を維持し、Drive 境界でのみ `targetTorque` と `torqueActualValue` を `% rated` 整数型に変換する。  
`positionRel` は Load 側相対位置、`velocityAct` は Load 側速度、`currentAct` は Motor 側実電流の互換エイリアスとして維持する。

**設計方針:**

1. **Raw ↔ 工学単位の双方向変換** - Motor/Load の raw 信号を rad, rad/s, A に変換する
2. **実験開始時の相対位置化** - リセット時に Motor/Load の絶対位置をキャプチャし、以降は相対位置を公開する
3. **外乱加算** - `controlInput + distValue` を current `[A]` で合成し、Drive 境界で `targetTorque` に変換する
4. **CW/SW 中継** - `controlWordIn -> controlWordOut` と `statusWord -> statusWordOut` を relay する
5. **電流ゲート** - `enableCurrentOutput = FALSE` または `playbackDone = TRUE` のとき `targetTorque := 0`

**Driver 変更時の対応:**

`MotorParams` / `LoadParams` の ADS パラメータを書き換えて運用する。  
物理定数は build-time 固定ではなく、TcCOM パラメータとして注入する。

---

## 2. 機能一覧

| # | 機能 | 説明 |
|---|---|---|
| 1 | Motor raw → 工学単位変換 | position, velocity, torque/status を Motor 側で変換する |
| 2 | Load raw → 工学単位変換 | position, velocity を Load 側で変換する |
| 3 | 相対位置化 | `resetReq` 立ち上がりで Motor/Load の位置オフセットをキャプチャする |
| 4 | 外乱加算 | `controlInput + distValue` を current `[A]` で合成する |
| 5 | CW/SW relay | ModeManager と Drive の間で ControlWord / StatusWord を中継する |
| 6 | 電流ゲート | 実験停止時に `targetTorque := 0` を強制する |
| 7 | 互換エイリアス | `positionRel = load.positionRel`, `velocityAct = load.velocityAct`, `currentAct = motor.currentAct` を維持する |

---

## 3. パラメータ

### 3.1 `MotorParams`

Motor 側の変換パラメータは ADS から設定する。

| 定数名 | データ型 | 単位 | 説明 |
|---|---|---|---|
| `encoderResolution` | `UDINT` | pulses/rev | Motor 側エンコーダ分解能 |
| `ratedCurrentA` | `LREAL` | A | Motor 定格電流 |
| `maxCurrentA` | `LREAL` | A | Motor 電流クランプ上限 |
| `positionSign` | `DINT` | -1/+1 | 位置符号反転用 |
| `velocitySign` | `DINT` | -1/+1 | 速度符号反転用 |
| `currentSign` | `DINT` | -1/+1 | 電流符号反転用 |
| `enableRelativePosition` | `BOOL` | - | 相対位置化の有効化 |

### 3.2 `LoadParams`

Load 側も同じ形で ADS から設定する。

| 定数名 | データ型 | 単位 | 説明 |
|---|---|---|---|
| `encoderResolution` | `UDINT` | pulses/rev | Load 側エンコーダ分解能 |
| `ratedCurrentA` | `LREAL` | A | Load 側電流換算基準 |
| `maxCurrentA` | `LREAL` | A | Load 側クランプ上限 |
| `positionSign` | `DINT` | -1/+1 | 位置符号反転用 |
| `velocitySign` | `DINT` | -1/+1 | 速度符号反転用 |
| `currentSign` | `DINT` | -1/+1 | 電流符号反転用 |
| `enableRelativePosition` | `BOOL` | - | 相対位置化の有効化 |

> `ratedCurrentA <= 0` または `encoderResolution <= 0` の場合は、そのチャネルの該当変換を無効化して安全側に倒す。

---

## 4. I/O 仕様

### 4.1 入力 - Motor raw

| # | 変数名 | データ型 | 説明 |
|---|---|---|---|
| 1 | `motorRaw.positionActualValue` | `DINT` | Motor 実位置 [pulses] |
| 2 | `motorRaw.velocityActualValue` | `DINT` | Motor 実速度 [pulses/s] |
| 3 | `motorRaw.torqueActualValue` | `INT` | Motor 実トルク [‰ rated] |
| 4 | `motorRaw.statusWord` | `UINT` | Motor 状態語 |

### 4.2 入力 - Load raw

| # | 変数名 | データ型 | 説明 |
|---|---|---|---|
| 5 | `loadRaw.positionActualValue` | `DINT` | Load 実位置 [pulses] |
| 6 | `loadRaw.velocityActualValue` | `DINT` | Load 実速度 [pulses/s] |
| 7 | `loadRaw.torqueActualValue` | `INT` | Load 実トルク [‰ rated] |
| 8 | `loadRaw.statusWord` | `UINT` | Load 状態語 |

### 4.3 入力 - 制御側

| # | 変数名 | データ型 | 説明 |
|---|---|---|---|
| 9 | `controlInput` | `LREAL` | 制御出力 `[A]` |
| 10 | `distValue` | `LREAL` | 外乱値 `[A]` |
| 11 | `controlWordIn` | `UINT` | CiA 402 ControlWord |
| 12 | `enableCurrentOutput` | `BOOL` | 電流ゲート有効フラグ |
| 13 | `playbackDone` | `BOOL` | 再生完了通知 |
| 14 | `resetReq` | `BOOL` | リセット要求 |

### 4.4 出力 - 工学単位

| # | 変数名 | データ型 | 宛先 | 説明 |
|---|---|---|---|---|
| 1 | `motor.positionAbs` | `LREAL` | Logger / Debug | Motor 絶対位置 [rad] |
| 2 | `motor.positionRel` | `LREAL` | Debug | Motor 相対位置 [rad] |
| 3 | `motor.velocityAct` | `LREAL` | Logger / Debug | Motor 速度 [rad/s] |
| 4 | `motor.currentAct` | `LREAL` | Logger / Debug | Motor 実電流 [A] |
| 5 | `load.positionAbs` | `LREAL` | Debug | Load 絶対位置 [rad] |
| 6 | `load.positionRel` | `LREAL` | ControllerCore / Logger | Load 相対位置 [rad] |
| 7 | `load.velocityAct` | `LREAL` | Logger | Load 速度 [rad/s] |
| 8 | `load.currentAct` | `LREAL` | Debug | Load 実電流 [A] |
| 9 | `positionRel` | `LREAL` | ControllerCore / Logger | 互換エイリアス = `load.positionRel` |
| 10 | `velocityAct` | `LREAL` | Logger | 互換エイリアス = `load.velocityAct` |
| 11 | `currentAct` | `LREAL` | Logger | 互換エイリアス = `motor.currentAct` |
| 12 | `statusWordOut` | `UINT` | ModeManager | 互換エイリアス = `motorRaw.statusWord` |

### 4.5 出力 - Drive 側 raw

| # | 変数名 | データ型 | 宛先 | 説明 |
|---|---|---|---|---|
| 13 | `targetTorque` | `INT` | Drive | Motor 側指令 [% rated] |
| 14 | `controlWordOut` | `UINT` | Drive | ControlWord relay |

---

## 5. 変換ロジック

### 5.1 基本式

| 方向 | 変換 | 数式 |
|---|---|---|
| raw → rad | position | `theta = raw * 2pi / encoderResolution` |
| raw → rad/s | velocity | `omega = raw * 2pi / encoderResolution` |
| raw → A | current | `current = torquePermille * ratedCurrentA / 1000` |
| A → permille | targetTorque | `permille = round(currentCmd * 1000 / ratedCurrentA)` |

### 5.2 実行順

1. Motor raw と Load raw を工学単位へ変換する。
2. `resetReq` の立ち上がりで Motor/Load の位置オフセットをキャプチャする。
3. `enableRelativePosition` が有効なら相対位置を公開する。
4. `currentCmd = clamp(controlInput + distValue, +/- MotorParams.maxCurrentA)` を計算する。
5. `enableCurrentOutput = FALSE` または `playbackDone = TRUE` なら `targetTorque := 0` にする。
6. 有効時は `currentCmd` を `targetTorque` に変換し、`INT16` へ飽和させる。
7. `controlWordIn -> controlWordOut` と `motorRaw.statusWord -> statusWordOut` を relay する。

### 5.3 相対位置化

`resetReq` 立ち上がりで現在の絶対位置を保持し、以降は `positionAbs - offset` を `positionRel` として公開する。  
ControllerCore は Load 側の `positionRel` をそのまま受け取り、開始時点を 0 とした誤差計算を行う。

---

## 6. リセット仕様

| 項目 | 仕様 |
|---|---|
| 入力 | `resetReq` |
| 検出方式 | 立ち上がりエッジ |
| リセット内容 | Motor/Load の位置オフセットを再キャプチャ |
| 内部状態 | `prevResetReq`, `motorPositionOffsetRad`, `loadPositionOffsetRad` |

---

## 7. 接続例

### 7.1 SIL

```
VirtualMotorCore.Outputs.positionActualValue  -> loadRaw.positionActualValue
VirtualMotorCore.Outputs.velocityActualValue  -> loadRaw.velocityActualValue
VirtualMotorCore.Outputs.torqueActualValue    -> motorRaw.torqueActualValue
VirtualMotorCore.Outputs.statusWord           -> motorRaw.statusWord

DriverAdapter.targetTorque                    -> VirtualMotorCore.Inputs.targetTorque
DriverAdapter.controlWordOut                  -> VirtualMotorCore.Inputs.controlWord
```

### 7.2 Phase 4

```
EtherCAT motor PDO.positionActualValue        -> motorRaw.positionActualValue
EtherCAT motor PDO.velocityActualValue        -> motorRaw.velocityActualValue
EtherCAT motor PDO.torqueActualValue          -> motorRaw.torqueActualValue
EtherCAT motor PDO.statusWord                 -> motorRaw.statusWord

EtherCAT load encoder.positionActualValue     -> loadRaw.positionActualValue
EtherCAT load encoder.velocityActualValue     -> loadRaw.velocityActualValue
EtherCAT load PDO.torqueActualValue           -> loadRaw.torqueActualValue
EtherCAT load PDO.statusWord                  -> loadRaw.statusWord
```

---

## 8. 設計メモ

`DriverAdapter` は「Motor と Load の差分を吸収する層」であり、上流の制御構造にドライバ差を漏らさないことを主目的とする。  
そのため、TcCOM パラメータ化は「物理定数を build 時に埋め込む」ではなく、「実機差を ADS で切り替える」方向を採る。
