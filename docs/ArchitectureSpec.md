# アーキテクチャ設計仕様 — 次世代実験基盤

> **位置づけ:** [ProjectArchitecture.md](ProjectArchitecture.md) の設計思想を具体化したモジュール仕様書。  
> **参照:** ブロック図 → [NewProjectBlock.pu](NewProjectBlock.pu)  
> **現行仕様:** [CurrentProject.md](CurrentProject.md)

---

## 0. 実装方針メモ (2026-02-24)

* Phase 1 (1 ms SIL) 実装では PLC シンボル名を **`GVL_SEQ` / `GVL_SEQ_LOG`** に統一する（`GVL_EXP*` 互換は維持しない）。
* `TmpLogger` の機能は `ExperimentSequencer` に置換し、Phase 1 統合完了後に撤去する。
* Phase 3 の `ExperimentLogger` (C++ TcCOM) 導入まで、SIL 検証用の暫定リングバッファ logger を PLC (`GVL_SEQ_LOG`) に保持する。

---

## 1. モジュール一覧

| # | モジュール名 | 実装方式 | タスク (Phase 1–3 → Phase 4) | 役割 |
|---|---|---|---|---|
| 1 | **ControllerCore** | C++ TcCOM (新規) | VirtualMotorTask 1 ms → ControlTask 125 µs | 誤差計算 + FB 制御チェーン + FF 付加 (スカラ I/O、テーブル非所有) |
| 2 | **ExperimentSequencer** | PLC ST (新規) | VirtualMotorTask 1 ms → ControlTask 125 µs | テーブルリプレイ（ref / ff / dist スカラ出力のみ） |
| 3 | **VirtualMotorCore** | C++ TcCOM (既存) | VirtualMotorTask 1 ms → ControlTask 125 µs | 仮想モーター物理シミュレーション (SIL 用、1慣性近似) |
| 4 | **DriverAdapter** | PLC ST (Phase 1〜) | VirtualMotorTask 1 ms → ControlTask 125 µs | ControlInput + Dist → TargetTorque 合成 + ControlWord / StatusWord 中継 + EtherCAT PDO I/O (Phase 4) |
| 5 | **ExperimentLogger** | C++ TcCOM (Phase 3 新規) | VirtualMotorTask 1 ms → ControlTask 125 µs | ファイルロギング専用 (8kHz×100s 対応) |
| 6 | **ModeManager** | PLC ST (StateMachineControl 拡張) | PlcTask1 10 ms | CiA 402 + 実験シーケンス管理 + 安全監視 |

### 1.1 Phase 別モジュール構成

```
Phase 1-3 (1 ms):
  ExperimentSequencer ─── ControllerCore ─── DriverAdapter ─── VirtualMotorCore
         │                                       │
         └─── mode_flags ◄── ModeManager ◄───────┘ (CW/SW 中継)
                                   │
                         ExperimentLogger (Phase 3〜)

Phase 4 (125 µs = 8 kHz):
  ExperimentSequencer ─── ControllerCore ─── DriverAdapter ─── EtherCAT Drive
         │                                       │
         └─── mode_flags ◄── ModeManager ◄───────┘ (CW/SW 中継)
         │                                                        
         └──── ExperimentLogger ──────────────────────────────────
         (VirtualMotorCore は SIL テスト用に維持)
```

> **設計意図:** ControllerCore (C++ TcCOM) はテーブルを所有しない。
> 制御構造を C++ で直接実装し、ADS で Tunable Parameter を注入する。
> 誤差計算・FB Chain・FF 付加を ControllerCore 内に配置する。
> テーブルリプレイは PLC ST (ExperimentSequencer) で実装する。
> ExperimentSequencer は ref / ff / dist のスカラ出力のみを担当する。
> 外乱加算 (Dist Adder: target_torque = control_input + dist) および
> ControlWord / StatusWord の中継は DriverAdapter (PLC ST) が担当する。
>
> **2慣性系構成:** 本実験は Motor + Load の 2 慣性系である。
> トルク指令 (`target_torque`) は Motor 側に入力し、
> 位置フィードバック (`position_act`) は Load 側エンコーダから取得する。
> VirtualMotorCore (SIL) は Load 側応答の 1 慣性近似として動作する。
> Phase 4 (DriverAdapter + EtherCAT) で実機の Motor/Load 両方の信号を取得する。

---

## 2. ControllerCore — C++ TcCOM I/O 仕様

> **設計方針:** ControllerCore は誤差計算・FB Chain・FF 付加を担当する。
> C++ で PID / Lead / Notch / Reso の離散フィルタを直接実装する。
> テーブル (大規模配列) は所有せず、スカラ入力のみとする。

### 2.1 入力ポート (TcCOM Data Area Input)

| # | ポート名 | データ型 | ソース | 説明 |
|---|---|---|---|---|
| 1 | `ref_value` | `double` | ExperimentSequencer | 位置指令値 (スカラ) [rad] |
| 2 | `ff_value` | `double` | ExperimentSequencer | FF 信号 (スカラ) [Nm] |
| 3 | `position_act` | `double` | DriverAdapter / VirtualMotorCore | **Load 側**実位置 [rad] |

### 2.2 出力ポート (TcCOM Data Area Output)

| # | ポート名 | データ型 | 宛先 | 説明 |
|---|---|---|---|---|
| 1 | `control_input` | `double` | DriverAdapter | 制御出力 $u_{fb} + u_{ff}$ [Nm] |

### 2.3 内部処理

1. **Error Calc:** $e = \text{ref\_value} - \text{position\_act}$ 　(`position_act` = Load 側実位置)
2. **FB Chain:** $e \to \text{PID} \to \text{Lead} \to \text{Notch} \to \text{Reso} \to u_{fb}$
3. **FF Adder:** $\text{control\_input} = u_{fb} + \text{ff\_value}$

### 2.3 Tunable Parameters (ADS 注入、Build 不要)

> TMC (TwinCAT Module Class) 定義により Data Area として公開し、ADS シンボルとしてアクセス可能にする。
> VirtualMotorCore と同様の方式。

> **注記:** テーブル (`ref_table`, `ff_table`, `dist_table`, `table_len`) は ControllerCore に含めない。
> ExperimentSequencer (PLC ST) 側の GVL に配置。→ §2A 参照。

#### 2.3.1 PID パラメータ

| パラメータ名 | データ型 | 説明 |
|---|---|---|
| `pid_Kp` | `double` | 比例ゲイン |
| `pid_Ki` | `double` | 積分ゲイン |
| `pid_Kd` | `double` | 微分ゲイン |
| `pid_N` | `double` | 微分フィルタ係数 (1次ローパス) |

#### 2.3.2 Lead Compensator パラメータ

| パラメータ名 | データ型 | サイズ | 説明 |
|---|---|---|---|
| `lead_num` | `double[]` | `[1 × 3]` | 離散伝達関数 分子係数 $[b_0, b_1, b_2]$ |
| `lead_den` | `double[]` | `[1 × 3]` | 離散伝達関数 分母係数 $[1, a_1, a_2]$ |

#### 2.3.3 Notch Filter パラメータ

| パラメータ名 | データ型 | 説明 |
|---|---|---|
| `notch_b0` | `double` | Biquad 分子係数 $b_0$ |
| `notch_b1` | `double` | Biquad 分子係数 $b_1$ |
| `notch_b2` | `double` | Biquad 分子係数 $b_2$ |
| `notch_a1` | `double` | Biquad 分母係数 $a_1$ |
| `notch_a2` | `double` | Biquad 分母係数 $a_2$ |

#### 2.3.4 位相最適共振フィルタ パラメータ

| パラメータ名 | データ型 | 説明 |
|---|---|---|
| `reso_b0` | `double` | Biquad 分子係数 $b_0$ |
| `reso_b1` | `double` | Biquad 分子係数 $b_1$ |
| `reso_b2` | `double` | Biquad 分子係数 $b_2$ |
| `reso_a1` | `double` | Biquad 分母係数 $a_1$ |
| `reso_a2` | `double` | Biquad 分母係数 $a_2$ |

#### 2.3.5 Enable / Bypass フラグ

| パラメータ名 | データ型 | デフォルト | 説明 |
|---|---|---|---|
| `enable_pid` | `boolean` | `true` | PID ブロックの有効/バイパス |
| `enable_lead` | `boolean` | `false` | Lead Compensator の有効/バイパス |
| `enable_notch` | `boolean` | `false` | Notch Filter の有効/バイパス |
| `enable_reso` | `boolean` | `false` | 位相最適共振フィルタの有効/バイパス |

> **bypass 動作:** `enable = false` のとき、そのブロックの出力は入力をそのまま通過 (ゲイン 1)。  
> FB チェーン: `error → [PID] → [Lead] → [Notch] → [Reso] → u_fb → (+ff_value) → control_input`  
> 各ブロックは `enable ? block_output : input` の条件分岐で選択する。

---

## 2A. ExperimentSequencer — PLC ST 仕様

> **役割:** テーブルリプレイ（ref / ff / dist のスカラ読み出し）のみを PLC ST で実装する。
> ControllerCore (C++ TcCOM) からテーブルを分離し、責務を明確化する。
> 誤差計算・FF 付加は ControllerCore (C++ TcCOM) 側で実装する。
> 外乱加算 (Dist Adder) は DriverAdapter に移管する。
> **ExperimentSequencer は ref / ff / dist のスカラ出力のみを担当する。**

### 2A.1 機能

1. **Ref Table Replay** — `ref_table[idx]` から位置指令値 `ref_value` (スカラ) を読み出し→ ControllerCore へ
2. **FF Table Replay** — `ff_table[idx]` から FF 値 `ff_value` (スカラ) を読み出し→ ControllerCore へ
3. **Dist Table Replay** — `dist_table[idx]` から外乱値 `dist_value` (スカラ) を読み出し→ DriverAdapter へ
4. **テーブルインデックス管理** — `experiment_active` が `TRUE` の間 `idx` をインクリメント。`idx >= table_len` で再生完了。

### 2A.2 GVL — テーブル変数

| 変数名 | データ型 | サイズ | 説明 |
|---|---|---|---|
| `ref_table` | `LREAL[]` | `[0..N_REF_MAX-1]` | 位置指令テーブル [rad] |
| `ff_table` | `LREAL[]` | `[0..N_FF_MAX-1]` | フィードフォワードテーブル [Nm] |
| `dist_table` | `LREAL[]` | `[0..N_DIST_MAX-1]` | 外乱テーブル [Nm] |
| `table_len` | `UDINT` | scalar | テーブル有効長 (共通) |

> `N_REF_MAX`, `N_FF_MAX`, `N_DIST_MAX` は PLC 定数として定義 (初期値: 100,000)。  
> `table_len ≤ N_*_MAX` で実効長を制御する。

### 2A.3 入出力

#### 入力

| # | 変数名 | データ型 | ソース | 説明 |
|---|---|---|---|---|
| 1 | `mode_flags` | `UINT` | ModeManager | 動作モードフラグ |
| 2 | `experiment_active` | `BOOL` | ModeManager | 実験実行中フラグ |

#### 出力

| # | 変数名 | データ型 | 宛先 | 説明 |
|---|---|---|---|---|
| 1 | `ref_value` | `LREAL` | ControllerCore | 位置指令値 (スカラ) `ref_table[idx]` [rad] |
| 2 | `ff_value` | `LREAL` | ControllerCore | FF 信号 (スカラ) `ff_table[idx]` [Nm] |
| 3 | `dist_value` | `LREAL` | DriverAdapter | 外乱値 (スカラ) `dist_table[idx]` [Nm] |

---

## 2B. DriverAdapter — PLC ST 仕様

> **役割:** ControllerCore の制御出力 (`control_input`) を Drive 入力形式に整形するアダプタ層。
> 外乱加算 (Dist Adder) と ControlWord / StatusWord の中継を担当する。
> Phase 1–3 では VirtualMotorCore に接続し、Phase 4 で EtherCAT PDO I/O に切り替える。
> **ExperimentSequencer からテーブルリプレイ処理を受け取らず、スカラ入力のみを扱う。**

### 2B.1 機能

1. **Dist Adder** — $\text{target\_torque} = \text{control\_input} + \text{dist\_value}$ (最終トルク出力 → Motor 側)
2. **ControlWord 中継** — ModeManager が生成した `controlword` を Drive (VirtualMotorCore / EtherCAT) へ転送
3. **StatusWord 中継** — Drive から受信した `statusword` を ModeManager へ転送
4. **Phase 4 拡張:** EtherCAT PDO マッピング、2慣性系 (Motor + Load) の信号取得

### 2B.2 入出力

#### 入力

| # | 変数名 | データ型 | ソース | 説明 |
|---|---|---|---|---|
| 1 | `control_input` | `LREAL` | ControllerCore | 制御出力 $u_{fb} + u_{ff}$ [Nm] |
| 2 | `dist_value` | `LREAL` | ExperimentSequencer | 外乱値 (スカラ) [Nm] |
| 3 | `statusword` | `UINT` | Drive (VirtualMotorCore / EtherCAT) | CiA 402 StatusWord |
| 4 | `controlword_in` | `UINT` | ModeManager | CiA 402 ControlWord (ModeManager 生成) |

#### 出力

| # | 変数名 | データ型 | 宛先 | 説明 |
|---|---|---|---|---|
| 1 | `target_torque` | `LREAL` | Drive (VirtualMotorCore / EtherCAT) | 最終トルク $\text{control\_input} + \text{dist\_value}$ [Nm] → Motor 側 |
| 2 | `controlword_out` | `UINT` | Drive (VirtualMotorCore / EtherCAT) | CiA 402 ControlWord (中継) |
| 3 | `statusword_out` | `UINT` | ModeManager | CiA 402 StatusWord (中継) |

> **Phase 4 追加出力 (EtherCAT PDO):**
> `load_position`, `load_velocity` (Load 側エンコーダ)
> `motor_position`, `motor_velocity`, `motor_torque_act` (Motor 側)
>
> Phase 1–3 では VirtualMotorCore の I/O 構造体と直接リンクする。
> Phase 4 では EtherCAT Slave の PDO マッピングに切り替え、
> tsproj の `<Mappings>` 変更のみで仮想/実機を選択可能にする。

---

## 3. Data Area — I/O リンク接続マップ

### 3.1 ExperimentSequencer → ControllerCore

```
ExperimentSequencer.ref_value      ──►  ControllerCore.ref_value
ExperimentSequencer.ff_value       ──►  ControllerCore.ff_value
```

### 3.2 ControllerCore → DriverAdapter

```
ControllerCore.control_input       ──►  DriverAdapter.control_input
```

### 3.3 ExperimentSequencer → DriverAdapter

```
ExperimentSequencer.dist_value     ──►  DriverAdapter.dist_value
```

### 3.4 DriverAdapter ↔ VirtualMotorCore (Phase 1–3)

```
DriverAdapter.target_torque         ──►  VirtualMotorCore.Inputs.VirtualMotorInputs.current_in   (Motor 側入力)
DriverAdapter.controlword_out       ──►  VirtualMotorCore.Inputs.controlword
VirtualMotorCore.Outputs.statusword ──►  DriverAdapter.statusword
VirtualMotorCore.Outputs.VirtualMotorOutputs.position_out  ──►  ControllerCore.position_act   (Load 側 FB)
```

> VirtualMotorCore は 1 慣性近似。`position_out` は Load 側応答の近似値として扱う。

### 3.5 ModeManager ↔ DriverAdapter

```
ModeManager.controlword            ──►  DriverAdapter.controlword_in
DriverAdapter.statusword_out       ──►  ModeManager.statusword
```

> ModeManager が CiA 402 ControlWord を生成し、DriverAdapter が Drive へ中継する。
> Drive (VirtualMotorCore / EtherCAT) の StatusWord は DriverAdapter 経由で ModeManager に返る。

### 3.6 ModeManager → ExperimentSequencer

```
ModeManager.mode_flags        ──►  ExperimentSequencer.mode_flags
ModeManager.experiment_active ──►  ExperimentSequencer.experiment_active
```

### 3.7 各モジュール → ExperimentLogger (Phase 3〜)

```
DriverAdapter.target_torque                                ──►  ExperimentLogger.Inputs.torque_cmd
ExperimentSequencer.ref_value                              ──►  ExperimentLogger.Inputs.ref_value
ExperimentSequencer.ff_value                               ──►  ExperimentLogger.Inputs.ff_value
ControllerCore.control_input                               ──►  ExperimentLogger.Inputs.control_input
ControllerCore.error                                       ──►  ExperimentLogger.Inputs.error

(Phase 1–3: VirtualMotorCore — 1慣性近似)
VirtualMotorCore.Outputs.VirtualMotorOutputs.position_out  ──►  ExperimentLogger.Inputs.load_position    (Load 近似)
VirtualMotorCore.Outputs.VirtualMotorOutputs.velocity_out  ──►  ExperimentLogger.Inputs.load_velocity    (Load 近似)

(Phase 4: DriverAdapter — 2慣性系実機)
DriverAdapter.Outputs.motor_position                       ──►  ExperimentLogger.Inputs.motor_position
DriverAdapter.Outputs.motor_velocity                       ──►  ExperimentLogger.Inputs.motor_velocity
DriverAdapter.Outputs.motor_torque_act                     ──►  ExperimentLogger.Inputs.motor_torque_act
DriverAdapter.Outputs.load_position                        ──►  ExperimentLogger.Inputs.load_position
DriverAdapter.Outputs.load_velocity                        ──►  ExperimentLogger.Inputs.load_velocity
```

> `error` は ControllerCore の Data Area Output として公開する。
> Phase 1–3 では motor_position / motor_velocity / motor_torque_act は取得不可 (ゼロ埋め)。

### 3.8 DriverAdapter ↔ EtherCAT Drive (Phase 4)

```
DriverAdapter.target_torque         ──►  EtherCAT.PDO.target_torque   (Motor 側入力)
DriverAdapter.controlword_out       ──►  EtherCAT.PDO.controlword
EtherCAT.PDO.statusword             ──►  DriverAdapter.statusword
EtherCAT.PDO.load_position          ──►  ControllerCore.position_act   (Load 側 FB)
```

> Phase 4 では DriverAdapter が EtherCAT PDO に接続する。
> VirtualMotorCore と同一の Data Area インターフェース名を採用し、
> tsproj の `<Mappings>` 切り替えのみで仮想/実機を選択可能にする。

### 3.9 接続マップ図 (Phase 1–3)

```
┌──────────────────────────────────────────────────┐
│       ControllerCore (C++ TcCOM)                 │
│       誤差計算 + FB Chain + FF Adder              │
│                                                  │
│  ref_value    ◄──────── ExperimentSequencer      │
│  ff_value     ◄──────── ExperimentSequencer      │
│  position_act ◄──────── VirtualMotorCore         │
│                      (Load 側 1慣性近似)          │
│                                                  │
│  [e = ref - pos] → PID → Lead → Notch → Reso    │
│  [u_fb + ff_value]                                │
│                                                  │
│  control_input ──────► DriverAdapter             │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│       ExperimentSequencer (PLC ST)               │
│       テーブル読み出し専用 (ref / ff / dist)      │
│                                                  │
│  mode_flags ◄──────────── ModeManager            │
│  experiment_active ◄───── ModeManager            │
│                                                  │
│  ref_table[idx]  → ref_value  → ControllerCore   │
│  ff_table[idx]   → ff_value   → ControllerCore   │
│  dist_table[idx] → dist_value → DriverAdapter    │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│       DriverAdapter (PLC ST)                     │
│       ControlInput → Drive 入力整形              │
│                                                  │
│  control_input ◄───────── ControllerCore         │
│  dist_value    ◄───────── ExperimentSequencer    │
│  controlword_in ◄──────── ModeManager            │
│  statusword    ◄───────── VirtualMotorCore       │
│                                                  │
│  target_torque = control_input + dist_value      │
│                                                  │
│  target_torque ──────────► VirtualMotorCore.in (Motor 側)   │
│  controlword_out ────────► VirtualMotorCore.controlword     │
│  statusword_out ─────────► ModeManager                      │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│       ModeManager (StateMachineControl PLC)      │
│       CiA 402 + 実験シーケンス + 安全監視        │
│                                                  │
│  statusword ◄──────────── DriverAdapter          │
│                                                  │
│  controlword ────────────► DriverAdapter         │
│  mode_flags ─────────────► ExperimentSequencer   │
│  experiment_active ──────► ExperimentSequencer   │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│       MATLAB Orchestrator                        │
│                                                  │
│  ───► ADS Write (ExperimentSequencer GVL):        │
│       ref_table[], ff_table[], dist_table[],      │
│       table_len                                   │
│  ───► ADS Write (ControllerCore TcCOM):           │
│       pid_Kp, pid_Ki, pid_Kd, pid_N              │
│       lead_num[], lead_den[]                      │
│       notch_b0..a2, reso_b0..a2                   │
│       enable_pid, enable_lead, enable_notch,      │
│       enable_reso                                 │
│  ───► ADS Write: mode_flags, experiment_active    │
│  ◄─── ADS Read:  ExperimentLogger ステータス     │
│  ◄─── File Read: ログファイル (実験後)            │
└──────────────────────────────────────────────────┘
```

---

## 4. ADS シンボル名規則

### 4.1 ControllerCore (C++ TcCOM)

VirtualMotorCore と同様に、TMC 定義により Data Area を ADS シンボルとして公開する。

```
<instance_name>.<parameter_name>
```

**想定インスタンス名:** `ControllerCore_Obj1 (ControllerModule)`

| シンボルパス (例) | 型 |
|---|---|
| `ControllerCore_Obj1 (ControllerModule).pid_Kp` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).pid_Ki` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).pid_Kd` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).pid_N` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).lead_num` | `LREAL[3]` |
| `ControllerCore_Obj1 (ControllerModule).lead_den` | `LREAL[3]` |
| `ControllerCore_Obj1 (ControllerModule).notch_b0` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).notch_b1` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).notch_b2` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).notch_a1` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).notch_a2` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).reso_b0` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).reso_b1` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).reso_b2` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).reso_a1` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).reso_a2` | `LREAL` |
| `ControllerCore_Obj1 (ControllerModule).enable_pid` | `BOOL` |
| `ControllerCore_Obj1 (ControllerModule).enable_lead` | `BOOL` |
| `ControllerCore_Obj1 (ControllerModule).enable_notch` | `BOOL` |
| `ControllerCore_Obj1 (ControllerModule).enable_reso` | `BOOL` |

> **注記:** テーブル (`ref_table`, `ff_table`, `dist_table`, `table_len`) は
> ControllerCore に含めない。ExperimentSequencer PLC 側 GVL を参照。

### 4.2 VirtualMotorCore (既存・変更なし)

```
VirtualMotorCore_Obj1 (Module1).VirtualMotorParameter.M       → LREAL
VirtualMotorCore_Obj1 (Module1).VirtualMotorParameter.D       → LREAL
VirtualMotorCore_Obj1 (Module1).VirtualMotorParameter.Kt      → LREAL
VirtualMotorCore_Obj1 (Module1).VirtualMotorParameter.tau_limit → LREAL
VirtualMotorCore_Obj1 (Module1).VirtualMotorParameter.vel_limit → LREAL
VirtualMotorCore_Obj1 (Module1).VirtualMotorParameter.task_dt_ns → ULINT
```

### 4.3 ExperimentSequencer (PLC ST)

```
GVL_SEQ.ref_table          → ARRAY[0..N_REF_MAX-1] OF LREAL
GVL_SEQ.ff_table           → ARRAY[0..N_FF_MAX-1] OF LREAL
GVL_SEQ.dist_table         → ARRAY[0..N_DIST_MAX-1] OF LREAL
GVL_SEQ.table_len          → UDINT
```

### 4.4 ExperimentLogger (Phase 3, C++ TcCOM)

```
ExperimentLogger_Obj1 (LoggerModule).LogControl.file_path    → STRING(255)
ExperimentLogger_Obj1 (LoggerModule).LogControl.logging      → BOOL
ExperimentLogger_Obj1 (LoggerModule).LogStatus.records_written → UDINT
ExperimentLogger_Obj1 (LoggerModule).LogStatus.file_size_kb  → UDINT
ExperimentLogger_Obj1 (LoggerModule).LogStatus.error_code    → UDINT
```

### 4.5 ModeManager (StateMachineControl PLC, 既存拡張)

```
GVL_MODE.mode_flags       → UINT
GVL_MODE.experiment_active → BOOL
GVL_MODE.experiment_state  → UINT   (IDLE=0, READY=1, RUNNING=2, DONE=3)
```

---

## 5. タスク構成

### 5.1 Phase 1–3 (1 ms)

| Task 名 | CycleTime | Priority | AmsPort | バインドモジュール |
|---|---|---|---|---|
| VirtualMotorTask | 1,000,000 ns (1 ms) | 1 | 351 | ControllerCore, ExperimentSequencer, DriverAdapter, VirtualMotorCore, (ExperimentLogger) |
| PlcTask1 | 10,000,000 ns (10 ms) | 21 | 352 | ModeManager (StateMachineControl) |

> TmpLogger の PlcTask (1 ms, Priority 20) は Phase 1 統合完了後に撤去予定。

### 5.2 Phase 4 (125 µs = 8 kHz)

| Task 名 | CycleTime | Priority | AmsPort | バインドモジュール |
|---|---|---|---|---|
| ControlTask | 125,000 ns (125 µs) | 1 | 351 | ControllerCore, ExperimentSequencer, DriverAdapter, ExperimentLogger |
| SupervisionTask | 1,000,000 ns (1 ms) | 20 | 352 | ModeManager |

> EtherCAT DC Sync0 = 125 µs に設定。

---

## 6. ExperimentLogger — ファイルロギング仕様 (Phase 3)

> **設計方針:** 8kHz × 100秒 = 800,000 サンプルのシステム同定用データを確実に記録するため、
> C++ TcCOM で実装したファイルライタを用いる。
> RT コンテキストからローカルディスクにバイナリファイルを書き出す。
> 実験後に MATLAB からネットワーク共有またはローカルコピーで読み出す。

### 6.1 ST_LogRecord

```structured-text
TYPE ST_LogRecord :
STRUCT
  seq              : UDINT;    (* シーケンス番号 *)
  t_ns             : ULINT;    (* タイムスタンプ [ns] *)
  motor_position   : LREAL;    (* Motor 側実位置 [rad] *)
  motor_velocity   : LREAL;    (* Motor 側実速度 [rad/s] *)
  motor_torque_act : LREAL;    (* Motor 実トルク [Nm] — Phase 4 *)
  load_position    : LREAL;    (* Load 側実位置 [rad] — FB 対象 *)
  load_velocity    : LREAL;    (* Load 側実速度 [rad/s] *)
  torque_cmd       : LREAL;    (* 指令トルク [Nm] → Motor 側 *)
  error            : LREAL;    (* 位置誤差 = ref - load_position [rad] *)
  ref_value        : LREAL;    (* 指令位置 [rad] *)
  control_input    : LREAL;    (* FB制御出力 u_fb + u_ff [Nm] *)
END_STRUCT
END_TYPE
```

> 1 レコード = 4 + 8 + 8×9 = 84 bytes (アライメント込み: 88 bytes)  
> 8kHz × 100s = 800,000 レコード × 88 bytes ≈ 67 MB
>
> Phase 1–3 (SIL) では `motor_position`, `motor_velocity`, `motor_torque_act` は 0 埋め。
> `load_position` / `load_velocity` に VirtualMotorCore の出力 (1慣性近似) が入る。

### 6.2 ファイル書き込み動作

- **ファイル出力先:** ローカルディスク (例: `C:\ExperimentData\`)
- **ファイルフォーマット:** バイナリ (fixed-size record) — MATLAB で `fread` で直接読み込み可能
- **内部バッファ:** 8,000 レコード (= 1 秒分 @ 8kHz, ≈ 688 KB)
- **flush 戦略:** バッファ満杯時に一括 flush。サイクル分散でジッタを最小化
- **Producer (RT側):** 毎サイクル `ST_LogRecord` を内部バッファに追記。バッファ満杯゛にディスクへ flush
- **実験終了時:** 残余バッファを最終 flush し、ファイルをクローズ
- **MATLAB 側:** ADS 経由でファイルパス・ステータスを取得し、実験後にファイルを読み出す

---

## 7. ControllerCore 内部ブロック図

```
  ref_value ──►(−)──► [PID] ──► [Lead] ──► [Notch] ──► [Reso] ──► u_fb ──►(+)──► control_input
                ▲       ↕          ↕          ↕           ↕              ▲
  position_act ─┘   enable_pid enable_lead enable_notch enable_reso    │
  (Load 側)                                                      ff_value
```

> ControllerCore (C++ TcCOM) は以下を内包:
> 1. **Error Calc:** $e = \text{ref\_value} - \text{position\_act}$ 　(`position_act` = Load 側実位置)
> 2. **FB Chain:** $e \to \text{PID} \to \text{Lead} \to \text{Notch} \to \text{Reso} \to u_{fb}$
> 3. **FF Adder:** $\text{control\_input} = u_{fb} + \text{ff\_value}$
>
> C++ で離散フィルタを直接実装。
> テーブル (大規模配列) は所有せず、全入力がスカラ。

### 7.1a ExperimentSequencer 内部フロー

```
             ExperimentSequencer (PLC ST)
             テーブル読み出し専用 (ref / ff / dist)
  ┌─────────────────────────────────────────────────────────┐
  │                                                         │
  │  ref_table[idx]  ──► ref_value  ──► ControllerCore     │
  │  ff_table[idx]   ──► ff_value   ──► ControllerCore     │
  │  dist_table[idx] ──► dist_value ──► DriverAdapter      │
  │                                                         │
  │  idx: experiment_active=TRUE の間インクリメント          │
  │  idx >= table_len → 再生完了                             │
  └─────────────────────────────────────────────────────────┘
```

### 7.1b DriverAdapter 内部フロー

```
             DriverAdapter (PLC ST)
             ControlInput → Drive 入力整形
  ┌─────────────────────────────────────────────────────────┐
  │                                                         │
  │  ControllerCore.control_input ────────────────► (+) ──► target_torque → Drive
  │  ExperimentSequencer.dist_value ──────────────► (+)    │
  │                                                         │
  │  ModeManager.controlword ──────────► controlword_out → Drive
  │  Drive.statusword ────────────────► statusword_out → ModeManager
  │                                                         │
  └─────────────────────────────────────────────────────────┘
```

### 7.2 Bypass ロジック詳細

各ブロックは C++ の条件分岐で実装:

```cpp
if (m_enable_pid)
  out = PID_block(in);
else
  out = in;          // スルー (ゲイン 1)
```
```

Lead / Notch / Reso も同様。bypass 時はフィルタ内部状態をリセットせず保持する  
(再 enable 時にトランジェントが不要な場合は、MATLAB 側から ADS 経由で内部状態リセットコマンドを発行)。

---

## 8. 設計上の決定事項

| # | 決定 | 根拠 |
|---|---|---|
| D1 | C++ TcCOM — 誤差計算 + FB Chain + FF Adder | TE1400 試用版 100kB 制限を回避。C++ 直接実装で TE1400 への依存を完全排除。ADS Tunable Parameter により Build 不要の設計は維持 |
| D1a | テーブルリプレイは ExperimentSequencer、外乱加算・ControlWord/StatusWord 中継は DriverAdapter | ExperimentSequencer は ref/ff/dist のスカラ出力に専念。DriverAdapter が control_input + dist → target_torque 合成と ControlWord/StatusWord 中継を担当。責務分離を徹底 |
| D2 | FB Chain バイパスフラグ方式 | Build 1 回で全構成を包含。実験条件変更は ADS パラメータ注入のみ |
| D3 | 位相最適共振フィルタは Biquad 形式 | Notch と同一構造で実装コストを抑え、係数で特性を変更可能 |
| D4 | サイクルタイム Phase 1–3 は 1 ms | 既存 VirtualMotorCore の検証済み設定を維持し、段階的に 8 kHz へ移行 |
| D5 | VirtualMotorCore を SIL 基盤として維持 | DriverAdapter と同一 I/F (Load 側出力) で差し替え可能。1慣性近似としてオフライン検証に利用 |
| D6 | TmpLogger は Phase 1 で置換完了 | テーブルリプレイ + SIL 暫定ログを `ExperimentSequencer` (PLC ST) に、Dist 加算を `DriverAdapter` (PLC ST) に移管し、旧 TmpLogger は撤去する |
| D7 | Lead / Notch / Reso は離散伝達関数係数を ADS 注入 | MATLAB で連続→離散変換 (`c2d`) し、係数のみ送信。Build 不要 |
| D8 | ExperimentLogger は C++ TcCOM ファイルライタ方式 | 8kHz × 100s = 800,000 サンプルの長時間記録に対応。Ring Buffer + ADS ではメモリ制約あり。ファイル I/O でデータ量制限なし |
| D9 | 2慣性系構成: Motor 入力 / Load FB | トルク指令は Motor 側、位置 FB は Load 側。ログには Motor/Load 両方の信号を記録。VirtualMotorCore は Load 側 1 慣性近似 |
