# アーキテクチャ設計仕様 — 次世代実験基盤

> **位置づけ:** [ProjectArchitecture.md](ProjectArchitecture.md) の設計思想を具体化したモジュール仕様書。  
> **参照:** ブロック図 → [NewProjectBlock.pu](NewProjectBlock.pu)  
> **現行仕様:** [CurrentProject.md](CurrentProject.md)

---

## 1. モジュール一覧

| # | モジュール名 | 実装方式 | タスク (Phase 1–3 → Phase 4) | 役割 |
|---|---|---|---|---|
| 1 | **ControllerCore** | TE1400 TcObject (Simulink 生成) | VirtualMotorTask 1 ms → ControlTask 125 µs | 誤差計算 + FB 制御チェーン + FF 付加 (スカラ I/O、テーブル非所有) |
| 2 | **ExperimentSequencer** | PLC ST (新規) | VirtualMotorTask 1 ms → ControlTask 125 µs | テーブルリプレイ + Dist 加算 |
| 3 | **VirtualMotorCore** | C++ TcCOM (既存) | VirtualMotorTask 1 ms → ControlTask 125 µs | 仮想モーター物理シミュレーション (SIL 用) |
| 4 | **DriveAdapter** | PLC ST (Phase 4 新規) | ControlTask 125 µs | EtherCAT PDO I/O + CiA 402 状態遷移 |
| 5 | **ExperimentLogger** | PLC ST (Phase 3 新規) | VirtualMotorTask 1 ms → ControlTask 125 µs | Ring Buffer ロギング専用 |
| 6 | **ModeManager** | PLC ST (StateMachineControl 拡張) | PlcTask1 10 ms | CiA 402 + 実験シーケンス管理 + 安全監視 |

### 1.1 Phase 別モジュール構成

```
Phase 1-3 (1 ms):
  ExperimentSequencer ─── ControllerCore ─── VirtualMotorCore ─── ModeManager
                                                       │
                                             ExperimentLogger (Phase 3〜)

Phase 4 (125 µs = 8 kHz):
  ExperimentSequencer ─── ControllerCore ─── DriveAdapter ─── ModeManager
         │                                                        │
         └──── ExperimentLogger ──────────────────────────────────┘
         (VirtualMotorCore は SIL テスト用に維持)
```

> **設計意図:** ControllerCore (TE1400 TcObject) はテーブルを所有しない。
> TE1400 試用版制限を回避しつつ、Simulink ブロック図で制御構造が直感的に見えるよう、
> 誤差計算・FB Chain・FF 付加を ControllerCore 内に配置する。
> テーブルリプレイ・外乱加算は PLC ST (ExperimentSequencer) で実装する。

---

## 2. ControllerCore — Simulink モデル I/O 仕様

> **設計方針:** ControllerCore は誤差計算・FB Chain・FF 付加を担当する。
> Simulink ブロック図で制御構造が直感的に表現されることを重視する。
> テーブル (大規模配列) は所有せず、スカラ入力のみで TE1400 試用版制限を回避する。

### 2.1 入力ポート (Simulink Inport)

| # | ポート名 | データ型 | ソース | 説明 |
|---|---|---|---|---|
| 1 | `ref_value` | `double` | ExperimentSequencer | 位置指令値 (スカラ) [rad] |
| 2 | `ff_value` | `double` | ExperimentSequencer | FF 信号 (スカラ) [Nm] |
| 3 | `position_act` | `double` | DriveAdapter / VirtualMotorCore | 実位置 [rad] |

### 2.2 出力ポート (Simulink Outport)

| # | ポート名 | データ型 | 宛先 | 説明 |
|---|---|---|---|---|
| 1 | `control_input` | `double` | ExperimentSequencer | 制御出力 $u_{fb} + u_{ff}$ [Nm] |

### 2.3 内部処理

1. **Error Calc:** $e = \text{ref\_value} - \text{position\_act}$
2. **FB Chain:** $e \to \text{PID} \to \text{Lead} \to \text{Notch} \to \text{Reso} \to u_{fb}$
3. **FF Adder:** $\text{control\_input} = u_{fb} + \text{ff\_value}$

### 2.3 Tunable Parameters (ADS 注入、Build 不要)

> Simulink Data Dictionary または Model Workspace で `ExportedGlobal` ストレージクラスとして定義。  
> TE1400 ビルド後、TwinCAT ADS シンボルとして自動公開される。

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
> 各 `[Block]` は `Switch` ブロックで `enable ? block_output : input` を選択する。

---

## 2A. ExperimentSequencer — PLC ST 仕様

> **役割:** テーブルリプレイ・外乱加算を PLC ST で実装する。
> ControllerCore (TE1400 TcObject) からテーブルを分離し、TE1400 試用版制限を回避する。
> 誤差計算・FF 付加は ControllerCore (Simulink) 側で実装する。

### 2A.1 機能

1. **Ref Table Replay** — `ref_table[idx]` から位置指令値 `ref_value` (スカラ) を読み出し→ ControllerCore へ
2. **FF Table Replay** — `ff_table[idx]` から FF 値 `ff_value` (スカラ) を読み出し→ ControllerCore へ
3. **Dist Table Replay** — `dist_table[idx]` から外乱値 `dist_value` (スカラ) を読み出し
4. **Dist Adder** — $\text{target\_torque} = \text{control\_input} + u_{dist}$ (最終トルク出力)
5. **テーブルインデックス管理** — `experiment_active` が `TRUE` の間 `idx` をインクリメント。`idx >= table_len` で再生完了。

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
| 1 | `position_act` | `LREAL` | DriveAdapter / VirtualMotorCore | 実位置 [rad] |
| 2 | `velocity_act` | `LREAL` | DriveAdapter / VirtualMotorCore | 実速度 [rad/s] |
| 3 | `control_input` | `LREAL` | ControllerCore | 制御出力 $u_{fb} + u_{ff}$ [Nm] |
| 4 | `mode_flags` | `UINT` | ModeManager | 動作モードフラグ |
| 5 | `experiment_active` | `BOOL` | ModeManager | 実験実行中フラグ |

#### 出力

| # | 変数名 | データ型 | 宛先 | 説明 |
|---|---|---|---|---|
| 1 | `ref_value` | `LREAL` | ControllerCore | 位置指令値 (スカラ) `ref_table[idx]` [rad] |
| 2 | `ff_value` | `LREAL` | ControllerCore | FF 信号 (スカラ) `ff_table[idx]` [Nm] |
| 3 | `target_torque` | `LREAL` | DriveAdapter / VirtualMotorCore | 最終トルク $\text{control\_input} + u_{dist}$ [Nm] |

---

## 3. Data Area — I/O リンク接続マップ

### 3.1 ExperimentSequencer ↔ ControllerCore

```
ExperimentSequencer.ref_value      ──►  ControllerCore.ref_value
ExperimentSequencer.ff_value       ──►  ControllerCore.ff_value
ControllerCore.control_input       ──►  ExperimentSequencer.control_input
```

### 3.2 ControllerCore ↔ VirtualMotorCore (Phase 1–3)

```
VirtualMotorCore.Outputs.VirtualMotorOutputs.position_out  ──►  ControllerCore.position_act
```

### 3.3 ExperimentSequencer ↔ VirtualMotorCore (Phase 1–3)

```
ExperimentSequencer.target_torque  ──►  VirtualMotorCore.Inputs.VirtualMotorInputs.current_in
VirtualMotorCore.Outputs.VirtualMotorOutputs.position_out  ──►  ExperimentSequencer.position_act
VirtualMotorCore.Outputs.VirtualMotorOutputs.velocity_out  ──►  ExperimentSequencer.velocity_act
```

### 3.3 ModeManager (StateMachineControl) ↔ VirtualMotorCore

```
StateMachineControl.MAIN.uiCtrlWord  ──►  VirtualMotorCore.Inputs.controlword
VirtualMotorCore.Outputs.statusword  ──►  StateMachineControl.MAIN.uiStatWord
```

### 3.4 ModeManager → ExperimentSequencer

```
ModeManager.mode_flags        ──►  ExperimentSequencer.mode_flags
ModeManager.experiment_active ──►  ExperimentSequencer.experiment_active
```

### 3.5 ExperimentSequencer ↔ ExperimentLogger (Phase 3〜)

```
ExperimentSequencer.target_torque  ──►  ExperimentLogger.Inputs.torque_cmd
ExperimentSequencer.position_act   ──►  ExperimentLogger.Inputs.position_act
ExperimentSequencer.velocity_act   ──►  ExperimentLogger.Inputs.velocity_act
ExperimentSequencer.ref_value      ──►  ExperimentLogger.Inputs.ref_value
ExperimentSequencer.ff_value       ──►  ExperimentLogger.Inputs.ff_value
ControllerCore.control_input       ──►  ExperimentLogger.Inputs.control_input
(ControllerCore 内部) error        ──►  ExperimentLogger.Inputs.error
```

> `error` は ControllerCore 内部計算値。Simulink Outport として追加するか、
> ExperimentSequencer 側で `ref_value - position_act` として再計算してもよい。

### 3.7 ControllerCore ↔ DriveAdapter (Phase 4)

```
DriveAdapter.Outputs.position_act  ──►  ControllerCore.position_act
```

### 3.8 ExperimentSequencer ↔ DriveAdapter (Phase 4)

```
ExperimentSequencer.target_torque  ──►  DriveAdapter.Inputs.target_torque
DriveAdapter.Outputs.position_act  ──►  ExperimentSequencer.position_act
DriveAdapter.Outputs.velocity_act  ──►  ExperimentSequencer.velocity_act
```

> DriveAdapter は VirtualMotorCore と同一の Data Area インターフェース名を採用し、  
> tsproj の `<Mappings>` 切り替えのみで仮想/実機を選択可能にする。

### 3.9 接続マップ図 (Phase 1–3)

```
┌──────────────────────────────────────────────┐
│       ControllerCore (TE1400 TcObject)            │
│       誤差計算 + FB Chain + FF Adder              │
│                                              │
│  ref_value    ◄────── ExperimentSequencer    │
│  ff_value     ◄────── ExperimentSequencer    │
│  position_act ◄────── VirtualMotorCore       │
│                                              │
│  [e = ref - pos] → PID → Lead → Notch → Reso │
│  [u_fb + ff_value]                            │
│                                              │
│  control_input ────► ExperimentSequencer     │
└──────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│       ExperimentSequencer (PLC ST)                │
│                                                  │
│  position_act ◄────────── VirtualMotorCore.pos   │
│  velocity_act ◄────────── VirtualMotorCore.vel   │
│  control_input ◄───────── ControllerCore         │
│  mode_flags ◄──────────── ModeManager            │
│  experiment_active ◄───── ModeManager            │
│                                                  │
│  ref_table[idx] → ref_value → ControllerCore     │
│  ff_table[idx]  → ff_value  → ControllerCore     │
│  dist_table[idx]→ dist_value                     │
│  target_torque = control_input + u_dist           │
│                                                  │
│  ref_value ────────────►  ControllerCore         │
│  ff_value  ────────────►  ControllerCore         │
│  target_torque ────────►  VirtualMotorCore.in    │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────┐
│       ModeManager                │
│    (StateMachineControl PLC)     │
│                                  │
│  uiCtrlWord ─────────────────────►  VirtualMotorCore.controlword
│  uiStatWord ◄────────────────────── VirtualMotorCore.statusword
└──────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│       MATLAB Orchestrator                        │
│                                                  │
│  ───► ADS Write (ExperimentSequencer GVL):        │
│       ref_table[], ff_table[], dist_table[],      │
│       table_len                                   │
│  ───► ADS Write (ControllerCore TcObject):        │
│       pid_Kp, pid_Ki, pid_Kd, pid_N              │
│       lead_num[], lead_den[]                      │
│       notch_b0..a2, reso_b0..a2                   │
│       enable_pid, enable_lead, enable_notch,      │
│       enable_reso                                 │
│  ───► ADS Write: mode_flags, experiment_active    │
│  ◄─── ADS Read:  ExperimentLogger ring buffer     │
└──────────────────────────────────────────────────┘
```

---

## 4. ADS シンボル名規則

### 4.1 ControllerCore (TE1400 TcObject)

TE1400 で生成された TcObject のシンボルは、TwinCAT プロジェクトでのインスタンス名に依存する。

```
<instance_name>.<parameter_name>
```

**想定インスタンス名:** `ControllerCore_Obj1 (controller_core)`

| シンボルパス (例) | 型 |
|---|---|
| `ControllerCore_Obj1 (controller_core).pid_Kp` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).pid_Ki` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).pid_Kd` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).pid_N` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).lead_num` | `LREAL[3]` |
| `ControllerCore_Obj1 (controller_core).lead_den` | `LREAL[3]` |
| `ControllerCore_Obj1 (controller_core).notch_b0` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).notch_b1` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).notch_b2` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).notch_a1` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).notch_a2` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).reso_b0` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).reso_b1` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).reso_b2` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).reso_a1` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).reso_a2` | `LREAL` |
| `ControllerCore_Obj1 (controller_core).enable_pid` | `BOOL` |
| `ControllerCore_Obj1 (controller_core).enable_lead` | `BOOL` |
| `ControllerCore_Obj1 (controller_core).enable_notch` | `BOOL` |
| `ControllerCore_Obj1 (controller_core).enable_reso` | `BOOL` |

> **注記:** テーブル (`ref_table`, `ff_table`, `dist_table`, `table_len`) は
> ControllerCore に含めない。ExperimentSequencer PLC 側 GVL を参照。
>
> 実際のシンボル名は TE1400 ビルド後に TwinCAT Symbol Manager で確認し、  
> MATLAB 側の `ControllerSymbols` クラスに反映する。

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

### 4.4 ExperimentLogger (Phase 3, PLC ST)

```
GVL_LOG.log_buffer       → ARRAY[0..RING_SIZE-1] OF ST_LogRecord
GVL_LOG.wr_idx           → UDINT
GVL_LOG.rd_idx           → UDINT
GVL_LOG.overflow         → BOOL
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
| VirtualMotorTask | 1,000,000 ns (1 ms) | 1 | 351 | ControllerCore, ExperimentSequencer, VirtualMotorCore, (ExperimentLogger) |
| PlcTask1 | 10,000,000 ns (10 ms) | 21 | 352 | ModeManager (StateMachineControl) |

> TmpLogger の PlcTask (1 ms, Priority 20) はControllerCore 導入後に段階的に廃止。

### 5.2 Phase 4 (125 µs = 8 kHz)

| Task 名 | CycleTime | Priority | AmsPort | バインドモジュール |
|---|---|---|---|---|
| ControlTask | 125,000 ns (125 µs) | 1 | 351 | ControllerCore, ExperimentSequencer, DriveAdapter, ExperimentLogger |
| SupervisionTask | 1,000,000 ns (1 ms) | 20 | 352 | ModeManager |

> EtherCAT DC Sync0 = 125 µs に設定。

---

## 6. ExperimentLogger — ログ構造体仕様 (Phase 3)

### 6.1 ST_LogRecord

```structured-text
TYPE ST_LogRecord :
STRUCT
  seq           : UDINT;    (* シーケンス番号 *)
  t_ns          : ULINT;    (* タイムスタンプ [ns] *)
  position      : LREAL;    (* 実位置 [rad] *)
  velocity      : LREAL;    (* 実速度 [rad/s] *)
  torque_cmd    : LREAL;    (* 指令トルク [Nm] *)
  torque_act    : LREAL;    (* 実トルク [Nm] — Phase 4 で追加 *)
  error         : LREAL;    (* 位置誤差 [rad] *)
  ref_value     : LREAL;    (* 指令位置 [rad] *)
  control_input : LREAL;    (* FB制御出力 u_fb [Nm] *)
END_STRUCT
END_TYPE
```

> 1 レコード = 8 + 8 + 8×7 = 72 bytes  
> Ring Buffer サイズ初期値: 200,000 レコード = 約 13.7 MB

### 6.2 Ring Buffer 動作

- **PLC 側 (Producer):** 毎サイクル `log_buffer[wr_idx MOD RING_SIZE]` に書き込み、`wr_idx` をインクリメント
- **MATLAB 側 (Consumer):** `wr_idx` をポーリングし、`rd_idx` から `wr_idx` までのチャンクを ADS Read。読み出し後 `rd_idx` を更新
- **オーバーフロー:** `wr_idx - rd_idx > RING_SIZE` で `overflow := TRUE`

---

## 7. ControllerCore 内部ブロック図

```
  ref_value ──►(−)──► [PID] ──► [Lead] ──► [Notch] ──► [Reso] ──► u_fb ──►(+)──► control_input
                ▲       ↕          ↕          ↕           ↕              ▲
  position_act ─┘   enable_pid enable_lead enable_notch enable_reso    │
                                                                ff_value
```

> ControllerCore (Simulink モデル) は以下を内包:
> 1. **Error Calc:** $e = \text{ref\_value} - \text{position\_act}$
> 2. **FB Chain:** $e \to \text{PID} \to \text{Lead} \to \text{Notch} \to \text{Reso} \to u_{fb}$
> 3. **FF Adder:** $\text{control\_input} = u_{fb} + \text{ff\_value}$
>
> Simulink ブロック図で制御構造が直感的に見える設計。
> テーブル (大規模配列) は所有せず、全入力がスカラのため TE1400 試用版制限の影響なし。

### 7.1a ExperimentSequencer 内部フロー

```
             ExperimentSequencer (PLC ST)
  ┌─────────────────────────────────────────────────────────┐
  │                                                         │
  │  ref_table[idx]  ──► ref_value  ──► ControllerCore     │
  │  ff_table[idx]   ──► ff_value   ──► ControllerCore     │
  │                                                         │
  │  ControllerCore.control_input ──────────────────► (+) ──► target_torque
  │  dist_table[idx] ────────────────────────────────► (+)    │
  │                                                         │
  │  idx: experiment_active=TRUE の間インクリメント          │
  │  idx >= table_len → target_torque = 0, 再生完了         │
  └─────────────────────────────────────────────────────────┘
```

### 7.2 Bypass ロジック詳細

各ブロックは Simulink の `Switch` ブロックで実装:

```
if enable_pid
  out = PID_block(in)
else
  out = in          % スルー (ゲイン 1)
end
```

Lead / Notch / Reso も同様。bypass 時はフィルタ内部状態をリセットせず保持する  
(再 enable 時にトランジェントが不要な場合は、MATLAB 側から内部状態リセットコマンドを発行)。

---

## 8. 設計上の決定事項

| # | 決定 | 根拠 |
|---|---|---|
| D1 | TE1400 TcObject — 誤差計算 + FB Chain + FF Adder | Simulink ブロック図で制御構造が直感的に見える設計。入力は全スカラで TE1400 試用版制限を回避 |
| D1a | テーブル・外乱加算は PLC ST | ExperimentSequencer に分離。GVL 配列で ADS 注入。PLC はライセンス制限なし |
| D2 | FB Chain バイパスフラグ方式 | Build 1 回で全構成を包含。実験条件変更は ADS パラメータ注入のみ |
| D3 | 位相最適共振フィルタは Biquad 形式 | Notch と同一構造で実装コストを抑え、係数で特性を変更可能 |
| D4 | サイクルタイム Phase 1–3 は 1 ms | 既存 VirtualMotorCore の検証済み設定を維持し、段階的に 8 kHz へ移行 |
| D5 | VirtualMotorCore を SIL 基盤として維持 | DriveAdapter と同一 I/F で差し替え可能。オフライン検証に必須 |
| D6 | TmpLogger は段階的廃止 | テーブルリプレイ→ControllerCore、ログ→ExperimentLogger に機能移管 |
| D7 | Lead / Notch / Reso は離散伝達関数係数を ADS 注入 | MATLAB で連続→離散変換 (`c2d`) し、係数のみ送信。Build 不要 |
