# アーキテクチャ設計仕様 — 次世代実験基盤

> **位置づけ:** [ProjectArchitecture.md](ProjectArchitecture.md) の設計思想を具体化したモジュール仕様書。  
> **参照:** ブロック図 → [NewProjectBlock.pu](NewProjectBlock.pu)  
> **現行仕様:** [CurrentProject.md](CurrentProject.md)  
> **命名規則:** [NamingConvention.md](NamingConvention.md)  
> **実験手順:** [ExperimentProcedure.md](ExperimentProcedure.md)  
> **技術リファレンス:** [TechnicalReference.md](TechnicalReference.md)  
> **未解決課題:** [OpenIssues.md](OpenIssues.md)

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
| 4 | **DriverAdapter** | PLC ST (Phase 1〜) | VirtualMotorTask 1 ms → ControlTask 125 µs | Raw/工学単位変換 + 相対位置化 + 外乱加算 + CW/SW 中継 + トルクゲート (→ [module-specs/DriverAdapter.md](module-specs/DriverAdapter.md)) |
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
> **DriverAdapter によるドライバ差異吸収 (D11):**
> VirtualMotorCore / EtherCAT Drive の I/O を CiA 402 準拠の整数型に統一し、
> DriverAdapter が raw ↔ 工学単位変換と実験開始時の相対位置化を一元的に担う。
> Driver 変更時は Adapter の `ENCODER_RESOLUTION` / `RATED_CURRENT` を書き換えて
> Build するのみで、制御ロジック (ControllerCore) の変更は不要。
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
| 2 | `ff_value` | `double` | ExperimentSequencer | FF 信号 (スカラ) [A] |
| 3 | `position_act` | `double` | DriverAdapter | **Load 側**相対位置 [rad]（Adapter で raw→rad 変換+相対位置化済み）|

### 2.2 出力ポート (TcCOM Data Area Output)

| # | ポート名 | データ型 | 宛先 | 説明 |
|---|---|---|---|---|
| 1 | `control_input` | `double` | DriverAdapter | 制御出力 $u_{fb} + u_{ff}$ [A] |

### 2.3 内部処理

1. **Error Calc:** $e = \text{ref\_value} - \text{position\_act}$ 　(`position_act` = DriverAdapter 出力の相対位置 [rad])
2. **FB Chain:** $e \to \text{PID} \to \text{Lead} \to \text{Notch} \to \text{Reso} \to u_{fb}$
3. **FF Adder:** $\text{control\_input} = u_{fb} + \text{ff\_value}$

> **D12 移行注記:** 相対位置化 (`positionRel = positionAct - positionOffset`) は DriverAdapter に移管済み。
> ControllerCore の `positionOffset` / `positionRel` 出力は廃止し、`position_act` は Adapter の `positionRel` をそのまま受け取る。
> ControllerCore のリセット時は biquad 内部状態クリアのみを行い、位置オフセット処理は行わない。

### 2.3 Tunable Parameters (ADS 注入、Build 不要)

> TMC (TwinCAT Module Class) 定義により Data Area として公開し、ADS シンボルとしてアクセス可能にする。
> VirtualMotorCore と同様の方式。

> **注記:** テーブル (`ref_table`, `ff_table`, `dist_table`, `table_len`) は ControllerCore に含めない。
> ExperimentSequencer (PLC ST) 側の GVL に配置。→ §2A 参照。

#### 2.3.1 PID パラメータ (`PIDParams : ST_PID`)

| パラメータ名 | データ型 | 説明 |
|---|---|---|
| `PIDParams.pidB0` | `double` | PID 用 biquad 分子係数 $b_0$ |
| `PIDParams.pidB1` | `double` | PID 用 biquad 分子係数 $b_1$ |
| `PIDParams.pidB2` | `double` | PID 用 biquad 分子係数 $b_2$ |
| `PIDParams.pidA1` | `double` | PID 用 biquad 分母係数 $a_1$ |
| `PIDParams.pidA2` | `double` | PID 用 biquad 分母係数 $a_2$ |

> **注記:** PID の連続時間パラメータ (`Kp`, `Ki`, `Kd`, `N`) は MATLAB 側で離散化し、biquad 係数に変換して注入する。

#### 2.3.2 Lead Compensator パラメータ (`LeadParams : ST_PhaseLead`)

| パラメータ名 | データ型 | 説明 |
|---|---|---|
| `LeadParams.leadB0` | `double` | Lead 用 biquad 分子係数 $b_0$ |
| `LeadParams.leadB1` | `double` | Lead 用 biquad 分子係数 $b_1$ |
| `LeadParams.leadB2` | `double` | Lead 用 biquad 分子係数 $b_2$ |
| `LeadParams.leadA1` | `double` | Lead 用 biquad 分母係数 $a_1$ |
| `LeadParams.leadA2` | `double` | Lead 用 biquad 分母係数 $a_2$ |

#### 2.3.3 Notch Filter パラメータ (`NotchParams : ST_Notch`)

| パラメータ名 | データ型 | 説明 |
|---|---|---|
| `NotchParams.notchB0` | `double` | Biquad 分子係数 $b_0$ |
| `NotchParams.notchB1` | `double` | Biquad 分子係数 $b_1$ |
| `NotchParams.notchB2` | `double` | Biquad 分子係数 $b_2$ |
| `NotchParams.notchA1` | `double` | Biquad 分母係数 $a_1$ |
| `NotchParams.notchA2` | `double` | Biquad 分母係数 $a_2$ |

#### 2.3.4 位相最適共振フィルタ パラメータ (`ResoParams : ST_Reso`)

| パラメータ名 | データ型 | 説明 |
|---|---|---|
| `ResoParams.resoB0` | `double` | Biquad 分子係数 $b_0$ |
| `ResoParams.resoB1` | `double` | Biquad 分子係数 $b_1$ |
| `ResoParams.resoB2` | `double` | Biquad 分子係数 $b_2$ |
| `ResoParams.resoA1` | `double` | Biquad 分母係数 $a_1$ |
| `ResoParams.resoA2` | `double` | Biquad 分母係数 $a_2$ |

#### 2.3.5 Enable / Bypass フラグ (`EnableParams : ST_FilterEnable`)

| パラメータ名 | データ型 | デフォルト | 説明 |
|---|---|---|---|
| `EnableParams.enablePid` | `boolean` | `true` | PID ブロックの有効/バイパス |
| `EnableParams.enableLead` | `boolean` | `false` | Lead Compensator の有効/バイパス |
| `EnableParams.enableNotch` | `boolean` | `false` | Notch Filter の有効/バイパス |
| `EnableParams.enableReso` | `boolean` | `false` | 位相最適共振フィルタの有効/バイパス |

> **注記:** `enablePid` のデフォルトは実装上 `true`。MATLAB 側では常に正規フィールド `EnableParams.enablePid` を明示設定する。

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
| `ff_table` | `LREAL[]` | `[0..N_FF_MAX-1]` | フィードフォワードテーブル [A] |
| `dist_table` | `LREAL[]` | `[0..N_DIST_MAX-1]` | 外乱テーブル [A] |
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
| 2 | `ff_value` | `LREAL` | ControllerCore | FF 信号 (スカラ) `ff_table[idx]` [A] |
| 3 | `dist_value` | `LREAL` | DriverAdapter | 外乱値 (スカラ) `dist_table[idx]` [A] |

---

## 2B. DriverAdapter — PLC ST 仕様

> **役割:** ドライバ差異吸収層。Drive (VirtualMotorCore / EtherCAT) の raw 信号 (パルス数、‰定格トルク) を
> 工学単位 (rad, rad/s, A) に変換し、制御モジュール群に統一インターフェースを提供する。
> 外乱加算 (Dist Adder)、ControlWord / StatusWord 中継、トルクゲート、
> および実験開始時の相対位置化を担当する。
> Phase 1–3 では VirtualMotorCore に接続し、Phase 4 で EtherCAT PDO I/O に切り替える。
> **Driver 変更時は `ENCODER_RESOLUTION` / `RATED_CURRENT` を書き換えて Build するのみ。**
> 詳細仕様は [module-specs/DriverAdapter.md](module-specs/DriverAdapter.md) を参照。

### 2B.1 機能

1. **Raw → 工学単位変換** — position [pulses]→[rad], velocity [pulses/s]→[rad/s], torque [‰ rated]→[A]
2. **工学単位 → Raw 変換** — targetTorque [A]→[‰ rated]
3. **電流クランプ** — `targetCurrentA` を `±MAX_CURRENT_A` でクランプ (モーター保護)
3. **相対位置化** — リセット時に絶対位置をキャプチャし、以降 `positionRel` として公開 (D12)
4. **Dist Adder** — $\text{target\_torque} = \text{control\_input} + \text{dist\_value}$ (最終トルク出力 → Motor 側)
5. **ControlWord 中継** — ModeManager が生成した `controlword` を Drive へ転送
6. **StatusWord 中継** — Drive から受信した `statusword` を ModeManager へ転送
7. **電流ゲート** — `enableCurrentOutput = FALSE` 時に `targetTorque := 0`

### 2B.2 定数パラメータ (`GVL_DRV` — `VAR_GLOBAL CONSTANT`)

| 定数名 | データ型 | 例値 | 説明 |
|---|---|---|---|
| `ENCODER_RESOLUTION` | `UDINT` | `8388608` (2²³) | エンコーダ分解能 [pulses/rev] |
| `RATED_CURRENT` | `LREAL` | `1.2` | 定格電流 [A] |
| `MAX_CURRENT_A` | `LREAL` | `1.5` | 電流クランプ上限 [A] (モーター保護) |
| `TWO_PI_INV_RES` | `LREAL` | (導出値) | $2\pi / \text{ENCODER\_RESOLUTION}$ [rad/pulse] |
| `RATED_CURRENT_INV_X1000` | `LREAL` | (導出値) | $1000 / \text{RATED\_CURRENT}$ [‰/A] |
| `RATED_CURRENT_DIV_1000` | `LREAL` | (導出値) | $\text{RATED\_CURRENT} / 1000$ [A/‰] |

### 2B.3 入出力

#### 入力 — Drive 側 raw 信号

| # | 変数名 | データ型 | ソース | 説明 |
|---|---|---|---|---|
| 1 | `positionActualValue` | `DINT` | VirtualMotor / EtherCAT | 実位置 [pulses] |
| 2 | `velocityActualValue` | `DINT` | VirtualMotor / EtherCAT | 実速度 [pulses/s] |
| 3 | `torqueActualValue` | `INT` | VirtualMotor / EtherCAT | 実トルク [‰ rated] |
| 4 | `statusword` | `UINT` | VirtualMotor / EtherCAT | CiA 402 StatusWord |

#### 入力 — 制御側

| # | 変数名 | データ型 | ソース | 説明 |
|---|---|---|---|---|
| 5 | `control_input` | `LREAL` | ControllerCore | 制御出力 $u_{fb} + u_{ff}$ [A] |
| 6 | `dist_value` | `LREAL` | ExperimentSequencer | 外乱値 (スカラ) [A] |
| 7 | `controlword_in` | `UINT` | ModeManager | CiA 402 ControlWord (ModeManager 生成) |
| 8 | `enableCurrentOutput` | `BOOL` | ModeManager | 電流ゲート有効フラグ |
| 9 | `resetReq` | `BOOL` | ModeManager | リセット要求 (エッジ検出) |

#### 出力 — 工学単位変換済み

| # | 変数名 | データ型 | 宛先 | 説明 |
|---|---|---|---|---|
| 1 | `positionRel` | `LREAL` | ControllerCore / ExperimentLogger | 相対位置 [rad] |
| 2 | `velocityAct` | `LREAL` | ExperimentLogger | 速度 [rad/s] |
| 3 | `currentAct` | `LREAL` | ExperimentLogger | 実電流 [A] |
| 4 | `statusword_out` | `UINT` | ModeManager | CiA 402 StatusWord (中継) |

#### 出力 — Drive 側 raw

| # | 変数名 | データ型 | 宛先 | 説明 |
|---|---|---|---|---|
| 5 | `target_torque` | `INT` | VirtualMotor / EtherCAT | 指令トルク [‰ rated] |
| 6 | `controlword_out` | `UINT` | VirtualMotor / EtherCAT | CiA 402 ControlWord (中継) |

> **Phase 4 拡張:**
> EtherCAT PDO マッピングへの切り替えは tsproj の `<Mappings>` 変更のみ。
> DriverAdapter 内部ロジックの変更は不要。
> `ENCODER_RESOLUTION` / `RATED_CURRENT` を実機ドライバの仕様に合わせて書き換え → Build。

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
DriverAdapter.target_torque (INT, ‰ rated)   ──►  VirtualMotorCore.Inputs.targetTorque       (Motor 側入力)
DriverAdapter.controlword_out                  ──►  VirtualMotorCore.Inputs.controlWord
VirtualMotorCore.Outputs.statusWord            ──►  DriverAdapter.statusword
VirtualMotorCore.Outputs.positionActualValue   ──►  DriverAdapter.positionActualValue    (DINT, pulses)
VirtualMotorCore.Outputs.velocityActualValue   ──►  DriverAdapter.velocityActualValue    (DINT, pulses/s)
VirtualMotorCore.Outputs.torqueActualValue     ──►  DriverAdapter.torqueActualValue      (INT, ‰ rated)
DriverAdapter.positionRel (LREAL, rad)         ──►  ControllerCore.position_act          (Load 側 FB, 相対位置化済み)
```

> VirtualMotorCore は CiA 402 PDO 準拚の整数型 I/O を提供 (D11).
> DriverAdapter が raw → 工学単位変換 + 相対位置化を行い、ControllerCore に `positionRel` を供給。

### 3.5 ModeManager ↔ DriverAdapter

```
ModeManager.controlword            ──►  DriverAdapter.controlword_in
ModeManager.resetOut               ──►  DriverAdapter.resetReq
ModeManager.enableCurrentOutput     ──►  DriverAdapter.enableCurrentOutput
DriverAdapter.statusword_out       ──►  ModeManager.statusword
```

> ModeManager が CiA 402 ControlWord を生成し、DriverAdapter が Drive へ中継する。
> Drive (VirtualMotorCore / EtherCAT) の StatusWord は DriverAdapter 経由で ModeManager に返る。
> `resetOut` は DriverAdapter の `positionOffsetRad` キャプチャにも使用される (D12)。

### 3.6 ModeManager → ExperimentSequencer

```
ModeManager.mode_flags        ──►  ExperimentSequencer.mode_flags
ModeManager.experiment_active ──►  ExperimentSequencer.experiment_active
```

### 3.7 各モジュール → ExperimentLogger (Phase 3〜)

```
DriverAdapter.positionRel                                  ──►  ExperimentLogger.Inputs.load_position    (Adapter 変換済み相対位置)
DriverAdapter.velocityAct                                  ──►  ExperimentLogger.Inputs.load_velocity    (Adapter 変換済み速度)
DriverAdapter.currentAct                                    ──►  ExperimentLogger.Inputs.motor_current_act (Adapter 変換済み実電流)
DriverAdapter.target_torque                                ──►  ExperimentLogger.Inputs.torque_cmd       (‰ rated → Logger 側で Nm 記録 or raw 記録を検討)
ExperimentSequencer.ref_value                              ──►  ExperimentLogger.Inputs.ref_value
ExperimentSequencer.ff_value                               ──►  ExperimentLogger.Inputs.ff_value
ControllerCore.control_input                               ──►  ExperimentLogger.Inputs.control_input
ControllerCore.error                                       ──►  ExperimentLogger.Inputs.error
```

> `error` は ControllerCore の Data Area Output として公開する。
> Phase 1–3 (SIL) でも `motor_current_act` は VirtualMotorCore の `torqueActualValue` 経由で
> DriverAdapter が A 変換した値が入る (D13、H3 解消)。
> `load_position` / `load_velocity` は DriverAdapter が raw→rad 変換+相対位置化した値が入る。
> `motor_position` / `motor_velocity` は Phase 4 で2軸構成時に追加予定。

**制御信号 (ロギング制御 + fast-path 停止):**

```
ModeManager.experimentActiveOut                            ──►  ExperimentLogger.Inputs.loggingReq       (ファイル open/close 制御、PlcTask 経由)
ExperimentSequencer.playbackDone                           ──►  ExperimentLogger.Inputs.playbackDone     (同一タスク fast-path、即時記録停止)
```

> `loggingReq` は引き続きファイル open/close の制御に使用する。
> `playbackDone` は同一 VirtualMotorTask 内で logger に直接マッピングし、レコード追記のみを 1 スキャン以内に停止させる。

### 3.8 DriverAdapter ↔ EtherCAT Drive (Phase 4)

```
DriverAdapter.target_torque (INT, ‰ rated)     ──►  EtherCAT.PDO.targetTorque      (Motor 側入力)
DriverAdapter.controlword_out                    ──►  EtherCAT.PDO.controlword
EtherCAT.PDO.statusword                          ──►  DriverAdapter.statusword
EtherCAT.PDO.positionActualValue (DINT, pulses)  ──►  DriverAdapter.positionActualValue
EtherCAT.PDO.velocityActualValue (DINT, pulses/s)──►  DriverAdapter.velocityActualValue
EtherCAT.PDO.torqueActualValue (INT, ‰ rated)   ──►  DriverAdapter.torqueActualValue
```

> Phase 4 では DriverAdapter が EtherCAT PDO に接続する。
> VirtualMotorCore と同一の CiA 402 整数型 I/O を採用し、
> tsproj の `<Mappings>` 切り替えのみで仮想/実機を選択可能にする (D11)。
> `ENCODER_RESOLUTION` / `RATED_CURRENT` を実機ドライバの仕様に書き換え → Build。

### 3.9 接続マップ図 (Phase 1–3)

```
┌──────────────────────────────────────────────────┐
│       ControllerCore (C++ TcCOM)                 │
│       誤差計算 + FB Chain + FF Adder              │
│                                                  │
│  ref_value    ◄──────── ExperimentSequencer      │
│  ff_value     ◄──────── ExperimentSequencer      │
│  position_act ◄──────── DriverAdapter.positionRel│
│                      (相対位置化済み)             │
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
│       PIDParams.pidB0..pidA2                      │
│       LeadParams.leadB0..leadA2                   │
│       NotchParams.notchB0..notchA2                │
│       ResoParams.resoB0..resoA2                   │
│       EnableParams.enablePid / enableLead /       │
│       enableNotch / enableReso                    │
│  ───► ADS Write: GVL_MODE.modeFlags               │
│  ◄─── ADS Read:  ExperimentLogger ステータス     │
│  ◄─── File Read: ログファイル (実験後)            │
└──────────────────────────────────────────────────┘
```

---

## 4. ADS シンボル名規則

### 4.1 ControllerCore (C++ TcCOM)

TMC 定義により Data Area を ADS シンボルとして公開する。

```
<instance_name>.<parameter_name>
```

**インスタンス名:** `ControllerCore_Obj1 (Module1)`

| シンボルパス (例) | 型 |
|---|---|
| `ControllerCore_Obj1 (Module1).PIDParams.pidB0` | `LREAL` |
| `ControllerCore_Obj1 (Module1).PIDParams.pidB1` | `LREAL` |
| `ControllerCore_Obj1 (Module1).PIDParams.pidB2` | `LREAL` |
| `ControllerCore_Obj1 (Module1).PIDParams.pidA1` | `LREAL` |
| `ControllerCore_Obj1 (Module1).PIDParams.pidA2` | `LREAL` |
| `ControllerCore_Obj1 (Module1).LeadParams.leadB0` | `LREAL` |
| `ControllerCore_Obj1 (Module1).LeadParams.leadB1` | `LREAL` |
| `ControllerCore_Obj1 (Module1).LeadParams.leadB2` | `LREAL` |
| `ControllerCore_Obj1 (Module1).LeadParams.leadA1` | `LREAL` |
| `ControllerCore_Obj1 (Module1).LeadParams.leadA2` | `LREAL` |
| `ControllerCore_Obj1 (Module1).NotchParams.notchB0` | `LREAL` |
| `ControllerCore_Obj1 (Module1).NotchParams.notchB1` | `LREAL` |
| `ControllerCore_Obj1 (Module1).NotchParams.notchB2` | `LREAL` |
| `ControllerCore_Obj1 (Module1).NotchParams.notchA1` | `LREAL` |
| `ControllerCore_Obj1 (Module1).NotchParams.notchA2` | `LREAL` |
| `ControllerCore_Obj1 (Module1).ResoParams.resoB0` | `LREAL` |
| `ControllerCore_Obj1 (Module1).ResoParams.resoB1` | `LREAL` |
| `ControllerCore_Obj1 (Module1).ResoParams.resoB2` | `LREAL` |
| `ControllerCore_Obj1 (Module1).ResoParams.resoA1` | `LREAL` |
| `ControllerCore_Obj1 (Module1).ResoParams.resoA2` | `LREAL` |
| `ControllerCore_Obj1 (Module1).EnableParams.enablePid` | `BOOL` |
| `ControllerCore_Obj1 (Module1).EnableParams.enableLead` | `BOOL` |
| `ControllerCore_Obj1 (Module1).EnableParams.enableNotch` | `BOOL` |
| `ControllerCore_Obj1 (Module1).EnableParams.enableReso` | `BOOL` |

> **注記:** テーブル (`refTable`, `ffTable`, `distTable`, `tableLen`) は
> ControllerCore に含めない。ExperimentSequencer PLC 側 GVL を参照。

### 4.2 VirtualMotorCore

```
VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.mass             → LREAL
VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.damping          → LREAL
VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.tauLimit         → LREAL
VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.velLimit         → LREAL
VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.taskDtNs         → ULINT
VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.encoderResolution → UDINT  (NEW: D11)
VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.ratedTorque       → LREAL  (D11, M16で一本化、kt=1 前提で RATED_CURRENT と同一値)
VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.maxPermille        → LREAL  (入力上限 [‰ rated], 0=無制限)
```

> `VirtualMotor1Parameter` は `CreateSymbol="true"` で ADS Discovery 確認済み。
> `encoderResolution` / `ratedTorque` / `maxPermille` は D11 で追加。詳細は [module-specs/VirtualMotorCore.md](module-specs/VirtualMotorCore.md) を参照。

### 4.3 ExperimentSequencer (PLC ST, Port 853)

```
GVL_SEQ.refTable           → ARRAY[0..99999] OF LREAL
GVL_SEQ.ffTable            → ARRAY[0..99999] OF LREAL
GVL_SEQ.distTable          → ARRAY[0..99999] OF LREAL
GVL_SEQ.tableLen           → UDINT
```

### 4.4 ExperimentLogger (Phase 3, C++ TcCOM, Port 351)

```
ExperimentLogger_Obj1 (Module1).LogControl.filePath          → STRING(255)
ExperimentLogger_Obj1 (Module1).Outputs.LogStatus.recordsWritten → UDINT
ExperimentLogger_Obj1 (Module1).Outputs.LogStatus.fileSizeKb    → UDINT
ExperimentLogger_Obj1 (Module1).Outputs.LogStatus.errorCode     → UDINT
```

> ログ開始/停止は `Inputs.loggingReq`（ModeManager 連動）のみを使用する。

### 4.5 ModeManager (StateMachineControl PLC, Port 852)

```
GVL_MODE.modeFlags         → UINT   (Write: ビットフラグ一括制御)
GVL_MODE.experimentActive  → BOOL   (Read: ModeManager 出力)
GVL_MODE.experimentState   → UINT   (Read: IDLE=0, READY=1, RUNNING=2, DONE=3)
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
  motor_current_act : LREAL;    (* Motor 実電流 [A] — Phase 4 *)
  load_position    : LREAL;    (* Load 側実位置 [rad] — FB 対象 *)
  load_velocity    : LREAL;    (* Load 側実速度 [rad/s] *)
  current_cmd      : LREAL;    (* 指令電流 [A] → Motor 側 *)
  error            : LREAL;    (* 位置誤差 = ref - load_position [rad] *)
  ref_value        : LREAL;    (* 指令位置 [rad] *)
  ff_value         : LREAL;    (* フィードフォワード値 [A] *)
  control_input    : LREAL;    (* FB制御出力 u_fb + u_ff [A] *)
END_STRUCT
END_TYPE
```

> 1 レコード = 4 + 4(pad) + 8 + 8×10 = 96 bytes  
> 8kHz × 100s = 800,000 レコード × 96 bytes ≈ 76.8 MB
>
> Phase 1–3 (SIL) では `motor_position`, `motor_velocity` は 0 埋め。
> `motor_current_act` は VirtualMotorCore の `torqueActualValue` 経由で DriverAdapter が A 変換した値が入る (D13)。
> `load_position` / `load_velocity` に DriverAdapter の raw→工学単位変換 + 相対位置化済みの値が入る。

### 6.2 ファイル書き込み動作

- **ファイル出力先:** ローカルディスク (例: `C:\ExperimentData\`)
- **ファイルフォーマット:** バイナリ (fixed-size record) — MATLAB で `fread` で直接読み込み可能
- **内部バッファ:** 8,000 レコード (= 1 秒分 @ 8kHz, ≈ 768 KB)
- **flush 戦略:** バッファ満杯時に一括 flush。サイクル分散でジッタを最小化
- **Producer (RT側):** 毎サイクル `ST_LogRecord` を内部バッファに追記。バッファ満杯゛にディスクへ flush
- **実験終了時:** 残余バッファを最終 flush し、ファイルをクローズ
- **MATLAB 側:** ADS 経由でファイルパス・ステータスを取得し、実験後にファイルを読み出す

> **ログ終端精度 (H6):** `loggingReq` は ModeManager (PlcTask 10 ms) 経由のままファイル open/close を担う。一方で `Inputs.playbackDone` を同一タスク内でマッピングし、ExperimentSequencer が `playbackDone = TRUE` を発行したスキャンでレコード追記を停止することで、クロスタスク遅延由来のゼロ値テール混入を防ぐ。

---

## 7. ControllerCore 内部ブロック図

```
  ref_value ──►(−)──► [PID] ──► [Lead] ──► [Notch] ──► [Reso] ──► u_fb ──►(+)──► control_input
                ▲       ↕          ↕          ↕           ↕              ▲
  position_act ─┘   enable_pid enable_lead enable_notch enable_reso    │
  (Load 側)                                                      ff_value
```

> ControllerCore (C++ TcCOM) は以下を内包:
> 1. **Error Calc:** $e = \text{ref\_value} - \text{position\_act}$ 　(`position_act` = DriverAdapter 出力の相対位置)
> 2. **FB Chain:** $e \to \text{PID} \to \text{Lead} \to \text{Notch} \to \text{Reso} \to u_{fb}$
> 3. **FF Adder:** $\text{control\_input} = u_{fb} + \text{ff\_value}$
>
> C++ で離散フィルタを直接実装。
> テーブル (大規模配列) は所有せず、全入力がスカラ。
> 相対位置化は DriverAdapter が担当 (D12)。

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
             ドライバ差異吸収層 — raw/工学単位変換 + 相対位置化
  ┌─────────────────────────────────────────────────────────────────┐
  │  [Drive → 工学単位]                                               │
  │  positionActualValue (DINT) ─ ×TWO_PI_INV_RES ─ positionRad     │
  │  velocityActualValue (DINT) ─ ×TWO_PI_INV_RES ─ velocityAct     │
  │  torqueActualValue (INT) ─ ×RATED_CURRENT_DIV_1000 ─ currentAct   │
  │                                                                 │
  │  [相対位置化]                                                    │
  │  positionRad - positionOffsetRad → positionRel ─► CC / Logger   │
  │    (resetReq edge → capture offset)                             │
  │                                                                 │
  │  [工学単位 → Drive]                                              │
  │  controlInput + distValue → clamp(±MAX_CURRENT_A)                │
  │    → ×RATED_CURRENT_INV_X1000                                   │
  │    → targetTorque (INT, ‰ rated) ─► Drive                      │
  │  enableCurrentOutput=FALSE → targetTorque := 0                    │
  │                                                                 │
  │  controlWord 中継 / statusWord 中継                              │
  └─────────────────────────────────────────────────────────────────┘
```

> 詳細仕様は [module-specs/DriverAdapter.md](module-specs/DriverAdapter.md) を参照。

### 7.2 Bypass ロジック詳細

各ブロックは C++ の条件分岐で実装:

```cpp
if (m_enable_pid)
  out = PID_block(in);
else
  out = in;          // スルー (ゲイン 1)
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
| D10 | **ModeManager-only 状態制御** | 状態制御フロー (`modeFlags`, `experimentActive`, `resetReq`) は ModeManager (`GVL_MODE`) のみを経由する。MATLAB が ExperimentSequencer に直接書込むのは **テーブルデータのみ** 。詳細は [OpenIssues.md](OpenIssues.md) M2 |
| D11 | **DriverAdapter でドライバ差異を吸収 (CiA 402 整数型 I/O)** | VirtualMotor と実機 EtherCAT Drive の I/O を CiA 402 準拚の整数型 (position: DINT [pulses], velocity: DINT [pulses/s], torque: INT [‰ rated]) に統一。Adapter の `ENCODER_RESOLUTION` / `RATED_CURRENT` 定数で工学単位変換。Driver 変更時は定数を書き換えて Build するのみ。詳細は [module-specs/DriverAdapter.md](module-specs/DriverAdapter.md) / [module-specs/VirtualMotorCore.md](module-specs/VirtualMotorCore.md) |
| D12 | **相対位置化を ControllerCore → DriverAdapter に移管** | 実機ドライバはエンコーダ絶対値を出力する。相対位置化はドライバ抽象化の一部として Adapter で行うべき。ControllerCore の `positionOffset` / `positionRel` は廃止し、Adapter の `positionOffsetRad` で代替 |
| D13 | **VirtualMotor に `torqueActualValue` を追加** | CiA 402 ドライバは実トルクを出力する。SIL でも同等の出力を提供することで H3 を解消。Adapter で A 変換後 ExperimentLogger の `motorCurrentAct` に接続 |

### 8.1 ADS アクセス設計方針

MATLAB からの ADS アクセスは以下の原則に従う:

| カテゴリ | アクセス方式 | 理由 |
|---|---|---|
| **状態制御** (`modeFlags`, `experimentActive`) | `GVL_MODE` のみ → ModeManager 経由 | 一元管理。競合回避 |
| **テーブルプリロード** (`refTable`, `ffTable`, `distTable`, `tableLen`) | `GVL_SEQ` に直接書込 (Port 853) | 大容量データ (最大 800KB/テーブル)。ModeManager 経由は非現実的 |
| **制御パラメータ注入** (`*Params.*`) | ControllerCore TcCOM に直接書込 (Port 351) | C++ Data Area。PLC を経由する設計的理由なし |
| **VM パラメータ注入** (`VirtualMotor1Parameter.*`) | VirtualMotorCore TcCOM に直接書込 (Port 351) | 同上 |
| **ログ制御/読出し** | ExperimentLogger TcCOM (Port 351) / `GVL_SEQ_LOG` (Port 853) | Phase 3 以降 |
| **状態監視** (`experimentState`) | `GVL_MODE` 読出し (Port 852) | 正当 |
