# VirtualMotorCore

> **位置づけ:** SIL 用の仮想モーター物理シミュレーション仕様  
> **対象読者:** C++ TcCOM 実装者、SIL 検証担当者  
> **更新条件:** 物理モデル、I/O 契約、Drive エミュレーション前提が変わったとき  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) §3 / [DriverAdapter](./DriverAdapter.md)

---

## 1. 概要

VirtualMotorCore は SIL (Software-in-the-Loop) 検証用の仮想モーター物理シミュレータである。
現行実装は **Motor/Load を 1:1 ねじり結合した 2 慣性モデル** として動作し、Motor/Load それぞれに CiA 402 状態機械を持つ。

`VirtualMotorAlgorithm` が CiA 402 状態、2慣性plant、fault判定、raw量子化を固定メモリの純粋C++として所有する。TcCOM `Module1` はADS公開型と純粋型の変換、および8 kHz cyclic呼出しだけを担当する。scan順序は `drive state -> command fault -> plant integration -> output quantization` で固定し、host testで保護する。

**設計方針 (D11/D13):**  
VirtualMotorCore の外部 I/O を CiA 402 EtherCAT PDO 準拠の **整数型** に変更する。
実機ドライバ (Panasonic A6B 等) と同一のインターフェースを提供することで、
DriverAdapter が VirtualMotor / EtherCAT Drive のどちらに接続されても同一の変換ロジックで動作可能にする。

内部シミュレーションは引き続き物理単位 (`double`: rad, Nm, rad/s) で計算し、
I/O 境界で整数変換を行う。

---

## 2. パラメータ (`ST_VirtualPlantParams`)

TcCOM object parameter `PlantParameter` として ADS シンボル公開され、Build 不要で MATLAB から注入可能。
既定プリセットは `MADLT11BF + MHMF011L1A2` 相当とし、Motor/Load を同一ロータ相当の小慣性 2 慣性系として扱う。
`ratedTorque <= 0` の場合は `0.32 N·m` を安全な変換既定値として使う。

| 項目 | 既定値 |
|---|---|
| Motor/Load inertia | `7.1e-6 kg·m²` |
| Motor/Load ratedTorque | `0.32 N·m` |
| Motor/Load tauLimit | `1.11 N·m` |
| Motor/Load velLimit | `2*pi*6500/60 rad/s` |
| Motor/Load encoderResolution | `8,388,608 pulses/rev` |
| Motor maxPermille | `1000 ‰` |
| coupling stiffness / damping | `5.6059352998187553 N·m/rad` / `0.0004194811568097506 N·m·s/rad` |
| torsional natural frequency / damping ratio | `200 Hz` / `0.05` (`virtualMotor.torsional_mode`) |

### 2.1 `PlantParameter.motor`

| パラメータ名 | データ型 | 単位 | 説明 |
|---|---|---|---|
| `inertia` | `double` | kg·m² | Motor 慣性 |
| `damping` | `double` | N·m·s/rad | 粘性減衰係数 |
| `ratedTorque` | `double` | N·m | `‰ rated` 変換基準 |
| `tauLimit` | `double` | N·m | トルク飽和リミット |
| `velLimit` | `double` | rad/s | 速度リミット |
| `maxPermille` | `double` | ‰ rated | 入力指令トルク上限。`0.0` は無制限 |
| `encoderResolution` | `UDINT` | pulses/rev | エンコーダ分解能 |

### 2.2 `PlantParameter.load`

| パラメータ名 | データ型 | 単位 | 説明 |
|---|---|---|---|
| `inertia` | `double` | kg·m² | Load 慣性 |
| `damping` | `double` | N·m·s/rad | 粘性減衰係数 |
| `ratedTorque` | `double` | N·m | `‰ rated` 変換基準 |
| `tauLimit` | `double` | N·m | 許容伝達トルク上限 |
| `velLimit` | `double` | rad/s | 速度リミット |
| `encoderResolution` | `UDINT` | pulses/rev | エンコーダ分解能 |

### 2.3 `PlantParameter.coupling` / `taskDtNs`

| パラメータ名 | データ型 | 単位 | 説明 |
|---|---|---|---|
| `coupling.stiffness` | `double` | N·m/rad | ねじり剛性 |
| `coupling.damping` | `double` | N·m·s/rad | ねじり減衰 |
| `taskDtNs` | `ULINT` | ns | タスク周期 |

既定 coupling は Motor/Load の慣性・粘性を含む連続4状態モデルの複素固有値が、自然周波数 `200 Hz`、減衰比 `0.05` になるように決める。減衰付き共振周波数は約 `199.749 Hz` である。

---

## 3. I/O インターフェース — CiA 402 PDO 準拠

> **2 軸構成 (実装準拠):** `Module1Inputs/Outputs` は `motor` / `load` の構造体を持つ。
> Motor 側だけが `targetTorque` を受け取り、Load 側は `controlWord` と `statusWord` による drive state 管理のみを持つ。

### 3.1 入力ポート (Data Area Input)

| # | ポート名 | データ型 | CiA 402 Index | ソース | 説明 |
|---|---|---|---|---|---|
| 1 | `Inputs.motor.targetTorque` | `INT` (16bit) | 0x6071 | DriverAdapter | Motor 指令トルク [‰ rated] |
| 2 | `Inputs.motor.controlWord` | `UINT` (16bit) | 0x6040 | DriverAdapter | Motor CiA 402 ControlWord |
| 3 | `Inputs.load.controlWord` | `UINT` (16bit) | 0x6040 | DriverAdapter | Load CiA 402 ControlWord |

### 3.2 出力ポート (Data Area Output)

| # | ポート名 | データ型 | CiA 402 Index | 宛先 | 説明 |
|---|---|---|---|---|---|
| 1 | `Outputs.motor.positionActualValue` | `DINT` (32bit) | 0x6064 | DriverAdapter | Motor 実位置 [pulses] |
| 2 | `Outputs.motor.velocityActualValue` | `DINT` (32bit) | 0x606C | DriverAdapter | Motor 実速度 [pulses/s] |
| 3 | `Outputs.motor.torqueActualValue` | `INT` (16bit) | 0x6077 | DriverAdapter | Motor 実トルク [‰ rated] |
| 4 | `Outputs.motor.statusWord` | `UINT` (16bit) | 0x6041 | DriverAdapter | Motor StatusWord |
| 5 | `Outputs.load.positionActualValue` | `DINT` (32bit) | 0x6064 | DriverAdapter | Load 実位置 [pulses] |
| 6 | `Outputs.load.velocityActualValue` | `DINT` (32bit) | 0x606C | DriverAdapter | Load 実速度 [pulses/s] |
| 7 | `Outputs.load.torqueActualValue` | `INT` (16bit) | 0x6077 | DriverAdapter | 負荷軸へ伝達されたシャフトトルク [‰ rated] |
| 8 | `Outputs.load.statusWord` | `UINT` (16bit) | 0x6041 | DriverAdapter | Load StatusWord |

---

## 4. 内部変換ロジック

内部シミュレーションは物理単位 (rad, Nm, rad/s) で計算する。I/O 境界で以下の変換を行う。

### 4.1 入力変換 (raw → 物理単位)

**maxPermille チェック (入力レベル保護):**

`maxPermille > 0` かつ $|\text{targetTorque}| > \text{maxPermille}$ の場合、`internalFault = true` → CiA 402 FAULT 状態に遷移する。
これは入力指令の物理的値ではなく、‰ rated 値でのチェックであり、DriverAdapter の故障・暴走対策として機能する。
`maxPermille = 0.0` の場合、このチェックは無効化される。現行既定は `1000.0` で、定格トルク相当までに制限する。

**トルク変換:**

$$\tau_{cmd} = \frac{\text{targetTorque}}{1000} \times \text{ratedTorque} \quad [\text{Nm}]$$

### 4.2 物理シミュレーション

$$\tau_s = K_s(\theta_m - \theta_l) + D_s(\omega_m - \omega_l)$$
$$J_m \dot{\omega}_m = \tau_m - \tau_s - B_m \omega_m$$
$$J_l \dot{\omega}_l = \tau_s - B_l \omega_l$$

各 scan で Euler 積分により $\theta_m, \omega_m, \theta_l, \omega_l$ を更新する。
Motor 側 torque request 超過、Motor/Load 速度超過、Load 側シャフトトルク超過で各 drive は `FAULT` に遷移する。

### 4.3 出力変換 (物理単位 → raw)

$$\text{positionActualValue} = \text{round}\!\left(\frac{\theta}{2\pi} \times \text{encoderResolution}\right) \quad [\text{pulses}]$$

$$\text{velocityActualValue} = \text{round}\!\left(\frac{\dot{\theta}}{2\pi} \times \text{encoderResolution}\right) \quad [\text{pulses/s}]$$

$$\text{torqueActualValue} = \text{round}\!\left(\frac{\tau}{\text{ratedTorque}} \times 1000\right) \quad [\text{‰ rated}]$$

Motor 側は適用トルク $\tau_m$、Load 側は伝達シャフトトルク $\tau_s$ を使う。

### 4.4 量子化誤差の見積もり

| パラメータ | 値 | 分解能 |
|---|---|---|
| エンコーダ (2²³ pulses/rev) | 8,388,608 | $\approx 7.5 \times 10^{-7}$ rad/pulse |
| トルク (‰ rated, ratedTorque=0.32 Nm) | 1000 分割 | $3.2 \times 10^{-4}$ Nm/digit |

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
| `VirtualMotorCore_Obj1 (Module1).PlantParameter.motor.*` | `LREAL/UDINT` | W |
| `VirtualMotorCore_Obj1 (Module1).PlantParameter.load.*` | `LREAL/UDINT` | W |
| `VirtualMotorCore_Obj1 (Module1).PlantParameter.coupling.*` | `LREAL` | W |
| `VirtualMotorCore_Obj1 (Module1).PlantParameter.taskDtNs` | `ULINT` | W |
