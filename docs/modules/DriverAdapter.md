# DriverAdapter

> **位置づけ:** Driver 境界の変換・中継・差異吸収を定義するモジュール仕様  
> **対象読者:** PLC / TcCOM 実装者、Drive I/O を変更する設計者  
> **更新条件:** I/O 契約、変換式、Drive 境界責務が変わったとき  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) §2B / [VirtualMotorCore](./VirtualMotorCore.md) / [OpenIssues](../status/OpenIssues.md)

---

## 1. 概要

DriverAdapter は **ドライバ差異吸収層** である。
Drive (VirtualMotorCore / EtherCAT) の raw 信号 (パルス数、‰定格トルク) を
工学単位 (rad, rad/s, A) に変換し、制御モジュール群に統一インターフェースを提供する。
制御チェーンの外部契約は current ベース ([A]) とし、Drive 境界でのみ
`targetTorque` / `torqueActualValue` の `% rated` 整数型に変換する。
kt = 1 前提により、‰定格トルクと‰定格電流は同一スケールとして扱う。

**設計方針 (D11/D12):**

1. **Raw ↔ 工学単位の双方向変換** — Drive 出力 (CiA 402 整数型) → 工学単位 (ControllerCore / Logger 向け) と、制御出力 [A] → Drive 入力 (‰ rated)
2. **実験開始時の相対位置化** — リセット時に絶対位置をキャプチャし、以降は相対位置 (`positionRel`) を公開
3. **外乱加算 (Dist Adder)** — `controlInput + distValue` を current [A] で合成し、Drive 境界で `targetTorque` [% rated] に変換
4. **CW/SW 中継** — ModeManager ↔ Drive 間の ControlWord / StatusWord 中継
5. **電流ゲート** — `enableCurrentOutput = FALSE` または `playbackDone = TRUE` 時に電流出力をゼロクランプ

**Driver 変更時の対応:**  
DriverAdapter の `ENCODER_RESOLUTION` / `RATED_CURRENT` を書き換えて Build するのみ。
制御ロジック (ControllerCore) やテーブル (ExperimentSequencer) の変更は不要。

---

## 2. 機能一覧

| # | 機能 | Phase 1–3 | Phase 4 |
|---|---|---|---|
| 1 | Raw → 工学単位変換 (position, velocity, A) | ✓ (VirtualMotor) | ✓ (EtherCAT PDO) |
| 2 | 工学単位 → Raw 変換 (targetTorque) | ✓ | ✓ |
| 3 | 相対位置化 (positionOffsetRad キャプチャ) | ✓ | ✓ |
| 4 | 外乱加算 (controlInput + distValue) | ✓ | ✓ |
| 5 | CW/SW 中継 | ✓ | ✓ |
| 6 | 電流ゲート (安全停止) | ✓ | ✓ |

---

## 3. 定数パラメータ (`GVL_DRV` — `VAR_GLOBAL CONSTANT`)

ドライバ物理仕様に依存する定数。**Build 時に固定** され、ADS から変更不可。

| 定数名 | データ型 | 例値 | 単位 | 説明 |
|---|---|---|---|---|
| `ENCODER_RESOLUTION` | `UDINT` | `8388608` | pulses/rev | エンコーダ分解能 (Panasonic A6B: 2²³) |
| `RATED_CURRENT` | `LREAL` | `1.2` | A | モーター定格電流 |
| `MAX_CURRENT_A` | `LREAL` | `1.5` | A | 電流クランプ上限 (モーター保護) |
| `TWO_PI_INV_RES` | `LREAL` | (導出値) | rad/pulse | $\frac{2\pi}{\text{ENCODER\_RESOLUTION}}$ — パルス→rad 変換定数 |
| `RATED_CURRENT_INV_X1000` | `LREAL` | (導出値) | ‰/A | $\frac{1000}{\text{RATED\_CURRENT}}$ — A→‰rated 変換定数 |
| `RATED_CURRENT_DIV_1000` | `LREAL` | (導出値) | A/‰ | $\frac{\text{RATED\_CURRENT}}{1000}$ — ‰rated→A 変換定数 |

> **導出値の事前計算:**  
> ランタイムでの除算を回避し、乗算のみで変換を完結させるため、逆数定数を事前計算する。
> GVL 宣言時に `TWO_PI_INV_RES : LREAL := 6.283185307179586 / 8388608.0;` のようにリテラルで定義する。

> **Driver 変更手順:**  
> 1. `ENCODER_RESOLUTION` を新ドライバのエンコーダ仕様に変更  
> 2. `RATED_CURRENT` を新ドライバの定格電流に変更  
> 3. `MAX_CURRENT_A` を新ドライバの最大許容電流に変更  
> 4. 導出値 (`TWO_PI_INV_RES`, `RATED_CURRENT_INV_X1000`, `RATED_CURRENT_DIV_1000`) を再計算して更新  
> 5. Build → Activate Configuration

---

## 4. I/O 仕様

### 4.1 入力 — Drive 側 raw 信号 (`AT %I*`)

| # | 変数名 | データ型 | ソース | 説明 |
|---|---|---|---|---|
| 1 | `positionActualValue` | `DINT` | VirtualMotor / EtherCAT | 実位置 [pulses] |
| 2 | `velocityActualValue` | `DINT` | VirtualMotor / EtherCAT | 実速度 [pulses/s] |
| 3 | `torqueActualValue` | `INT` | VirtualMotor / EtherCAT | 実トルク [‰ rated] |
| 4 | `statusWord` | `UINT` | VirtualMotor / EtherCAT | CiA 402 StatusWord |

### 4.2 入力 — 制御側 (`AT %I*`)

| # | 変数名 | データ型 | ソース | 説明 |
|---|---|---|---|---|
| 5 | `controlInput` | `LREAL` | ControllerCore | 制御出力 $u_{fb} + u_{ff}$ [A] |
| 6 | `distValue` | `LREAL` | ExperimentSequencer | 外乱値 [A] |
| 7 | `controlWordIn` | `UINT` | ModeManager | CiA 402 ControlWord |
| 8 | `enableCurrentOutput` | `BOOL` | ModeManager | 電流ゲート有効フラグ |
| 9 | `playbackDone` | `BOOL` | ExperimentSequencer | 同一タスク fast-path 完了通知 |
| 10 | `resetReq` | `BOOL` | ModeManager | リセット要求 **(新規 — M15 解決)** |

### 4.3 出力 — 工学単位変換済み (`AT %Q*`)

| # | 変数名 | データ型 | 宛先 | 説明 |
|---|---|---|---|---|
| 1 | `positionRel` | `LREAL` | ControllerCore / ExperimentLogger | 相対位置 [rad] |
| 2 | `velocityAct` | `LREAL` | ExperimentLogger | 速度 [rad/s] |
| 3 | `currentAct` | `LREAL` | ExperimentLogger | 実電流 [A] |
| 4 | `statusWordOut` | `UINT` | ModeManager | CiA 402 StatusWord (中継) |

### 4.4 出力 — Drive 側 raw (`AT %Q*`)

| # | 変数名 | データ型 | 宛先 | 説明 |
|---|---|---|---|---|
| 5 | `targetTorque` | `INT` | VirtualMotor / EtherCAT | Drive 境界の指令 [% rated] |
| 6 | `controlWordOut` | `UINT` | VirtualMotor / EtherCAT | CiA 402 ControlWord (中継) |

### 4.5 旧 I/O との対応

| 旧変数名 | 旧型 | 状態 | 新変数名 | 備考 |
|---|---|---|---|---|
| `targetTorque` (LREAL) | `LREAL` [Nm] | **型変更** | `targetTorque` (INT) | ‰ rated 整数型に変更 |
| `controlInput` | `LREAL` | 維持 | `controlInput` | — |
| `distValue` | `LREAL` | 維持 | `distValue` | — |
| `statusWord` (入力) | `UINT` | 維持 | `statusWord` | — |
| `controlWordIn` | `UINT` | 維持 | `controlWordIn` | — |
| `controlWordOut` | `UINT` | 維持 | `controlWordOut` | — |
| `statusWordOut` | `UINT` | 維持 | `statusWordOut` | — |
| `enableTorqueOutput` | `BOOL` | **名称変更** | `enableCurrentOutput` | 電流ゲートに変更 |
| (なし) | — | **新規** | `positionActualValue` | Drive 生位置入力 |
| (なし) | — | **新規** | `velocityActualValue` | Drive 生速度入力 |
| (なし) | — | **新規** | `torqueActualValue` | Drive 生トルク入力 |
| (なし) | — | **新規** | `resetReq` | リセット要求 |
| (なし) | — | **新規** | `positionRel` | 相対位置出力 [rad] |
| (なし) | — | **新規** | `velocityAct` | 速度出力 [rad/s] |
| (なし) | — | **新規** | `currentAct` | 実電流出力 [A] |

---

## 5. 変換ロジック

### 5.1 PRG_DriverAdapter 疑似コード

```iecst
PROGRAM PRG_DriverAdapter
VAR
    positionRad       : LREAL := 0.0;
    targetCurrentA    : LREAL := 0.0;
    permilleCmd       : LREAL := 0.0;
    targetTorqueDint  : DINT := 0;
    positionOffsetRad : LREAL := 0.0;  (* リセット時キャプチャ位置 *)
    resetReqPrev      : BOOL  := FALSE; (* エッジ検出用 *)
    resetEdge         : BOOL  := FALSE;
END_VAR
```

```iecst
(* ═══════════════════════════════════════════════════════════════ *)
(*  1. Drive → 工学単位変換                                       *)
(* ══════════════════════
positionRad          := DINT_TO_LREAL(GVL_DRV.positionActualValue) * TWO_PI_INV_RES;
GVL_DRV.velocityAct  := DINT_TO_LREAL(GVL_DRV.velocityActualValue) * TWO_PI_INV_RES;
GVL_DRV.currentAct   := INT_TO_LREAL(GVL_DRV.torqueActualValue) * RATED_CURRENT_DIV_1000;

(* ═══════════════════════════════════════════════════════════════ *)
(*  2. リセット — 相対位置オフセットキャプチャ (エッジ検出)       *)
(* ═══════════════════════════════════════════════════════════════ *)
resetEdge := GVL_DRV.resetReq AND NOT resetReqPrev;
IF resetEdge THEN
    positionOffsetRad := positionRad;
END_IF
resetReqPrev := GVL_DRV.resetReq;

(* ═══════════════════════════════════════════════════════════════ *)
(*  3. 相対位置化                                                 *)
(* ═══════════════════════════════════════════════════════════════ *)
GVL_DRV.positionRel := positionRad - positionOffsetRad;

(* ═══════════════════════════════════════════════════════════════ *)
(*  4. 工学単位 → Drive 変換 (電流クランプ + 外乱加算 + 電流ゲート)           *)
(* ═══════════════════════════════════════════════════════════════ *)
targetCurrentA := GVL_DRV.controlInput + GVL_DRV.distValue;

(* Motor protection: clamp current before permille conversion *)
IF targetCurrentA > MAX_CURRENT_A THEN
    targetCurrentA := MAX_CURRENT_A;
ELSIF targetCurrentA < -MAX_CURRENT_A THEN
    targetCurrentA := -MAX_CURRENT_A;
END_IF

IF GVL_DRV.enableCurrentOutput AND NOT GVL_DRV.playbackDone THEN
    (* Symmetric rounding (+/-0.5) then INT16 saturation via DINT path *)
    permilleCmd := targetCurrentA * RATED_CURRENT_INV_X1000;
    IF permilleCmd >= 0.0 THEN
        targetTorqueDint := LREAL_TO_DINT(permilleCmd + 0.5);
    ELSE
        targetTorqueDint := LREAL_TO_DINT(permilleCmd - 0.5);
    END_IF

    IF targetTorqueDint > 32767 THEN
        targetTorqueDint := 32767;
    ELSIF targetTorqueDint < -32768 THEN
        targetTorqueDint := -32768;
    END_IF

    GVL_DRV.targetTorque := DINT_TO_INT(targetTorqueDint);
ELSE
    GVL_DRV.targetTorque := 0;
END_IF

(* ═══════════════════════════════════════════════════════════════ *)
(*  5. CW/SW 中継                                                 *)
(* ═══════════════════════════════════════════════════════════════ *)
GVL_DRV.controlWordOut := GVL_DRV.controlWordIn;
GVL_DRV.statusWordOut  := GVL_DRV.statusWord;
```

### 5.2 変換数式サマリ

| 方向 | 変換 | 数式 |
|---|---|---|
| Drive → Adapter | Position [pulses] → [rad] | $\theta_{rad} = \text{positionActualValue} \times \frac{2\pi}{\text{ENCODER\_RESOLUTION}}$ |
| Drive → Adapter | Velocity [pulses/s] → [rad/s] | $\dot{\theta}_{rad/s} = \text{velocityActualValue} \times \frac{2\pi}{\text{ENCODER\_RESOLUTION}}$ |
| Drive → Adapter | Current [‰ rated] → [A] | $\text{currentAct} = \text{currentActualValue} \times \frac{\text{RATED\_CURRENT}}{1000}$ |
| Adapter → Drive | Current clamp [A] | $\text{targetCurrentA} = \text{clamp}(\text{controlInput} + \text{distValue},\; \pm\text{MAX\_CURRENT\_A})$ |
| Adapter → Drive | Current [A] → [‰ rated] | $\text{targetTorque} = \text{round}(\text{targetCurrentA} \times \frac{1000}{\text{RATED\_CURRENT}})$ |

### 5.3 相対位置化

リセット時 (`resetReq` 立ち上がりエッジ) に現在の絶対位置 `positionRad` をキャプチャし、
以降は差分を `positionRel` として公開する。

$$\text{positionRel} = \theta_{rad} - \theta_{offset}$$

これにより ControllerCore は「実験開始時点 = 0」の相対位置で誤差計算を行う。

> **移行元:** この相対位置化は従来 ControllerCore (C++ TcCOM) 内の  
> `positionOffset` / `positionRel` で実装されていた (M5 で実装)。  
> D12 により DriverAdapter に移管し、ControllerCore は  
> `positionAct` をそのまま相対位置として使用する (→ [SystemArchitecture](../architecture/SystemArchitecture.md) §2)。
>
> **命名例外:** `targetTorque` / `torqueActualValue` は CiA 402 の Drive 境界に合わせて残す。
> DriverAdapter より上流の制御・ロギング契約は current [A] が正規契約である。

---

## 6. リセット仕様

| 項目 | 仕様 |
|---|---|
| 入力 | `GVL_DRV.resetReq AT %I*` ← ModeManager.resetOut |
| 検出方式 | **エッジ検出** (`resetReq AND NOT resetReqPrev`) — ControllerCore / ExperimentLogger と統一 |
| リセット内容 | `positionOffsetRad := positionRad` (現在位置キャプチャ) |
| 内部状態 | `positionOffsetRad`, `resetReqPrev` |

> **M15 解決:** 旧 DriverAdapter は組み合わせ回路で内部状態を持たなかったため `resetReq` が不要だった。  
> 相対位置化の移管に伴い内部状態 (`positionOffsetRad`) が導入されるため、`resetReq` が必須となる。

---

## 7. I/O リンク接続 (Phase 1–3)

```
  VirtualMotorCore.positionActualValue  ──►  GVL_DRV.positionActualValue
  VirtualMotorCore.velocityActualValue  ──►  GVL_DRV.velocityActualValue
  VirtualMotorCore.torqueActualValue    ──►  GVL_DRV.torqueActualValue
  VirtualMotorCore.statusWord           ──►  GVL_DRV.statusWord

  GVL_DRV.targetTorque                  ──►  VirtualMotorCore.targetTorque
  GVL_DRV.controlWordOut                ──►  VirtualMotorCore.controlWord

  ControllerCore.controlInput           ──►  GVL_DRV.controlInput
  ExperimentSequencer.distValue         ──►  GVL_DRV.distValue
  ExperimentSequencer.playbackDone      ──►  GVL_DRV.playbackDone
  ModeManager.controlWord               ──►  GVL_DRV.controlWordIn
  ModeManager.enableCurrentOutput     ──►  GVL_DRV.enableCurrentOutput
  ModeManager.resetOut                   ──►  GVL_DRV.resetReq

  GVL_DRV.positionRel                   ──►  ControllerCore.positionAct
  GVL_DRV.positionRel                   ──►  ExperimentLogger.Inputs.loadPosition
  GVL_DRV.velocityAct                   ──►  ExperimentLogger.Inputs.loadVelocity
  GVL_DRV.currentAct                    ──►  ExperimentLogger.Inputs.motorCurrentAct
  GVL_DRV.statusWordOut                 ──►  ModeManager.statusWord
```

### 7.1 Phase 4 での変更点

Phase 4 では VirtualMotorCore の接続を EtherCAT PDO に差し替える:

```
  EtherCAT.PDO.positionActualValue      ──►  GVL_DRV.positionActualValue
  EtherCAT.PDO.velocityActualValue      ──►  GVL_DRV.velocityActualValue
  EtherCAT.PDO.torqueActualValue        ──►  GVL_DRV.torqueActualValue
  EtherCAT.PDO.statusWord               ──►  GVL_DRV.statusWord

  GVL_DRV.targetTorque                  ──►  EtherCAT.PDO.targetTorque
  GVL_DRV.controlWordOut                ──►  EtherCAT.PDO.controlWord
```

DriverAdapter 内部ロジックの変更は不要。tsproj の `<Mappings>` 変更のみ。
`ENCODER_RESOLUTION` / `RATED_CURRENT` を実機ドライバの仕様に合わせて書き換え → Build。

---

## 8. 信号フロー図

```
                        DriverAdapter (PLC ST)
                        ドライバ差異吸収層
  ┌────────────────────────────────────────────────────────────────────┐
  │                                                                    │
  │  [Drive → 工学単位]                                                │
  │  positionActualValue (DINT) ─── ×TWO_PI_INV_RES ─── positionRad  │
  │  velocityActualValue (DINT) ─── ×TWO_PI_INV_RES ─── velocityAct  │
  │  torqueActualValue (INT) ────── ×RATED_CURRENT_DIV_1000 ── currentAct│
  │                                                                    │
  │  [相対位置化]                                                      │
  │  positionRad ─── (−positionOffsetRad) ─── positionRel ──► CC/Logger│
  │                   ▲                                                │
  │                   └── resetReq edge → capture positionRad          │
  │                                                                    │
  │  [工学単位 → Drive]                                                │
  │  controlInput (LREAL [A]) ──────────────────► (+) ──► clamp(±MAX │
  │  distValue (LREAL [A]) ────────────────────► (+)     _CURRENT_A)│
  │                                                        ──► ×RATED_CURRENT│
  │                                                             _INV_X1000  │
  │                                                        ──► target │
  │                                                          Torque   │
  │                                               (INT, ‰ rated)     │
  │  [enableCurrentOutput=FALSE or playbackDone=TRUE                    │
  │    → targetTorque := 0]                                             │
  │                                                                    │
  │  [CW/SW 中継]                                                      │
  │  controlWordIn ──────────────────────── controlWordOut ──► Drive   │
  │  statusWord (from Drive) ──────────── statusWordOut ──► ModeManager│
  │                                                                    │
  └────────────────────────────────────────────────────────────────────┘
```
