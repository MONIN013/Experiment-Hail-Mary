# Experiment Procedure

> **位置づけ:** 実験オペレーター向けの操作手順と確認項目  
> **対象読者:** 実験実行者、検証担当者  
> **更新条件:** 実験手順、前提条件、運用フロー、停止条件が変わったとき  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) / [TechnicalReference](../architecture/TechnicalReference.md)

本ドキュメントは実験オペレーター向けの **手順書** である。  
モジュール内部ロジック・GVL 変数定義・ADS シンボルの詳細は [TechnicalReference](../architecture/TechnicalReference.md) を参照。

---

## 1. モジュール構成概要

| モジュール | 実装 | Task | 役割 |
|---|---|---|---|
| **StateMachineControl** (ModeManager) | PLC ST | PlcTask1 (10 ms) | CiA 402 状態遷移 + フラグ管理 + 実験開始/停止制御 |
| **ExperimentSequencer** | PLC ST | VirtualMotorTask (125 us / 8 kHz) | テーブルリプレイ |
| **ControllerCore** | C++ TcCOM | VirtualMotorTask (125 us / 8 kHz) | 誤差計算 + 最大 10 段の汎用 SOS cascade + FF 付加 |
| **DriverAdapter** | C++ TcCOM | VirtualMotorTask (125 us / 8 kHz) | Raw/工学単位変換 + 相対位置化 + 外乱加算 + CW/SW 中継 + 電流ゲート |
| **VirtualMotorCore** | C++ TcCOM | VirtualMotorTask (125 us / 8 kHz) | 仮想モーター物理シミュレーション (CiA 402 内蔵) |
| **ExperimentLogger** | C++ TcCOM | VirtualMotorTask (125 us / 8 kHz) | バイナリファイルロギング (8kHz × 100s 対応、非同期 I/O) |

---

## 2. フラグ管理 — GVL_MODE

### 2.1 `modeFlags` ビットフィールド定義

`GVL_MODE.modeFlags` は `UINT` 型のビットフィールドで、ADS から書き込むことで各機能を制御する。
**Port 852** (`StateMachineControl`) でアクセス。
状態制御の経路は `GVL_MODE.modeFlags`（実験開始/停止）と `GVL_MODE.resetReq`（リセット要求）を使用する。

| ビット | 定数名 | 値 | 意味 |
|---|---|---|---|
| bit 0 | `MODEF_SERVO_ENABLE` | `16#0001` | サーボ有効化リクエスト |
| bit 1 | `MODEF_EXPERIMENT_START_REQ` | `16#0002` | 実験開始リクエスト |

### 2.2 状態監視変数

| 変数 | 型 | 方向 | 説明 |
|---|---|---|---|
| `GVL_MODE.modeFlags` | `UINT` | ADS → PLC | 上記ビットフィールドで機能リクエストを投入 |
| `GVL_MODE.resetReq` | `BOOL` | ADS → PLC | リセット要求（MATLAB は `TRUE` を書くだけ） |
| `GVL_MODE.resetAckCounter` | `UDINT` | PLC → ADS (読取) | reset 受理ごとに +1 |
| `GVL_MODE.hostHeartbeatCounter` | `UDINT` | ADS → PLC | ホスト生存監視カウンタ（100 ms 周期更新） |
| `GVL_MODE.watchdogTripCounter` | `UDINT` | PLC → ADS (読取) | heartbeat timeout 発生回数 |
| `GVL_MODE.experimentActive` | `BOOL` | PLC → ADS (読取) | ModeManager が管理する実験実行中フラグ |
| `GVL_MODE.modeState` | `E_ModeState` (`INT16`) | PLC → ADS (読取) | 現在の実験状態 |

### 2.3 `modeState` 状態値

| 値 | 定数名 | 意味 | 遷移条件 |
|---|---|---|---|
| `0` | `IDLE` | 待機中 | サーボ無効 or reset 完了 |
| `10` | `RESETTING` | リセット中 | 20 ms reset pulse |
| `20` | `SERVO_READY` | 実験待機 | サーボ有効 & ドライブ `OPERATION_ENABLED` & logger ready |
| `30` | `RUNNING` | 実験実行中 | `experimentActive = TRUE` |
| `40` | `DONE` | 実験完了 | reset まで保持 |

---

## 3. 実験シーケンス手順 (ADS 書き込み順)

### 3.1 全体フロー

```
 ①  リセット要求      resetReq := TRUE
                       → ModeManager が受理して resetOut パルスを生成
                       → ExperimentSequencer / ControllerCore / ExperimentLogger / DriverAdapter の内部状態がクリア
                       → ModeManager が resetReq を FALSE に戻し、resetAckCounter を +1

 ②  テーブル書込      GVL_SEQ.refTable[], ffTable[], distTable[], tableLen を ADS 書込 (Port 853)

 ③  パラメータ注入    ControllerCore の SOS 係数 / 段数 / applyRevision を書き、
                       processedRevision / appliedRevision / parameterErrorCode で確認

 ④  サーボ有効化      modeFlags := MODEF_SERVO_ENABLE (16#0001)
                       → ModeManager が CiA 402 状態遷移を開始
                       → OPERATION_ENABLED 到達で modeState = SERVO_READY (20)

 ⑤  実験開始          modeFlags := MODEF_SERVO_ENABLE OR MODEF_EXPERIMENT_START_REQ (16#0003)
                       → ModeManager が experimentActive = TRUE を設定
                       → ExperimentSequencer のテーブル再生が開始
                       → modeState = RUNNING (30)

 ⑥  実験完了待ち      modeState を ADS から読み取り、DONE (40) を待つ
                       → ExperimentSequencer が playbackDone = TRUE を発行
                       → ModeManager が experimentActive = FALSE にし DONE へ遷移

 ⑦  停止              modeFlags := 0
                       → サーボ無効化 → ドライブ状態が SWITCH_ON_DISABLED に戻る
```

### 3.2 ModeManager 内部動作概要

#### リセット処理

```
resetReq       := GVL_MODE.resetReq
resetEdge      := resetReq AND NOT resetReqPrev   ← 立ち上がりエッジ検出
modeState      := RESETTING                        ← reset edge scanで遷移
resetOut       := (modeState = RESETTING)          ← edge scan + 1 hold scanの計20 ms (AT %Q*)
                                                       → ExperimentSequencer.resetReq にリンク
                                                      → ControllerCore.Inputs.resetReq にリンク
                                                      → ExperimentLogger.Inputs.control.resetReq にリンク
                                                      → DriverAdapter.resetReq にリンク (D12)
IF resetEdge THEN
    GVL_MODE.experimentActive := FALSE;
    GVL_MODE.resetReq := FALSE;
    GVL_MODE.resetAckCounter := GVL_MODE.resetAckCounter + 1;
END_IF
```

#### リセット処理の既知制約

各モジュールのリセット対応状況を以下にまとめる。

| モジュール | resetReq 入力 | 検出方式 | リセット内容 | 既知制約 |
|---|---|---|---|---|
| **StateMachineControl** | `GVL_MODE.resetReq` | エッジ | `doneLatched` / `experimentActive` クリア, `resetAckCounter` +1, `resetOut` パルス生成 | heartbeat timeout 時に `modeFlags := 0` を自動実行 |
| **ExperimentSequencer** | `GVL_SEQ.resetReq` (`AT %I*`) | **エッジ** | `idx`/`refValue`/`ffValue`/`distValue`/`playbackDone` クリア, `ExperimentLogger` リセット | M14 解消済み。エッジ検出に統一 |
| **ControllerCore** | `Inputs.resetReq` | エッジ | 全 SOS 段の内部状態クリア | 相対位置化は DriverAdapter に移管済み (D12) |
| **ExperimentLogger** | `Inputs.control.resetReq` | エッジ | ファイルクローズ, `bufferCount`/`seq`/`recordsWritten` 等クリア | — |
| **VirtualMotorCore** | **なし** | — | — | 設計決定: 実機同等。`position`/`velocity` は実験間で carry-over する。DriverAdapter の `positionOffsetRad` で相対位置は補正される |
| **DriverAdapter** | `Inputs.resetReq` | エッジ | Motor/Load の位置オフセット再キャプチャ | 相対位置化を担当 (D12、M15 解消) |

> **注意:** `ExperimentRunner` は `wait_for_reset_idle` タイムアウト時に warning 続行せず **error で停止** する。
> `hostHeartbeatCounter` の更新が 500 ms 以上停止すると ModeManager watchdog が `modeFlags := 0` を実行する。
> MATLAB 実行中の任意停止は watchdog を待たず、`modeFlags := 0` を明示送信する explicit abort を正規経路とする。
> internal heartbeat と external helper は同時に有効化しない。学生入口は internal を無効化し、`cfg.ads_assembly` を使う external helper の起動・生存・停止を Runner が監視する。
> 通常の学生入口 / demo / Runner はVM parameterやlifecycleを扱わない。VM parameter変更はIDLE中に`run_configure_virtual_motor.m`を明示実行し、Test/E2Eの予測照合だけが`virtualMotor.restart_runtime`を使う。
> VM configure時にraw positionが`DINT`上下限へ到達している場合は`virtualMotor:settle:positionSaturated`で停止する。Scope非記録を確認してTest/E2E用lifecycle resetでhidden stateをゼロ化するまでparameterを書かない。

#### サーボ有効化 → CiA 402 状態遷移

```
servoEnableReq := (modeFlags AND MODEF_SERVO_ENABLE) <> 0
enableEffective := enable AND servoEnableReq

statusWord → F_DecodeDriveState → driveState に応じて controlWord を生成:
  FAULT              → CW_FAULT_RESET (16#0080)
  SWITCH_ON_DISABLED → CW_SHUTDOWN (16#0006)
  READY_TO_SWITCH_ON → CW_SWITCH_ON (16#0007)
  SWITCHED_ON        → CW_ENABLE_OP (16#000F)
  OPERATION_ENABLED  → CW_ENABLE_OP 維持
```

#### 実験開始/停止制御

```
条件: experimentStartReq AND driveReady AND (NOT doneLatched)
  → experimentActive := TRUE

停止条件:
  (a) seqPlaybackDone = TRUE     ← テーブル再生完了
  (b) enableEffective = FALSE    ← サーボ無効化
  (c) MATLAB explicit abort      ← `modeFlags := 0`

完了ラッチ:
  playbackDone → doneLatched := TRUE
  experimentStartReq = FALSE or resetEdge → doneLatched リセット
```

#### 電流ゲート

```
enableCurrentOut は MAIN の CASE modeState で状態ごとに制御:
  IDLE / RESETTING:   enableCurrentOut := FALSE
  SERVO_READY:        enableCurrentOut := TRUE   ← CiA 402 遷移中
  RUNNING:            enableCurrentOut := TRUE
  DONE:               enableCurrentOut := FALSE

  → DriverAdapter: (enableCurrentOutput = FALSE) OR playbackDone = TRUE
                   時に targetTorque := 0 (安全停止)
```

> ドライブ自体が OPERATION_ENABLED 以外ではトルクを無視するため、SERVO_READY 状態で
> `enableCurrentOut = TRUE` であっても機能上の影響はない。

#### 停止経路の使い分け

- **自然完了:** `seqPlaybackDone` により `DONE` へ遷移し、次の reset まで保持
- **明示 abort:** MATLAB が `GVL_MODE.modeFlags := 0` を書き、`IDLE` と logger close を待つ
- **異常停止:** MATLAB 側 heartbeat が止まったとき watchdog が `modeFlags := 0` を自動実行

---

## 4. 実験ライフサイクル図

```
┌───────────────────────────────────────────────────────────────────────┐
│           ADS 操作                TwinCAT モジュール内部動作           │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ① modeFlags=0, tableLen=0         稼働停止とテーブル非公開を先に保証   │
│                                                                       │
│  ② resetReq = TRUE                ModeManager: resetEdge → resetOut   │
│    (RESET REQUEST)                ExperimentSequencer: idx=0, ログクリア│
│                                   ControllerCore: 全 SOS 状態クリア   │
│                                   DriverAdapter: positionOffsetRad     │
│                                     := positionRad (相対位置リセット) │
│                                                                       │
│  ③ TcCOM パラメータ ADS 書込     ControllerCore: SOS 係数・段数を     │
│                                   applyRevision で一括反映          │
│                                   VirtualMotorCore: PlantParameter.motor/load/coupling 更新 │
│                                                                       │
│  ④ refTable[], ffTable[],         GVL_SEQ に全テーブルデータ格納      │
│     distTable[], repeatCount       完了後に tableLen を一度だけ公開    │
│                                                                       │
│  ⑤ heartbeat 開始                internal/external の一方だけ開始     │
│                                                                       │
│  ⑥ modeFlags = 0x0001            ModeManager: サーボ有効化            │
│    (SERVO_ENABLE)                 CiA 402 → OPERATION_ENABLED         │
│                                   modeState = SERVO_READY (20)        │
│                                                                       │
│  ⑦ modeFlags = 0x0003            ModeManager: experimentActive=TRUE  │
│    (SERVO + EXPERIMENT_START)     ExperimentSequencer: 再生開始        │
│                                   modeState = RUNNING (30)             │
│                                                                       │
│     毎スキャン (125 us / 8 kHz):                                       │
│       ExperimentSequencer → ref/ff/dist → ControllerCore              │
│       ControllerCore → controlInput → DriverAdapter                   │
│       DriverAdapter → targetTorque (Drive 境界, ‰ rated, INT) → selected endpoint │
│       selected endpoint → positionActualValue (pulses) → DriverAdapter │
│       DriverAdapter: raw→rad変換 + 相対位置化 → load.positionRel      │
│       DriverAdapter.load.positionRel → ControllerCore (FB)            │
│                                                                       │
│  ⑧ (自動)                        idx >= tableLen                      │
│                                   → playbackDone = TRUE               │
│                                   → experimentActive = FALSE          │
│                                   → modeState = DONE (40)              │
│                                                                       │
│  ※ ⑧の playbackDone → experimentActive は                            │
│     クロスタスク(1ms→10ms→1ms)のため最大~11ms遅延。                   │
│     DriverAdapter は playbackDone を同一タスク内で直接受け、          │
│     targetTorque を即時 0 にクランプする。                            │
│     ただし ExperimentLogger は playbackDone を同一タスク内で           │
│     直接受け、レコード追記を即時停止する。                             │
│     そのため 8kHz運用時の余剰ゼロ記録は H6 fast-path で抑止される。     │
│                                                                       │
│  ⑨ modeFlags = 0x0000            ModeManager: サーボ無効化            │
│                                   → SWITCH_ON_DISABLED                │
│                                   modeState = IDLE (0)                 │
│     logger release 後              同じ logger bin を一度だけ読出し    │
└───────────────────────────────────────────────────────────────────────┘
```

---

## 5. ADS アクセス早見表

| 操作 | Port | シンボル | データ型 | R/W |
|------|------|----------|----------|-----|
| **フラグ操作** | 852 | `GVL_MODE.modeFlags` | `UINT` | W |
| **リセット要求** | 852 | `GVL_MODE.resetReq` | `BOOL` | W |
| **リセットACK** | 852 | `GVL_MODE.resetAckCounter` | `UDINT` | R |
| **状態監視** | 852 | `GVL_MODE.modeState` | `INT16` | R |
| **テーブル書込** | 853 | `GVL_SEQ.refTable` / `ffTable` / `distTable` | `LREAL[]` | W |
| **テーブル長** | 853 | `GVL_SEQ.tableLen` | `UDINT` | W |
| **SOS 係数** | 351 | `ControllerCore_Obj1 (Module1).SosCoefficients` | `LREAL[50]` | W |
| **SOS 段数** | 351 | `ControllerCore_Obj1 (Module1).SosSectionCount` | `UDINT` | W |
| **SOS 反映** | 351 | `ControllerCore_Obj1 (Module1).SosApplyRevision` | `UDINT` | W（最後） |
| **SOS 反映確認** | 351 | `ControllerCore_Obj1 (Module1).Outputs.appliedRevision` | `UDINT` | R |
| **SOS 処理確認** | 351 | `ControllerCore_Obj1 (Module1).Outputs.processedRevision` | `UDINT` | R |
| **SOS エラー** | 351 | `ControllerCore_Obj1 (Module1).Outputs.parameterErrorCode` | `UDINT` | R |
| **VM パラメータ（専用tool）** | 351 | `VirtualMotorCore_Obj1 (Module1).PlantParameter.*` | `LREAL/UDINT/ULINT` | W/R |
| **ログ pre-arm** | 852 | `MAIN.preArmOut` → `Inputs.control.preArmReq` | `BOOL` | Auto |
| **ログ制御** | 852 | `MAIN.experimentActiveOut` → `Inputs.control.loggingReq` | `BOOL` | Auto |
| **logger status** | 351 | `ExperimentLogger_Obj1 (Module1).Outputs.status.*` | `UDINT/BOOL` | R |

> 全シンボルの完全な一覧は [TechnicalReference](../architecture/TechnicalReference.md) §8 を参照。
> `modeFlags` の正規書込み先は `GVL_MODE.modeFlags` のみであり、reset は `resetReq/resetAckCounter` handshake を使う。
> Controller parameter 更新は `processedRevision` が送信 revision と一致した後、`appliedRevision` が同じ revision で `parameterErrorCode = 0` となるまで成功扱いしない。非 0 の場合は active 設定が維持されるため、実験開始前に停止する。
> ログ本体は ADS では読まず、`GVL_MODE.loggerFileReleased=TRUE` 確認後に `.bin` をファイル読み出しする。

---

## 6. ExperimentLogger 操作手順

```
① filePath 設定 (省略時はデフォルト)
     ADS Write: LogControl.filePath = "C:\ExperimentData\run_001.bin"

② pre-arm
     ModeManager が `SERVO_READY` に入ると `preArmOut` を TRUE にし、
     `Inputs.control.preArmReq` 経由で file open を先行完了させる

③ ロギング開始
     ModeManager が `experimentActiveOut` を TRUE にすると
     既に pre-open 済みの logger が `Inputs.control.loggingReq` で記録開始する

④ ステータス監視 (任意)
     ADS Read: status.recordsWritten / fileSizeKb / errorCode

⑤ ロギング停止
     `playbackDone` でレコード追記を即時停止し、
     その後 `experimentActiveOut` FALSE で flush + close

⑥ ファイル読み出し (実験後)
     ターゲット PC からバイナリファイルを取得
     MATLAB で読み込み:
       fid = fopen('run_001.bin', 'rb');
       raw = fread(fid, [12, Inf], 'double');
       fclose(fid);
       % 先頭 8 bytes は seq(uint32) + pad(uint32) → 別途パース要
```

> LogRecord フォーマット詳細は [TechnicalReference](../architecture/TechnicalReference.md) §6.4 を参照。

---

## 7. MATLAB 学生実験の実行手順

### 7.1 実行前確認

MATLAB の Current Folder はリポジトリ直下にする。初回または環境再設定時だけ setup を実行する。full preflight は TwinCAT activation、runtime/config変更後、または実験日の開始時に一度実行し、同一状態の trial ごとには繰り返さない。

TwinCAT側はVM用`ExperimentHailMary.tsproj`または実機用`ExperimentHailMary.RealMotor.tsproj`を選択してActivate/Restartする。後者は実PDO未取込みの非deployable scaffoldであり、現時点では実機運転に使用しない。VM parameterを変更する場合だけ、共通preflightより前に`run('matlab/tools/run_configure_virtual_motor.m')`を実行する。

```matlab
cd('<repository-root>')
run('matlab/setup_matlab_environment.m')
run('matlab/tools/run_exp01_exp04_preflight.m')
```

`run_exp01_exp04_preflight.m` はMapping種別に依存せず、MATLAB path、必須 toolbox 関数、ADS 接続、共通active contract symbol、`plant.mat`、tracked 8 kHz 軌道を確認する。VM symbolの検査・parameter writeや実験開始は行わない。

### 7.2 標準実行順

```matlab
run('matlab/experiment/exp01_SysId.m')
run('matlab/experiment/exp02_FeedBack.m')
run('matlab/experiment/exp03_FeedForward.m')
run('matlab/experiment/exp04_ILC.m')
```

| 入口 | 実体 | 主な出力 | 既定の確認内容 |
|---|---|---|---|
| `exp01_SysId.m` | 同左 | `data/chirp_result.mat`, `data/plant.mat` | logarithmic chirp SI と manual `Jn/Dn/Ndelay` fit |
| `exp02_FeedBack.m` | 同左 | `data/feedback_result.mat` | `designpid`、Nyquist、`Smax=2` 感度確認、tracking |
| `exp03_FeedForward.m` | 同左 | `data/feedforward_result.mat` | identified `Jn/Dn` 既定の FF と tracking |
| `exp04_ILC.m` | 同左 | `data/exp04_runs/<timestamp>/ilc_result.mat`, `trialXX.mat`, `trialXX_logger.bin` | `srinv` / `filtfilt_clean` による ILC trial 遷移 |

`experiment.scenario.exp02` / `exp03` / `exp04` は学生入口ではなく、Live ScriptとTestから共有する副作用なしbuilderである。exp02〜exp04 は `matlab/experiment/data/plant.mat` を前提にするため、必ず exp01 の SI と manual fit を先に実行する。

### 7.3 exp01: chirp SI と plant.mat

exp01 は open-loop logarithmic chirp を FF 入力として注入する。既定値は `Tend=100`、`Tcycle=10`、`f0=0.5 Hz`、`f1=4000 Hz`、`A=0.25 A`、`trans=2`、`Ndelay=4 samples` である。各cycleは平均0へ補正してから最大絶対値を0.25 Aへ正規化し、DC driftを持ち込まない。

過渡 2 周期を除去し、loggerの `ff_value` から実測速度への `tfestimate` / `mscohere` を計算する。位置 FRD は連続近似を使わず、semi-implicit Eulerの恒等式 `theta(k)=theta(k-1)+Ts*omega(k)` に対応する厳密な離散積分器 `Ts*z/(z-1)` で構成する。初期値は VirtualMotor preset の電流入力換算から `Jn=7.1e-5`、`Dn=5.325e-4`、`Ndelay=4` とし、学生は bode overlay が測定 FRF に合うように手動調整する。

`plant.mat` の変数集合は `Pd` / `Pd_motor` / `Pd_load` / `Pd_vel_load` / `Pd_vel_motor` / `Pdn` / `Jn` / `Dn` / `Ndelay` / `Ts` である。`Pd` はload側position FRD、`Pdn`は`c2d(1/(Jn*s+Dn)/s,Ts,"zoh")/z^Ndelay`である。Mapping種別は保存せず、Mapping変更後もexp01から標準順序で再同定する。

### 7.4 exp02〜exp04: 標準軌道と制御設計

`matlab/resources/trajectory_8khz.mat` は標準軌道の tracked resource で、SHA-256 は `11C4E587D2E413707C09CA0875779269E1F6F7ECFD1CEC1C50030C18A62B5CB0` である。`load_trajectory` が `ref1_struct` の field・件数・有限性・8 kHz 時間刻みを検証し、deg 系の 720 deg / 1 s 往復軌道を rad 系に変換する。`experiment.waveform.point_to_point_trajectory` は任意軌道生成ツールとして残るが、この標準手順の既定軌道ではない。

exp02 は `designpid(Dn/Jn,0,1/Jn,omega)` を `omega=15 rad/s` で設計し、`c2d(...,"tustin")` で離散化する。実験前に nominal / FRD の Nyquist と `Smax=2` の感度上限を数値確認し、`feedback_result.mat` に `t,r,y,e,u,Kd` を保存する。

exp03 は exp02 と同じ FB 設計に、`f=Kfa*a+Kfv*v+Kfc*sign(v)` の FF を加える。`Kfa=[]` / `Kfv=[]` / `Kfc=[]` の既定では、`plant.mat` の `Jn` / `Dn` を使って `Kfa=Jn`、`Kfv=Dn`、`Kfc=0` とし、`Ndelay` 分の先読み補償を行う。保存変数は `t,r,y,e,u,f,Kd` である。

exp04 は Temp 参照実装と同じ `Linv=feedback(Pdn,Kd)`、`J=feedback(Pd,Kd)` と2次 low-pass Qを使い、`|Q|^2|1-alpha*J/Linv| < 1` を実験前に数値確認する。学習更新は `f_{j+1}=filtfilt_clean(Qnum,Qden,f_j+alpha*srinv(Linv,e_j,Npad),Npad)` で、200 sample transient splice を行う。既定は `Ntrial=10`、`alpha=0.6`、`q_cutoff_hz=120`、`maxInput=1.6 A` である。720 deg往復の後ろへ6秒のゼロreference整定tailを付け、学習は元の往復軌道だけへ適用し、tailのFFは全trialで厳密に0へ固定する。manifest生成時に全trialの終端速度量子値0・motor/load位置差2 count以内を確認する。各trialの実測直後、学習更新前に位置、誤差、logger上で整列したFF/FB入力の同一dashboardを更新する。次trialのFFが1.6 Aを超える場合、または実測error normが増加した場合は、完了済み数値history、`trialSummary`、停止理由を `ilc_result.mat` へcheckpointしてから例外化する。trial別画像は保存しない。
VirtualMotor予測は `testoracle.simulate_ilc_campaign` / `predict_ilc_campaign` に集約し、Test専用とする。実験中のILCは実測errorから次FFを計算し、予測・VM再起動・parameter設定を行わない。

### 7.5 VirtualMotor での目安

VirtualMotor は Panasonic MHMF011L1A2 相当の小慣性 preset を既定にする。Motor / Load inertia は `7.1e-6 kg m^2`、rated torque は `0.32 N m`、DriverAdapter の rated current は `1.6 A`、encoder resolution は 23 bit (`8388608`) である。coupling はねじり自然周波数 `200 Hz`、減衰比 `0.05`（減衰付き約 `199.749 Hz`）に設定する。preset 更新後は exp01〜exp04 を同じ順序で再実行して `plant.mat` の fit、720 deg 軌道、FF 上限、Q帯域、heartbeat / logger 状態を確認する。

VM tools の既定は position demo が20 rad/s filtered PIDによる `0.75 rad` step、SI demo がcycle meanを除去してからDriverAdapterの `1.6 mA/count` へ量子化し、1周期のcount総和を厳密0へ補正した `A=0.25 A` chirp、prediction E2E がdriver量子の30 countに一致する `±0.048 A` 入力である。SI demo は測定 FRF と coherence を出力する。Testでは過渡2周期後の同位相cycle間位置差をsecular driftとして判定し、終端位置・終端速度そのものをdriftとはみなさない。nominal予測との照合はTestに限定する。長時間runのheartbeatは学生入口と同じ外部helperを使う。

### 7.6 rich Live Script結果更新のDesktop fallback

R2025bのheadless `matlab.internal.liveeditor.executeAndSave` が不安定な場合だけ、次のfallbackを使う。

1. 原本backupと更新target backupが存在し、実行前file SHAとoutput JSON digestが記録済みであることを確認する。
2. `exp01_SysId.m`〜`exp04_ILC.m`をそれぞれ別のDesktop MATLAB session/processで1本ずつ開き、`Run All` → `Save`する。自動実行済みentryを再実行してVM実験を二重化しない。
3. 各保存直後に`experiment.liveeditor.inspect` / `assert_valid`を実行し、output参照とappendix定義の全単射、ID/JSON一意性、PNG magic、metadata/sectionを検証する。画像数18は4本を集計して確認する。
4. fresh `completedAtUtc`、実行前後のfile SHA、output JSON digestを保存証拠にする。mtimeだけでは合格にしない。
5. headless失敗後も自動campaignが続行したことにはしない。当該entryを未完了として停止し、Desktop実行、構造検証、実測照合後にledgerへ完了結果を反映する。

