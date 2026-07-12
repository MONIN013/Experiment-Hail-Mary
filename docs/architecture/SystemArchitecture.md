# System Architecture

> **位置づけ:** [ProjectOverview](../overview/ProjectOverview.md) の設計思想を具体化した現行実装の正本仕様  
> **対象読者:** TwinCAT / MATLAB 実装者、構成変更を行う設計者  
> **更新条件:** モジュール境界、I/O 契約、制御フロー、タスク/ポート構成が変わったとき  
> **関連文書:** [ProjectOverview](../overview/ProjectOverview.md) / [TechnicalReference](./TechnicalReference.md) / [ExperimentProcedure](../operations/ExperimentProcedure.md) / [NamingConvention](../operations/NamingConvention.md) / [NewProjectBlock.pu](./diagrams/NewProjectBlock.pu)

---

## 0. 現行構成の要点

* checked-in TwinCAT project は `ExperimentHailMary.tsproj` (VM variant) と `ExperimentHailMary.RealMotor.tsproj` (real-motor mapping scaffold) の 2 本を持つ。
* どちらの project でも **`VirtualMotorTask = 125 us (8 kHz)`** を正とする。
* `ExperimentSequencer`, `ControllerCore`, `DriverAdapter`, `VirtualMotorCore`, `ExperimentLogger` は同一 RT タスク上で動作する。
* `ModeManager` は `StateMachineControl` 内の PLC FSM として `PlcTask1 (10 ms)` で動作し、reset handshake / watchdog / logger handshake を管理する。
* `DriverAdapter` の active 実装は **C++ TcCOM** (`DriverAdapter_Obj1 (Module1)`) である。
* DriverAdapter の実装正本は C++ TcCOM `DriverAdapter/` のみである。

---

## 1. モジュール一覧

| # | モジュール名 | 実装方式 | Task / Port | 主責務 |
|---|---|---|---|---|
| 1 | **ControllerCore** | C++ TcCOM | `VirtualMotorTask` / 351 | 誤差計算 + FB チェーン + FF 加算 |
| 2 | **ExperimentSequencer** | PLC ST | `VirtualMotorTask` / 853 | `ref/ff/dist` テーブル再生、repeat 管理、完了通知 |
| 3 | **DriverAdapter** | C++ TcCOM | `VirtualMotorTask` / 351 | Motor/Load raw 変換、相対位置化、外乱加算、CW/SW 中継、電流ゲート |
| 4 | **VirtualMotorCore** | C++ TcCOM | `VirtualMotorTask` / 351 | SIL 用仮想モーター、CiA 402 エミュレーション |
| 5 | **ExperimentLogger** | C++ TcCOM | `VirtualMotorTask` / 351 | 固定長バイナリファイルロギング |
| 6 | **ModeManager** (`StateMachineControl`) | PLC ST | `PlcTask1` / 852 | 状態遷移、reset handshake、heartbeat watchdog、logger handshake |

### 1.1 現行データフロー

```text
ExperimentSequencer.refValue  ─┐
ExperimentSequencer.ffValue   ├─► ControllerCore ─► controlInput ─┐
                              │                                    │
ExperimentSequencer.distValue └────────────────────────────────────┤
                                                                   ▼
                                                           DriverAdapter
                                                     (currentCmd / targetTorque)
                                                                   │
                                        VirtualMotorCore ◄─────────┘
                                                                   │
                                               load.positionRel ───┘
                                                                   ▼
                                                           ControllerCore

ModeManager ─► experimentActive / resetOut / enableCurrentOut / motorCtrlWord / loadCtrlWord
ModeManager ◄─ motorStatusWordOut / loadStatusWordOut / loggerReady / loggerFileReleased / loggerErrorCode

ExperimentLogger ◄─ Inputs.record.(refValue / ffValue / controlInput / error /
                    currentCmd / load.position / load.velocity /
                    motor.currentAct)
ExperimentLogger ◄─ Inputs.control.playbackDone
```

---

## 2. モジュール境界と公開契約

### 2.1 ControllerCore

**入力**

| ポート | 型 | ソース | 説明 |
|---|---|---|---|
| `refValue` | `LREAL` | ExperimentSequencer | 位置指令 [rad] |
| `ffValue` | `LREAL` | ExperimentSequencer | FF 値 [A] |
| `positionAct` | `LREAL` | DriverAdapter | Load 側相対位置 [rad] |
| `resetReq` | `BOOL` | ModeManager | biquad 内部状態リセット |

**出力**

| ポート | 型 | 宛先 | 説明 |
|---|---|---|---|
| `controlInput` | `LREAL` | DriverAdapter / ExperimentLogger | 制御出力 [A] |
| `error` | `LREAL` | ExperimentLogger | 位置誤差 [rad] |

**処理**

1. `error = refValue - positionAct`
2. `PID -> Lead -> Notch -> Reso` の 4 段 biquad
3. `controlInput = u_fb + ffValue`

### 2.2 ExperimentSequencer

**責務**

* `refTable`, `ffTable`, `distTable` の 1 サンプル再生
* `repeatCount` による multi-trial 再生
* `seqState`, `seqError`, `playbackDone` の公開

**公開変数**

| 変数 | 型 | 意味 |
|---|---|---|
| `refTable`, `ffTable`, `distTable` | `ARRAY[0..99999] OF LREAL` | 入力テーブル |
| `tableLen` | `UDINT` | 有効長 |
| `tableLenClamped` | `UDINT` | 実際の再生長 |
| `repeatCount` | `UDINT` | trial 繰返し回数 |
| `trialIndex` | `UDINT` | 現在 trial |
| `idx` | `UDINT` | 現 trial 内インデックス |
| `refValue`, `ffValue`, `distValue` | `LREAL` | 現在出力 |
| `playbackDone` | `BOOL` | 全 trial 完了 |
| `seqError` | `BOOL` | `FAULT` 状態 |
| `seqState` | `E_SeqState` | `IDLE / PLAYING / COMPLETE / FAULT` |

**開始/完了条件**

* `experimentActive` 立ち上がりで再生開始
* `tableLen = 0` または `repeatCount = 0` は `FAULT`
* 最終 trial 完了で `playbackDone = TRUE`

### 2.3 DriverAdapter

**active 実装**

* `DriverAdapter_Obj1 (Module1)` の C++ TcCOM
* `Module1Inputs` / `Module1Outputs` を公開
* `MotorParams` / `LoadParams` を TcCOM object parameter として保持

**入力**

| 入力 | 型 | 説明 |
|---|---|---|
| `motorRaw`, `loadRaw` | struct | raw position / velocity / torque / status |
| `controlInput` | `LREAL` | ControllerCore 出力 [A] |
| `distValue` | `LREAL` | Sequencer 外乱 [A] |
| `motorControlWordIn` | `UINT` | ModeManager 生成 Motor ControlWord |
| `loadControlWordIn` | `UINT` | ModeManager 生成 Load ControlWord |
| `enableCurrentOutput` | `BOOL` | 電流ゲート |
| `playbackDone` | `BOOL` | same-task fast stop |
| `resetReq` | `BOOL` | オフセット再キャプチャ |

**出力**

| 出力 | 型 | 説明 |
|---|---|---|
| `motor.*`, `load.*` | struct | 工学単位変換済み信号 |
| `currentCmd` | `LREAL` | `clamp(controlInput + distValue)` 後の指令電流 [A] |
| `targetTorque` | `INT` | Drive 境界の指令トルク [‰ rated] |
| `motorControlWordOut`, `loadControlWordOut` | `UINT` | relay |
| `motorStatusWordOut`, `loadStatusWordOut` | `UINT` | relay |

**SIL 配線上の注意**

* checked-in `.tsproj` では SIL 時に `VirtualMotorCore.Outputs.motor/*` を Motor、`VirtualMotorCore.Outputs.load/*` を Load として接続する。
* `targetTorque` は `VirtualMotorCore.Inputs.motor.targetTorque` にのみ入り、Motor/Load ControlWord は個別 relay する。
* Motor/Load の力学連成は `VirtualMotorCore` 内部の 2 慣性モデルで表現する。

### 2.4 ModeManager

**公開 ADS 契約 (`GVL_MODE`)**

| シンボル | 型 | 用途 |
|---|---|---|
| `modeFlags` | `UINT` | `SERVO_ENABLE` / `EXPERIMENT_START_REQ` 投入 |
| `resetReq` | `BOOL` | reset 要求 |
| `resetAckCounter` | `UDINT` | reset 受理 ACK |
| `hostHeartbeatCounter` | `UDINT` | ホスト heartbeat |
| `watchdogTripCounter` | `UDINT` | watchdog 発生回数 |
| `experimentActive` | `BOOL` | 状態監視 |
| `modeState` | `E_ModeState` (`INT16`) | `IDLE / RESETTING / SERVO_READY / RUNNING / DONE` (0/10/20/30/40) |
| `loggerFileReleased` | `BOOL` | logger close 完了 |
| `loggerErrorCode` | `UDINT` | logger エラー |

**運用ルール**

* reset は `modeFlags` bit ではなく `resetReq/resetAckCounter` handshake を使う。
* `SERVO_READY -> RUNNING` 遷移には `driveReady` に加えて `loggerReadyIn` が必要。
* 任意停止は watchdog ではなく `modeFlags := 0` による explicit abort を正規経路とする。

### 2.5 ExperimentLogger

**責務**

* file pre-open: `Inputs.control.preArmReq`
* record append / close: `Inputs.control.loggingReq`
* same-task 停止短縮: `Inputs.control.playbackDone`

**主要入力**

| 入力 | 説明 |
|---|---|
| `Inputs.record.currentCmd` | DriverAdapter clamp 後の current-domain command [A] |
| `Inputs.record.refValue`, `Inputs.record.ffValue` | Sequencer 出力 |
| `Inputs.record.controlInput`, `Inputs.record.error` | ControllerCore 出力 |
| `Inputs.record.motor.position`, `Inputs.record.motor.velocity`, `Inputs.record.motor.currentAct` | DriverAdapter 変換済み Motor 信号 |
| `Inputs.record.load.position`, `Inputs.record.load.velocity` | DriverAdapter 変換済み Load 信号 |
| `Inputs.control.preArmReq`, `Inputs.control.loggingReq`, `Inputs.control.playbackDone` | logger 制御入力 |

**記録スキーマ**

`seq`, `tNs`, `motorPosition`, `motorVelocity`, `motorCurrentAct`, `loadPosition`, `loadVelocity`, `currentCmd`, `error`, `refValue`, `ffValue`, `controlInput`

### 2.6 VirtualMotorCore

* checked-in mapping では `VirtualMotorCore.Inputs/Outputs` の `motor` / `load` struct をそのまま使う
* `targetTorque` は `VirtualMotorCore.Inputs.motor.targetTorque` にのみ投入する
* `PlantParameter.*` は `CreateSymbol="true"` で symbol browse 可

---

## 3. タスクとポート

### 3.1 現行タスク

| Task | CycleTime | AmsPort | バインド対象 |
|---|---|---|---|
| `VirtualMotorTask` | `125,000 ns` | `351` | ControllerCore / DriverAdapter / VirtualMotorCore / ExperimentLogger / ExperimentSequencer |
| `PlcTask1` | `10,000,000 ns` | `852` | StateMachineControl |

### 3.2 現行 ADS アクセス面

| ポート | 主対象 | 備考 |
|---|---|---|
| `351` | C++ TcCOM 群 | ControllerCore / DriverAdapter / VirtualMotorCore / ExperimentLogger |
| `852` | ModeManager | 制御フラグ、reset handshake、状態監視 |
| `853` | ExperimentSequencer | テーブル書込みと replay 状態 |
| `851` | discovery 用の明示 probe のみ | checked-in `.tsproj` の active DriverAdapter 契約ではなく、正本 API からは参照しない |

---

## 4. MATLAB からのアクセス方針

| カテゴリ | 書込み/読取り先 | 備考 |
|---|---|---|
| テーブル | `GVL_SEQ.*` (853) | `refTable`, `ffTable`, `distTable`, `tableLen`, `repeatCount` |
| 状態制御 | `GVL_MODE.*` (852) | `modeFlags`, `resetReq`, `resetAckCounter`, `modeState` |
| Controller params | `ControllerCore_Obj1 (Module1).*` (351) | symbol write |
| VM params | `VirtualMotorCore_Obj1 (Module1).PlantParameter.*` (351) | symbol write |
| logger 監視 | `GVL_MODE.loggerFileReleased/loggerErrorCode` (852) | MATLAB は logger TcCOM を直接待機しない |
| logger 本体 | `.bin` file read | `read_logger_bin` で解析 |

> 現行 MATLAB 実装には DriverAdapter `MotorParams` / `LoadParams` を書く専用 helper は含まれない。必要なら別途追加する。

---

## 5. 重要な設計判断

| ID | 決定 |
|---|---|
| D1 | ControllerCore はスカラ I/O のみを持ち、テーブルを所有しない |
| D2 | ExperimentSequencer が `ref/ff/dist` replay と repeat 管理を担当する |
| D3 | DriverAdapter が相対位置化、外乱加算、current clamp、CW/SW relay を担当する |
| D4 | ModeManager only で状態制御し、reset は handshake、停止は explicit abort を正規とする |
| D5 | ExperimentLogger を唯一の正規ログ経路とする |
| D6 | DriverAdapter は C++ TcCOM の単一実装とする |

---

## 6. 実装正本

* 現行構成は 8 kHz TcCOM、ExperimentLogger、ADS 852/853 の PLC 契約を正本とする。
* DriverAdapter は C++ TcCOM の単一実装であり、PLC 版の互換実装は持たない。
