# 実験手順書 — ExperimentHailMary

> **作成日:** 2026-02-26  
> **対象フェーズ:** Phase 1–3 (1 ms SIL)  
> **参照:** [ArchitectureSpec.md](ArchitectureSpec.md) / [TechnicalReference.md](TechnicalReference.md) / [OpenIssues.md](OpenIssues.md)

本ドキュメントは実験オペレーター向けの **手順書** である。  
モジュール内部ロジック・GVL 変数定義・ADS シンボルの詳細は [TechnicalReference.md](TechnicalReference.md) を参照。

---

## 1. モジュール構成概要

| モジュール | 実装 | Task | 役割 |
|---|---|---|---|
| **StateMachineControl** (ModeManager) | PLC ST | PlcTask1 (10 ms) | CiA 402 状態遷移 + フラグ管理 + 実験開始/停止制御 |
| **ExperimentSequencer** | PLC ST | VirtualMotorTask (1 ms) | テーブルリプレイ + リングバッファログ記録 |
| **ControllerCore** | C++ TcCOM | VirtualMotorTask (1 ms) | 誤差計算 + FB Chain + FF 付加 |
| **DriverAdapter** | PLC ST | VirtualMotorTask (1 ms) | 外乱加算 + CW/SW 中継 + トルクゲート |
| **VirtualMotorCore** | C++ TcCOM | VirtualMotorTask (1 ms) | 仮想モーター物理シミュレーション (CiA 402 内蔵) |
| **ExperimentLogger** | C++ TcCOM | VirtualMotorTask (1 ms) | バイナリファイルロギング (8kHz × 100s 対応、非同期 I/O) |

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
| `GVL_MODE.experimentState` | `UINT` | PLC → ADS (読取) | 現在の実験状態 |

### 2.3 `experimentState` 状態値

| 値 | 定数名 | 意味 | 遷移条件 |
|---|---|---|---|
| `0` | `STATE_IDLE` | 待機中 | サーボ無効 or ドライブ未 Ready |
| `1` | `STATE_READY` | 実験待機 | サーボ有効 & ドライブ `OPERATION_ENABLED` & 実験未開始 |
| `2` | `STATE_RUNNING` | 実験実行中 | `experimentActive = TRUE` |
| `3` | `STATE_DONE` | 実験完了 | 再生完了ラッチ済み |

---

## 3. 実験シーケンス手順 (ADS 書き込み順)

### 3.1 全体フロー

```
 ①  リセット要求      resetReq := TRUE
                       → ModeManager が受理して resetOut パルスを生成
                       → ExperimentSequencer / ControllerCore / ExperimentLogger の内部状態がクリア
                       → ModeManager が resetReq を FALSE に戻し、resetAckCounter を +1

 ②  テーブル書込      GVL_SEQ.refTable[], ffTable[], distTable[], tableLen を ADS 書込 (Port 853)

 ③  パラメータ注入    ControllerCore / VirtualMotorCore の TcCOM パラメータを ADS 書込 (Port 351)

 ④  サーボ有効化      modeFlags := MODEF_SERVO_ENABLE (16#0001)
                       → ModeManager が CiA 402 状態遷移を開始
                       → OPERATION_ENABLED 到達で experimentState = STATE_READY

 ⑤  実験開始          modeFlags := MODEF_SERVO_ENABLE OR MODEF_EXPERIMENT_START_REQ (16#0003)
                       → ModeManager が experimentActive = TRUE を設定
                       → ExperimentSequencer のテーブル再生が開始
                       → experimentState = STATE_RUNNING

 ⑥  実験完了待ち      experimentState を ADS から読み取り、STATE_DONE (3) を待つ
                       → ExperimentSequencer が playbackDone = TRUE を発行
                       → ModeManager が experimentActive = FALSE にし STATE_DONE へ遷移

 ⑦  停止              modeFlags := 0
                       → サーボ無効化 → ドライブ状態が SWITCH_ON_DISABLED に戻る
```

### 3.2 ModeManager 内部動作概要

#### リセット処理

```
resetReq       := GVL_MODE.resetReq
resetEdge      := resetReq AND NOT resetReqPrev   ← 立ち上がりエッジ検出
resetOut       := resetEdge                        ← ワンショットパルス出力 (AT %Q*)
                                                      → ExperimentSequencer.resetReq にリンク
                                                      → ControllerCore.Inputs.resetReq にリンク
                                                      → ExperimentLogger.Inputs.resetReq にリンク
IF resetEdge THEN
    GVL_MODE.experimentActive := FALSE;
    GVL_MODE.resetReq := FALSE;
    GVL_MODE.resetAckCounter := GVL_MODE.resetAckCounter + 1;
END_IF
```

#### リセット処理の既知制約

各モジュールのリセット対応状況を以下にまとめる。詳細は [OpenIssues.md](OpenIssues.md) を参照。

| モジュール | resetReq 入力 | 検出方式 | リセット内容 | 既知制約 |
|---|---|---|---|---|
| **StateMachineControl** | `GVL_MODE.resetReq` | エッジ | `doneLatched` / `experimentActive` クリア, `resetAckCounter` +1, `resetOut` パルス生成 | heartbeat timeout 時に `modeFlags := 0` を自動実行 |
| **ExperimentSequencer** | `GVL_SEQ.resetReq` (`AT %I*`) | **レベル** | `idx`/`refValue`/`ffValue`/`distValue`/`playbackDone` クリア, `GVL_SEQ_LOG` リセット | エッジ検出不統一 (M14) |
| **ControllerCore** | `Inputs.resetReq` | エッジ | biquad 内部状態クリア, `positionOffset := positionAct` | — |
| **ExperimentLogger** | `Inputs.resetReq` | エッジ | ファイルクローズ, `bufferCount`/`seq`/`recordsWritten` 等クリア | — |
| **VirtualMotorCore** | **なし** | — | — | 設計決定: 実機同等。`position`/`velocity` は実験間で carry-over する。ControllerCore の `positionOffset` で相対位置は補正される |
| **DriverAdapter** | **なし** | — | — | 組み合わせ回路のため影響なし。Phase 4 拡張時に要検討 (M15) |

> **注意:** `send_position_command` / `VirtualMotorService` は `wait_for_reset_idle` タイムアウト時に warning 続行せず **error で停止** する。
> `hostHeartbeatCounter` の更新が 500 ms 以上停止すると ModeManager watchdog が `modeFlags := 0` を実行する。

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

完了ラッチ:
  playbackDone → doneLatched := TRUE
  experimentStartReq = FALSE or resetEdge → doneLatched リセット
```

#### トルクゲート

```
enableTorqueOut := enableEffective AND driveReady
  → DriverAdapter: enableTorqueOutput = FALSE 時に target_torque := 0.0
```

---

## 4. 実験ライフサイクル図

```
┌───────────────────────────────────────────────────────────────────────┐
│           ADS 操作                TwinCAT モジュール内部動作           │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ① resetReq = TRUE                ModeManager: resetEdge → resetOut   │
│    (RESET REQUEST)                ExperimentSequencer: idx=0, ログクリア│
│                                   ControllerCore: biquad 状態クリア    │
│                                                                       │
│  ② refTable[], ffTable[],         GVL_SEQ にテーブルデータ格納        │
│     distTable[], tableLen                                             │
│     を ADS 書込                                                       │
│                                                                       │
│  ③ TcCOM パラメータ ADS 書込     ControllerCore: biquad 係数更新      │
│                                   VirtualMotorCore: mass/damping/torqueConstant 等更新 │
│                                                                       │
│  ④ modeFlags = 0x0001            ModeManager: サーボ有効化            │
│    (SERVO_ENABLE)                 CiA 402 → OPERATION_ENABLED         │
│                                   experimentState = STATE_READY (1)   │
│                                                                       │
│  ⑤ modeFlags = 0x0003            ModeManager: experimentActive=TRUE  │
│    (SERVO + EXPERIMENT_START)     ExperimentSequencer: 再生開始        │
│                                   experimentState = STATE_RUNNING (2) │
│                                                                       │
│     毎スキャン (1 ms):                                                 │
│       ExperimentSequencer → ref/ff/dist → ControllerCore              │
│       ControllerCore → controlInput → DriverAdapter                   │
│       DriverAdapter → targetTorque → VirtualMotorCore                 │
│       VirtualMotorCore → positionOut → ControllerCore (FB)            │
│                                                                       │
│  ⑥ (自動)                        idx >= tableLen                      │
│                                   → playbackDone = TRUE               │
│                                   → experimentActive = FALSE          │
│                                   → experimentState = STATE_DONE (3)  │
│                                                                       │
│  ⑦ modeFlags = 0x0000            ModeManager: サーボ無効化            │
│                                   → SWITCH_ON_DISABLED                │
│                                   experimentState = STATE_IDLE (0)    │
└───────────────────────────────────────────────────────────────────────┘
```

---

## 5. ADS アクセス早見表

| 操作 | Port | シンボル | データ型 | R/W |
|------|------|----------|----------|-----|
| **フラグ操作** | 852 | `GVL_MODE.modeFlags` | `UINT` | W |
| **リセット要求** | 852 | `GVL_MODE.resetReq` | `BOOL` | W |
| **リセットACK** | 852 | `GVL_MODE.resetAckCounter` | `UDINT` | R |
| **状態監視** | 852 | `GVL_MODE.experimentState` | `UINT` | R |
| **テーブル書込** | 853 | `GVL_SEQ.refTable` / `ffTable` / `distTable` | `LREAL[]` | W |
| **テーブル長** | 853 | `GVL_SEQ.tableLen` | `UDINT` | W |
| **フィルタ係数** | 351 | `ControllerCore_Obj1 (Module1).*Params.*` | `LREAL` | W |
| **VM パラメータ** | 351 | `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.*` | `LREAL` | W |
| **ログ制御** | 351 | `ExperimentLogger_Obj1 (Module1).LogControl.*` | — | W |
| **ログ読出し** | 853 | `GVL_SEQ_LOG.wrIdx` / `rdIdx` / `log*` | — | R/W |

> 全シンボルの完全な一覧は [TechnicalReference.md](TechnicalReference.md) §8 を参照。
> `send_position_command` の `mode_flags_symbol` は `GVL_MODE.modeFlags` のみサポートされる。

---

## 6. ExperimentLogger 操作手順

```
① filePath 設定 (省略時はデフォルト)
     ADS Write: LogControl.filePath = "C:\ExperimentData\run_001.bin"

② ロギング開始
     ADS Write: LogControl.logging = TRUE  (互換手動制御 / 通常不要)

③ ステータス監視 (任意)
     ADS Read: LogStatus.recordsWritten / fileSizeKb / errorCode

④ ロギング停止
     ADS Write: LogControl.logging = FALSE (互換手動制御 / 通常不要)

⑤ ファイル読み出し (実験後)
     ターゲット PC からバイナリファイルを取得
     MATLAB で読み込み:
       fid = fopen('run_001.bin', 'rb');
       raw = fread(fid, [12, Inf], 'double');
       fclose(fid);
       % 先頭 8 bytes は seq(uint32) + pad(uint32) → 別途パース要
```

> LogRecord フォーマット詳細は [TechnicalReference.md](TechnicalReference.md) §6.4 を参照。
