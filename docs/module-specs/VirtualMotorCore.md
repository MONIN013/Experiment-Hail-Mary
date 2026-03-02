# VirtualMotorCore — モジュール仕様書

> **作成日:** 2026-02-27  
> **実装方式:** C++ TcCOM (既存モジュール改修)  
> **タスク:** VirtualMotorTask (1 ms) → ControlTask (125 µs)  
> **参照:** [ArchitectureSpec.md](../ArchitectureSpec.md) §3 / [DriverAdapter.md](DriverAdapter.md) / [OpenIssues.md](../OpenIssues.md)

---

## 1. 概要

VirtualMotorCore は SIL (Software-in-the-Loop) 検証用の仮想モーター物理シミュレータである。
Load 側 1 慣性近似として動作し、CiA 402 状態機械を内蔵する。

**設計方針 (D11/D13):**  
VirtualMotorCore の外部 I/O を CiA 402 EtherCAT PDO 準拠の **整数型** に変更する。
実機ドライバ (Panasonic A6B 等) と同一のインターフェースを提供することで、
DriverAdapter が VirtualMotor / EtherCAT Drive のどちらに接続されても同一の変換ロジックで動作可能にする。

内部シミュレーションは引き続き物理単位 (`double`: rad, Nm, rad/s) で計算し、
I/O 境界で整数変換を行う。

---

## 2. パラメータ (`ST_VirtualMotorParams`)

TcCOM Data Area として ADS シンボル公開。Build 不要で MATLAB から注入可能。

### 2.1 既存パラメータ

| パラメータ名 | データ型 | 単位 | 説明 |
|---|---|---|---|
| `mass` | `double` | kg·m² | 慣性モーメント (Load 側 1 慣性近似) |
| `damping` | `double` | N·m·s/rad | 粘性減衰係数 |
| `tauLimit` | `double` | N·m | トルク飽和リミット |
| `velLimit` | `double` | rad/s | 速度リミット |
| `taskDtNs` | `ULINT` | ns | タスク周期 (自動取得) |

### 2.2 新規パラメータ

| パラメータ名 | データ型 | 単位 | 例値 | 説明 |
|---|---|---|---|---|
| `encoderResolution` | `UDINT` | pulses/rev | `8388608` (2²³) | エンコーダ分解能。実機ドライバのエンコーダ仕様に合わせて設定 |
| `ratedTorque` | `double` | N·m | `1.2` | 定格トルク。CiA 402 の ‰ rated 変換基準。kt=1 前提で `RATED_CURRENT` と同一値 |
| `maxPermille` | `double` | ‰ rated | `0.0` | 入力指令トルクの上限 [‰ rated]。`0.0` = 無制限、正値で有効化。超過時 Fault 遷移 |

> **`encoderResolution` / `ratedTorque` / `maxPermille` の位置づけ:**  
> `encoderResolution` と `ratedTorque` は実験セットアップの物理定数であり、基本的に変化しない。  
> `maxPermille` はモーター保護のための入力レベル制限であり、MATLAB から実験ごとに注入可能。  
> ADS 注入可能な TcCOM パラメータ (`mass` / `damping` 等と同列) として提供する。
> DriverAdapter にも同一の値を `VAR_GLOBAL CONSTANT` として持たせる (→ [DriverAdapter.md](DriverAdapter.md) §3)。

### 2.3 `ratedTorque` への一本化 (M16 解消)

`targetTorque` [‰ rated] から内部 Nm への変換は `ratedTorque` のみを使用する。  
`torqueConstant` は 2026-02-27 の更新で I/F から削除済み。

---

## 3. I/O インターフェース — CiA 402 PDO 準拠

### 3.1 入力ポート (Data Area Input)

| # | ポート名 | データ型 | CiA 402 Index | ソース | 説明 |
|---|---|---|---|---|---|
| 1 | `targetTorque` | `INT` (16bit) | 0x6071 | DriverAdapter | 指令トルク [‰ rated] |
| 2 | `controlWord` | `UINT` (16bit) | 0x6040 | DriverAdapter | CiA 402 ControlWord |

### 3.2 出力ポート (Data Area Output)

| # | ポート名 | データ型 | CiA 402 Index | 宛先 | 説明 |
|---|---|---|---|---|---|
| 1 | `positionActualValue` | `DINT` (32bit) | 0x6064 | DriverAdapter | 実位置 [pulses] |
| 2 | `velocityActualValue` | `DINT` (32bit) | 0x606C | DriverAdapter | 実速度 [pulses/s] |
| 3 | `torqueActualValue` | `INT` (16bit) | 0x6077 | DriverAdapter | 実トルク [‰ rated] **(新規)** |
| 4 | `statusWord` | `UINT` (16bit) | 0x6041 | DriverAdapter | CiA 402 StatusWord |

### 3.3 旧 I/O との対応

| 旧ポート名 | 旧型 | 新ポート名 | 新型 | 変更内容 |
|---|---|---|---|---|
| `currentIn` | `double` [A] | `targetTorque` | `INT` [‰ rated] | 名称・型・単位すべて変更 |
| `positionOut` | `double` [rad] | `positionActualValue` | `DINT` [pulses] | 型・単位変更 |
| `velocityOut` | `double` [rad/s] | `velocityActualValue` | `DINT` [pulses/s] | 型・単位変更 |
| (なし) | — | `torqueActualValue` | `INT` [‰ rated] | 新規追加 |
| `statusWord` | `UINT` | `statusWord` | `UINT` | 変更なし |
| `controlWord` | `UINT` | `controlWord` | `UINT` | 変更なし |

---

## 4. 内部変換ロジック

内部シミュレーションは物理単位 (rad, Nm, rad/s) で計算する。I/O 境界で以下の変換を行う。

### 4.1 入力変換 (raw → 物理単位)

**maxPermille チェック (入力レベル保護):**

`maxPermille > 0` かつ $|\text{targetTorque}| > \text{maxPermille}$ の場合、`internalFault = true` → CiA 402 FAULT 状態に遷移する。
これは入力指令の物理的値ではなく、‰ rated 値でのチェックであり、DriverAdapter の故障・暴走対策として機能する。
`maxPermille = 0.0` (デフォルト) の場合、このチェックは無効化される。

**トルク変換:**

$$\tau_{cmd} = \frac{\text{targetTorque}}{1000} \times \text{ratedTorque} \quad [\text{Nm}]$$

### 4.2 物理シミュレーション (既存ロジック維持)

$$v_{n+1} = v_n + \frac{dt}{m}\left(\tau_{sat} - D \cdot v_n\right)$$
$$x_{n+1} = x_n + dt \cdot v_{n+1}$$

ここで $\tau_{sat} = \text{clamp}(\tau_{cmd},\, -\text{tauLimit},\, +\text{tauLimit})$。  
速度リミット超過・トルクリミット超過で内部 Fault → CiA 402 `FAULT` 状態遷移。

### 4.3 出力変換 (物理単位 → raw)

$$\text{positionActualValue} = \text{round}\!\left(\frac{\theta}{2\pi} \times \text{encoderResolution}\right) \quad [\text{pulses}]$$

$$\text{velocityActualValue} = \text{round}\!\left(\frac{\dot{\theta}}{2\pi} \times \text{encoderResolution}\right) \quad [\text{pulses/s}]$$

$$\text{torqueActualValue} = \text{round}\!\left(\frac{\tau_{sat}}{\text{ratedTorque}} \times 1000\right) \quad [\text{‰ rated}]$$

### 4.4 量子化誤差の見積もり

| パラメータ | 値 | 分解能 |
|---|---|---|
| エンコーダ (2²³ pulses/rev) | 8,388,608 | $\approx 7.5 \times 10^{-7}$ rad/pulse |
| トルク (‰ rated, ratedTorque=0.318 Nm) | 1000 分割 | $\approx 3.18 \times 10^{-4}$ Nm/digit |

エンコーダ分解能は制御帯域に対して十分な精度を持つ (Panasonic A6B 相当)。  
トルク分解能は ‰ 単位のため実用上問題ない。

---

## 5. CiA 402 状態機械 (既存仕様維持)

VirtualMotorCore は CiA 402 状態機械を内蔵する。
`controlWord` による状態遷移と `statusWord` の応答は既存実装を維持:

```
SWITCH_ON_DISABLED → READY_TO_SWITCH_ON → SWITCHED_ON → OPERATION_ENABLED
                                                                 ↕
                                                              FAULT
```

`OPERATION_ENABLED` 状態でのみ `targetTorque` 入力を受け付ける。
他の状態では内部トルクを 0 にクランプする。

---

## 6. リセット仕様

**設計決定:** VirtualMotorCore は `resetReq` 入力を **持たない**。

実機モータードライバにもソフトウェアリセット (位置/速度ゼロ復帰) 機能はないため、
VirtualMotorCore は実機同等の仕様として `position` / `velocity` を実験間で carry-over する。
実験開始時の相対位置化は **DriverAdapter** の `positionOffsetRad` で対応する (→ [DriverAdapter.md](DriverAdapter.md) §4.3)。

---

## 7. ADS シンボル

**インスタンス名:** `VirtualMotorCore_Obj1 (Module1)`, **Port:** 351

| シンボルパス | 型 | R/W |
|---|---|---|
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.mass` | `LREAL` | W |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.damping` | `LREAL` | W |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.tauLimit` | `LREAL` | W |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.velLimit` | `LREAL` | W |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.taskDtNs` | `ULINT` | W |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.encoderResolution` | `UDINT` | W |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.ratedTorque` | `LREAL` | W |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.maxPermille` | `LREAL` | W |
