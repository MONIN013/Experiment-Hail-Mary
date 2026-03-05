# 技術リファレンス — モジュール内部動作・ADS シンボル

> **作成日:** 2026-02-26  
> **対象フェーズ:** Phase 1–3 (1 ms SIL)  
> **参照:** [ArchitectureSpec.md](ArchitectureSpec.md) / [ExperimentProcedure.md](ExperimentProcedure.md) / [OpenIssues.md](OpenIssues.md)

本ドキュメントは TwinCAT モジュールの **内部ロジック詳細・GVL 変数一覧・ADS シンボルリファレンス・tsproj Mapping 精査結果** をまとめた実装者向け技術参照である。  
実験手順については [ExperimentProcedure.md](ExperimentProcedure.md) を参照。

---

## 1. ExperimentSequencer — テーブル再生とフラグ詳細

### 1.1 GVL_SEQ 変数一覧

| 変数 | 型 | リンク | 方向 | 説明 |
|---|---|---|---|---|
| `refTable` | `LREAL[0..99999]` | — | ADS→PLC | 位置指令テーブル [rad] |
| `ffTable` | `LREAL[0..99999]` | — | ADS→PLC | FF テーブル [A] |
| `distTable` | `LREAL[0..99999]` | — | ADS→PLC | 外乱テーブル [A] |
| `tableLen` | `UDINT` | — | ADS→PLC | テーブル有効長 |
| `tableLenClamped` | `UDINT` | — | PLC内部 | min(tableLen, N_*_MAX) にクランプ済み |
| `idx` | `UDINT` | — | PLC内部 (ADS読取可) | 現在の再生インデックス |
| `refValue` | `LREAL` | `AT %Q*` | PLC→TcCOM | 現在のスカラ出力 → ControllerCore.refValue |
| `ffValue` | `LREAL` | `AT %Q*` | PLC→TcCOM | 現在のスカラ出力 → ControllerCore.ffValue |
| `distValue` | `LREAL` | `AT %Q*` | PLC→TcCOM | 現在のスカラ出力 → DriverAdapter.distValue |
| `resetReq` | `BOOL` | `AT %I*` | ModeManager→PLC | リセット要求 (ワンショット) |
| `experimentActive` | `BOOL` | `AT %I*` | ModeManager→PLC | 実験実行中フラグ |
| `playbackDone` | `BOOL` | `AT %Q*` | PLC→ModeManager | 再生完了フラグ |
| `modeFlags` | `UINT` | `AT %Q*` | PLC→ModeManager | モード制御フラグ（ModeManager から I/O リンクで受信） |

### 1.2 再生ロジック (PRG_ExperimentSequencer)

#### リセット処理 (`resetReq` 立ち上がりエッジ時)

```
resetEdge := GVL_SEQ.resetReq AND NOT resetReqPrev
IF resetEdge THEN
    idx          := 0
    refValue     := 0.0
    ffValue      := 0.0
    distValue    := 0.0
    playbackDone := FALSE
    playbackRunning := FALSE (内部)
    rearmRequired   := FALSE (内部)

    GVL_SEQ_LOG:
      seq   := 0
      tNs   := 0
      wrIdx := 0
      rdIdx := 0
      overflow := FALSE
END_IF
resetReqPrev := GVL_SEQ.resetReq
```

> リセットはテーブル内容には影響しない。インデックスとフラグのみクリアされる。
> M14 解消により、レベルトリガからエッジ検出に変更済み。

#### 開始エッジ検出

```
startEdge := experimentActive AND NOT cmdActivePrev
```

`experimentActive` の立ち上がりエッジで:
- `idx := 0`
- `playbackDone := FALSE`
- `playbackRunning := TRUE` (内部フラグ)

#### 毎スキャン再生 (playbackRunning = TRUE)

```
IF idx < tableLenClamped THEN
    refValue  := refTable[idx]
    ffValue   := ffTable[idx]
    distValue := distTable[idx]
    idx       := idx + 1
    sampleEmittedThisScan := TRUE   ← ログトリガー
ELSE
    playbackRunning := FALSE
    playbackDone    := TRUE         ← 完了通知
    rearmRequired   := TRUE
    refValue / ffValue / distValue は最終テーブル値を保持
END_IF
```

#### リアーム (再実験準備)

`experimentActive = FALSE` かつ `rearmRequired = TRUE` の時:
- `rearmRequired := FALSE`
- `playbackDone := FALSE`

> これにより次回の `experimentActive` 立ち上がりエッジで再度再生可能になる。

---

## 2. ControllerCore — 信号処理とリセット

### 2.1 Data Area (TcCOM I/O)

#### 入力 (InputDst)

| ポート | 型 | ソース | 説明 |
|---|---|---|---|
| `refValue` | `LREAL` | ExperimentSequencer `GVL_SEQ.refValue` | 位置指令 [rad] |
| `ffValue` | `LREAL` | ExperimentSequencer `GVL_SEQ.ffValue` | FF 信号 [A] |
| `positionAct` | `LREAL` | DriverAdapter `positionRel` | Load 側相対位置 [rad]（Adapter で raw→rad 変換+相対位置化済み）|
| `resetReq` | `BOOL` | ModeManager `resetOut` | リセット要求 |

#### 出力 (OutputSrc)

| ポート | 型 | 宛先 | 説明 |
|---|---|---|---|
| `controlInput` | `LREAL` | DriverAdapter `GVL_DRV.controlInput` + ログ (`GVL_SEQ_LOG.controlInputTap`) | 制御出力 [A] |
| `error` | `LREAL` | (ログ用) | 位置誤差 $e = \text{refValue} - \text{positionAct}$ |

### 2.2 CycleUpdate 処理 (毎スキャン 1 ms)

```
1. リセットエッジ検出:
     resetEdge := (Inputs.resetReq != false) AND NOT prevResetReq
     → ResetRuntimeState(): PID/Lead/Notch/Reso の biquad 内部状態 (s1, s2) を全てゼロクリア

2. 誤差計算:
     error := refValue - positionAct

3. FB Chain (StepController):
     y := error
     IF enablePid  → y := ApplyBiquad(y, pidB0..pidA2,   PidS1, PidS2)
     IF enableLead → y := ApplyBiquad(y, leadB0..leadA2, LeadS1, LeadS2)
     IF enableNotch→ y := ApplyBiquad(y, notchB0..notchA2, NotchS1, NotchS2)
     IF enableReso → y := ApplyBiquad(y, resoB0..resoA2, ResoS1, ResoS2)
     ※ enable = false のブロックはスルー (ゲイン 1)

4. FF 付加:
     controlInput := y + ffValue

5. NaN/Inf ガード:
     入力に非有限値が含まれる場合は controlInput := 0.0
```

### 2.3 ApplyBiquad (Transposed Direct Form II)

```
y  = b0 * x + s1
s1 = b1 * x - a1 * y + s2
s2 = b2 * x - a2 * y
```

### 2.4 ADS で注入可能なパラメータ

| ADS シンボル | 型 | TMC CreateSymbol |
|---|---|---|
| `ControllerCore_Obj1 (Module1).PIDParams.pidB0..pidA2` | `LREAL` × 5 | 設定済み |
| `ControllerCore_Obj1 (Module1).LeadParams.leadB0..leadA2` | `LREAL` × 5 | 設定済み |
| `ControllerCore_Obj1 (Module1).NotchParams.notchB0..notchA2` | `LREAL` × 5 | 設定済み |
| `ControllerCore_Obj1 (Module1).ResoParams.resoB0..resoA2` | `LREAL` × 5 | 設定済み |
| `ControllerCore_Obj1 (Module1).EnableParams.enablePid` | `BOOL` | 設定済み |
| `ControllerCore_Obj1 (Module1).EnableParams.enableLead` | `BOOL` | 設定済み |
| `ControllerCore_Obj1 (Module1).EnableParams.enableNotch` | `BOOL` | 設定済み |
| `ControllerCore_Obj1 (Module1).EnableParams.enableReso` | `BOOL` | 設定済み |

> Port 351 のシンボルテーブルに PID/Notch/Lead/Reso/EnableParams が表示されることを確認済み (H1/C3 解消)。

---

## 3. DriverAdapter — 信号合成とゲート

### 3.1 GVL_DRV 変数一覧

| 変数 | 型 | リンク | 方向 | 説明 |
|---|---|---|---|---|
| `positionActualValue` | `DINT` | `AT %I*` | VirtualMotorCore/EtherCAT→PLC | 実位置 [pulses] |
| `velocityActualValue` | `DINT` | `AT %I*` | VirtualMotorCore/EtherCAT→PLC | 実速度 [pulses/s] |
| `torqueActualValue` | `INT` | `AT %I*` | VirtualMotorCore/EtherCAT→PLC | 実トルク [‰ rated] |
| `controlInput` | `LREAL` | `AT %I*` | ControllerCore→PLC | 制御出力 [A] |
| `distValue` | `LREAL` | `AT %I*` | ExperimentSequencer→PLC | 外乱値 [A] |
| `statusWord` | `UINT` | `AT %I*` | VirtualMotorCore→PLC | CiA 402 StatusWord |
| `controlWordIn` | `UINT` | `AT %I*` | ModeManager→PLC | CiA 402 ControlWord |
| `enableCurrentOutput` | `BOOL` | `AT %I*` | ModeManager→PLC | 電流出力ゲート |
| `resetReq` | `BOOL` | `AT %I*` | ModeManager→PLC | リセット要求 (D12) |
| `positionRel` | `LREAL` | `AT %Q*` | PLC→ControllerCore/Logger | 相対位置 [rad] |
| `velocityAct` | `LREAL` | `AT %Q*` | PLC→Logger | 速度 [rad/s] |
| `currentAct` | `LREAL` | `AT %Q*` | PLC→Logger | 実電流 [A] |
| `targetTorque` | `INT` | `AT %Q*` | PLC→VirtualMotorCore | Drive 境界の最終出力 [% rated] |
| `controlWordOut` | `UINT` | `AT %Q*` | PLC→VirtualMotorCore | CW 中継 |
| `statusWordOut` | `UINT` | `AT %Q*` | PLC→ModeManager | SW 中継 |

### 3.2 PRG_DriverAdapter 処理 (毎スキャン 1 ms)

```
(* 1. Drive → 工学単位変換 *)
positionRad          := DINT_TO_LREAL(positionActualValue) * TWO_PI_INV_RES
velocityAct          := DINT_TO_LREAL(velocityActualValue) * TWO_PI_INV_RES
currentAct           := INT_TO_LREAL(torqueActualValue) * RATED_CURRENT_DIV_1000

(* 2. リセット — 相対位置オフセットキャプチャ (エッジ検出) *)
resetEdge := resetReq AND NOT resetReqPrev
IF resetEdge THEN
    positionOffsetRad := positionRad
END_IF
resetReqPrev := resetReq

(* 3. 相対位置化 *)
positionRel := positionRad - positionOffsetRad

(* 4. 工学単位 → Drive 変換 (電流クランプ + 外乱加算 + 電流ゲート + 飽和) *)
targetCurrentA := controlInput + distValue
targetCurrentA := Clamp(targetCurrentA, ±MAX_CURRENT_A)  ← モーター保護クランプ

IF enableCurrentOutput AND NOT playbackDone THEN
    targetTorque := LREAL_TO_INT(targetCurrentA * RATED_CURRENT_INV_X1000)
      ← 飽和: INT 範囲 [-32768, 32767] にクランプ
ELSE
    targetTorque := 0                                ← ゲートクローズ (安全)
END_IF

(* 5. CW/SW 中継 *)
controlWordOut := controlWordIn
statusWordOut  := statusWord
```

> `enableCurrentOutput` は ModeManager が `enableEffective AND driveReady` 時のみ `TRUE` を出力する。  
> `playbackDone` は ExperimentSequencer から同一 1 ms タスクで DriverAdapter にも直結し、
> `experimentActiveOut` 停止を待たずに `targetTorque := 0` を強制する。
> ドライブが `OPERATION_ENABLED` に到達するまでトルクは出力されない。  
> `targetTorque` は D11 により `LREAL [Nm]` から Drive 境界の `INT [‰ rated]` に変更済み。
> DriverAdapter より上流の制御契約は current [A] のまま維持する。

---

## 4. VirtualMotorCore — 仮想ドライブ動作

### 4.1 CiA 402 状態遷移 (UpdateDriveState)

VirtualMotorCore は実機ドライブと同じ CiA 402 インターフェースを内蔵する。

```
ControlWord ビット解釈:
  bit 1 (0x0002) = 0  → DisableVoltage (全遷移を SWITCH_ON_DISABLED にリセット)
  bit 7 (0x0080)      → FaultReset (ワンパルスで Fault 解除)
  (CW AND 0x008F):
    0x0006 → Shutdown
    0x0007 → SwitchOn
    0x000F → EnableOperation

状態遷移:
  SWITCH_ON_DISABLED ──[Shutdown]──► READY_TO_SWITCH_ON
  READY_TO_SWITCH_ON ──[SwitchOn]──► SWITCHED_ON
  SWITCHED_ON        ──[EnableOp]──► OPERATION_ENABLED
  FAULT              ──[FaultReset pulse]──► SWITCH_ON_DISABLED
```

#### StatusWord 生成 (ComposeStatusWord)

| DriveState | StatusWord | ビットパターン |
|---|---|---|
| `SWITCH_ON_DISABLED` | `0x0060` | bit6 + bit5 |
| `READY_TO_SWITCH_ON` | `0x0021` | bit5 + bit0 |
| `SWITCHED_ON` | `0x0023` | bit5 + bit1 + bit0 |
| `OPERATION_ENABLED` | `0x0027` | bit5 + bit2 + bit1 + bit0 |
| `FAULT` | `0x0028` | bit5 + bit3 |

### 4.2 物理シミュレーション (StepVirtualMotor)

`OPERATION_ENABLED` 状態のときのみ物理演算が実行される:

```
入力: targetTorque (= ‰ rated, INT from DriverAdapter)

ratedTorque := EffectiveRatedTorque(params)     ← パラメータから取得 (デフォルト 1.2 Nm)

(* maxPermille チェック: 入力レベル保護 *)
IF maxPermille > 0 AND |targetTorquePermille| > maxPermille THEN
    internalFault := TRUE → FAULT
END_IF

tauCmd := (targetTorquePermille / 1000.0) * ratedTorque
torqueSat := Clamp(tauCmd, ±tauLimit)
  ※ |tauCmd| > tauLimit → internalFault → FAULT 状態に遷移

velocity_next := velocity + (dt / mass) * (torqueSat - damping * velocity)
  ※ |velocity_next| > velLimit → internalFault → FAULT 状態に遷移

position_next := position + dt * velocity_next

出力 (CiA 402 整数型):
  positionActualValue  ← SaturatingRoundToDint(position * encoderResolution / 2π)
  velocityActualValue  ← SaturatingRoundToDint(velocity * encoderResolution / 2π)
  torqueActualValue    ← SaturatingRoundToInt((lastAppliedTorqueNm / ratedTorque) * 1000.0)
  statusWord           → DriverAdapter.statusWord にリンク
```

> D11 により入力が `currentIn [A]` から `targetTorque [‰ rated, INT]` に変更。
> 出力も double (`positionOut`/`velocityOut`) から CiA 402 整数型に変更済み。

### 4.3 ADS で注入可能なパラメータ

| ADS シンボル (Port 351) | 型 | 説明 |
|---|---|---|
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.mass` | `LREAL` | 慣性 [kg⋅m²] |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.damping` | `LREAL` | 粘性 [N⋅m⋅s/rad] |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.tauLimit` | `LREAL` | トルクリミット [Nm] |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.velLimit` | `LREAL` | 速度リミット [rad/s] |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.taskDtNs` | `ULINT` | タスク周期 [ns] |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.ratedTorque` | `LREAL` | 定格トルク [Nm] (D11 追加、デフォルト 1.2、kt=1 前提で RATED_CURRENT と同一値) |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.maxPermille` | `LREAL` | 入力指令上限 [‰ rated] (0.0 = 無制限、超過時 Fault) |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.encoderResolution` | `ULONG` | エンコーダ分解能 [pulses/rev] (D11 追加、デフォルト 8388608) |

> `VirtualMotor1Parameter` は `CreateSymbol="true"` でシンボルブラウズ可 (ADS Discovery 確認済み)。  
> `VirtualMotor2Parameter` は CreateSymbol 未設定のため Port 351 に非公開 — AdsRW (PTCID `#x00000002`) で書き込む。

---

## 5. ログ記録 — GVL_SEQ_LOG リングバッファ

### 5.1 GVL_SEQ_LOG 変数一覧

| 変数 | 型 | 説明 |
|---|---|---|
| `LOG_N` | `UDINT` (定数) | リングバッファ長 = **200,000** |
| `seq` | `UDINT` | シーケンス番号 (累積カウンタ) |
| `tNs` | `ULINT` | タイムスタンプ [ns] = `seq × task_dt_ns` |
| `wrIdx` | `UDINT` | 書き込みインデックス (累積、剰余でリング化) |
| `rdIdx` | `UDINT` | 読み出しインデックス (ADS からインクリメント) |
| `overflow` | `BOOL` | `wrIdx - rdIdx > LOG_N` 時に `TRUE` |
| `controlInputTap` | `LREAL` (`AT %I*`) | ControllerCore.controlInput のタップ接続 |
| `positionRelTap` | `LREAL` (`AT %I*`) | DriverAdapter.positionRel のタップ接続 |

### 5.2 ログ配列 (各 `ARRAY[0..LOG_N-1]`)

| チャネル | 型 | 記録内容 |
|---|---|---|
| `logSeq` | `UDINT[]` | シーケンス番号 |
| `logRefValue` | `LREAL[]` | ExperimentSequencer 出力 refValue |
| `logFfValue` | `LREAL[]` | ExperimentSequencer 出力 ffValue |
| `logDistValue` | `LREAL[]` | ExperimentSequencer 出力 distValue |
| `logControlInput` | `LREAL[]` | ControllerCore 出力 (`controlInputTap`) |
| `logTargetCurrent` | `LREAL[]` | `controlInputTap + distValue` (DriverAdapter 相当の合計電流) |
| `logPositionAct` | `LREAL[]` | DriverAdapter 出力 (`positionRelTap`) ※互換名 |
| `logT` | `ULINT[]` | タイムスタンプ [ns] |
| `logIdx` | `UDINT[]` | repeat をまたいだ出力サンプル絶対インデックス |

### 5.3 ログ書き込みロジック

ログ書き込みは **`sampleEmittedThisScan = TRUE` の時のみ** 実行される（= テーブルから 1 サンプル出力されたスキャン）。

```
wrPos := wrIdx MOD LOG_N                        ← リング位置の計算

seq := seq + 1
tNs := seq × VM_TASK_DT_NS (1,000,000 ns)

logSeq[wrPos]          := seq
logRefValue[wrPos]     := GVL_SEQ.refValue
logFfValue[wrPos]      := GVL_SEQ.ffValue
logDistValue[wrPos]    := GVL_SEQ.distValue
logControlInput[wrPos] := controlInputTap       ← TcCOM からのタップ入力
logTargetCurrent[wrPos] := controlInputTap + GVL_SEQ.distValue
logPositionAct[wrPos]  := positionRelTap         ← TcCOM からのタップ入力
logT[wrPos]            := tNs
logIdx[wrPos]          := trialIndex*tableLen + idx_before_increment

wrIdx := wrIdx + 1

IF (wrIdx - rdIdx) > LOG_N THEN
    overflow := TRUE                             ← 読み出しが追いつかない
END_IF
```

### 5.4 リングバッファの読み出し方法 (ADS)

```
1. wrIdx を ADS Read で取得
2. readCount := wrIdx - rdIdx  (未読サンプル数)
3. readCount > 0 なら:
     startPos := rdIdx MOD LOG_N
     各ログ配列から startPos 位置以降のデータを ADS Read
     ※ リング境界をまたぐ場合は 2 回に分けて読む
4. rdIdx := rdIdx + readCount  を ADS Write
```

> `overflow = TRUE` になると、古いデータが上書きされて失われる。  
> 読み出し側は十分な頻度でポーリングする必要がある。  
> 200,000 サンプル @ 1 kHz = 200 秒分のバッファ容量。

### 5.5 リセット時のログクリア

`GVL_SEQ.resetReq = TRUE` 時にログ変数もクリアされる:

```
seq      := 0
tNs      := 0
wrIdx    := 0
rdIdx    := 0
overflow := FALSE
```

> ログ配列の内容自体はゼロクリアされない（インデックスのリセットのみ）。  
> wrIdx/rdIdx が 0 に戻るため、次の実験で上書きされる。

---

## 6. ExperimentLogger — バイナリファイルロギング (C++ TcCOM)

### 6.1 概要

ExperimentLogger は C++ TcCOM モジュールとして実装されたファイルロガーである。  
GVL_SEQ_LOG のリングバッファ (§5) が ADS ポーリング前提の暫定ログであるのに対し、ExperimentLogger は **RT コンテキストから直接ローカルディスクにバイナリファイルを書き出す**。8kHz × 100s = 800,000 レコードの長時間記録に対応する設計。

### 6.2 Data Area (TcCOM I/O)

#### 入力 (InputDst)

| ポート | 型 | ソース | 説明 |
|---|---|---|---|
| `currentCmd` | `LREAL` | DriverAdapter current-domain command | 指令電流 [A] |
| `refValue` | `LREAL` | ExperimentSequencer `refValue` | 位置指令 [rad] |
| `ffValue` | `LREAL` | ExperimentSequencer `ffValue` | FF 信号 [A] |
| `controlInput` | `LREAL` | ControllerCore `controlInput` | 制御出力 [A] |
| `error` | `LREAL` | ControllerCore `error` | 位置誤差 [rad] |
| `motorPosition` | `LREAL` | (Phase 4: EtherCAT) | Motor 側実位置 [rad] |
| `motorVelocity` | `LREAL` | (Phase 4: EtherCAT) | Motor 側実速度 [rad/s] |
| `motorCurrentAct` | `LREAL` | DriverAdapter `currentAct` (D13) | Motor 実電流 [A] |
| `loadPosition` | `LREAL` | DriverAdapter `positionRel` (D12) | Load 側実位置 (相対位置) [rad] |
| `loadVelocity` | `LREAL` | DriverAdapter `velocityAct` (D11) | Load 側実速度 [rad/s] |
| `resetReq` | `BOOL` | ModeManager `resetOut` | リセット要求 |
| `loggingReq` | `BOOL` | ModeManager `experimentActiveOut` | レコード追記ゲート / セッション close |
| `preArmReq` | `BOOL` | ModeManager `preArmOut` | `SERVO_READY` 中の file pre-open |
| `playbackDone` | `BOOL` | ExperimentSequencer `GVL_SEQ.playbackDone` | 同一タスク fast-path でレコード追記停止 |

> Phase 1–3 (SIL) では `motorPosition`, `motorVelocity` は 0 (未接続)。  
> `loadPosition` は DriverAdapter.positionRel (D12)、`loadVelocity` は DriverAdapter.velocityAct (D11)、
> `motorCurrentAct` は DriverAdapter.currentAct (D13) を使用する。  
> `preArmReq` が file open の唯一のトリガであり、`loggingReq` はレコード追記と end-of-session close のみを担当する。
> `loggingReq` が file pre-open 完了前に立ち上がった場合は hard-fail (`errorCode`) とする。

#### 出力 (OutputSrc)

| ポート | 型 | 説明 |
|---|---|---|
| `LogStatus.recordsWritten` | `UDINT` | ディスクに書き込み済みのレコード数 |
| `LogStatus.fileSizeKb` | `UDINT` | ファイルサイズ [KB] |
| `LogStatus.errorCode` | `UDINT` | エラーコード (0 = 正常, 非 0 は内部 `0xE000000x` または下位 HRESULT) |

### 6.3 ADS で注入可能なパラメータ (LogControl)

| ADS シンボル | 型 | 説明 |
|---|---|---|
| `ExperimentLogger_Obj1 (Module1).LogControl.filePath` | `STRING(255)` | 出力ファイルパス (デフォルト: `C:\ExperimentData\experiment_logger.bin`)。親ディレクトリは事前作成必須 |

### 6.4 LogRecord バイナリフォーマット

1 レコード = **96 bytes** (fixed-size, packed):

```
Offset   Size  型          フィールド
------   ----  ----------  ----------------
  0       4    ULONG       seq              シーケンス番号
  4       4    ULONG       reservedPad0     パディング (= 0)
  8       8    ULONGLONG   tNs              タイムスタンプ [ns] = seq × cycleTime
 16       8    double      motorPosition    Motor 側実位置 [rad]
 24       8    double      motorVelocity    Motor 側実速度 [rad/s]
 32       8    double      motorCurrentAct  Motor 実電流 [A]
 40       8    double      loadPosition     Load 側実位置 [rad]
 48       8    double      loadVelocity     Load 側実速度 [rad/s]
 56       8    double      currentCmd       指令電流 [A]
 64       8    double      error            位置誤差 [rad]
 72       8    double      refValue         位置指令 [rad]
 80       8    double      ffValue          FF 信号 [A]
 88       8    double      controlInput     制御出力 [A]
------   ----
         96 bytes / record
```

> 8kHz × 100s = 800,000 records × 96 bytes ≈ **76.8 MB**

### 6.5 内部バッファと非同期ファイル I/O

| パラメータ | 値 | 説明 |
|---|---|---|
| `kBufferRecords` | **8,000** | 1バッファあたりの内部容量 |
| writeバッファ本数 | **2** | 書き込み中バッファ + 追記用バッファ (ping-pong) |
| ファイル I/O | `ITcFileAccessAsync` | TwinCAT 非同期ファイルアクセス |
| タイムスタンプ間隔 | タスク周期から自動取得 | |

### 6.6 ファイル FSM (File State Machine)

```
  IDLE ──[preArmReq ↑]──► OPEN_WAIT
                           │
                     [FileOpen 完了 + valid handle]
                           │
                           ▼
  IDLE ◄──[FileClose 完了] CLOSE_WAIT ◄── ACTIVE ──[バッファ満]──► WRITE_WAIT
                           ▲                                        │
                           │         [FileWrite 完了]               │
                           └────────────────────────────────────────┘

  ※ close 要求は async 中もラッチされ、OPEN/WRITE 完了直後に close へ進む
  ※ 非同期 Check 失敗時は wait state に留まらず session abort + async object release
  ※ loggerReady は ACTIVE かつ valid handle を持つときのみ TRUE
```

### 6.7 CycleUpdate 処理フロー (毎スキャン)

```
1. タスク周期取得:
     cycleTimeNs → timestampStepNsRuntime (タイムスタンプ計算に使用)

2. リセットエッジ検出:
     resetReq 立ち上がり → CloseLogFile + ResetRuntimeState
       seq=0, recordsWritten=0, bytesWritten=0, errorCode=0
       fileHandle=0, FSM→IDLE

3. preArm / logging コマンド監視:
     preArm 立ち上がりエッジ:
       → CloseLogFile (前セッション) + ResetRuntimeState
       → StartAsyncOpen (filePath でファイル pre-open)
       → FSM: IDLE → OPEN_WAIT

     logging 立ち上がりエッジ:
       → loggerReady == TRUE を必須条件とする
       → 未 pre-arm / invalid handle / close pending は hard-fail

     logging 立ち下がり or preArm 立ち下がり:
       → CloseLogFile (残余バッファ flush + ファイルクローズ)

4. FSM ポーリング:
     OPEN_WAIT  → PollAsyncOp() → 完了なら valid handle を確認して FSM=ACTIVE
     WRITE_WAIT → PollAsyncOp() → 完了なら bytesWritten 加算, pending 側バッファを解放して FSM=ACTIVE
     CLOSE_WAIT → PollAsyncOp() → 完了なら fileHandle=0, FSM=IDLE
     いずれも失敗時は session abort + async object release + FSM=ERROR

5. レコード追記 (`loggingReq=TRUE` & `playbackDone=FALSE` & !sessionFailed):
     LogRecord を追記用バッファに追記
     追記用バッファ満杯で FSM=ACTIVE なら StartAsyncWrite:
       → 満杯バッファを WRITE_WAIT 側に固定し、もう一方へ追記継続
     追記用バッファ満杯で FSM!=ACTIVE の場合は hard-fail (取りこぼし禁止)

6. ステータス出力更新:
     LogStatus.recordsWritten = recordsWritten
     LogStatus.fileSizeKb     = bytesWritten / 1024
     LogStatus.errorCode      = errorCode
```

### 6.8 エラーコード一覧

| コード | 種別 | 説明 |
|---|---|---|
| `0x00000000` | 正常 | エラーなし |
| `0xE0000001` など | internal | モジュール内部 invariant / contract 違反 |
| `0x800...` / `0x9811...` など | HRESULT | TwinCAT / COM / ADS / File API が返した生の失敗コード |

> `errorCode` は generic open/close/write failure に丸めず、下位 API が返した `HRESULT` を優先して保持する。

### 6.9 GVL_SEQ_LOG (リングバッファ) との使い分け

| 特性 | GVL_SEQ_LOG (§5) | ExperimentLogger (§6) |
|---|---|---|
| 実装 | PLC ST (ExperimentSequencer 内) | C++ TcCOM |
| 記録先 | PLC メモリ (GVL 配列) | ローカルディスク (バイナリファイル) |
| 容量 | 200,000 サンプル (固定) | ディスク容量依存 (実質無制限) |
| 読み出し | ADS ポーリング (rdIdx/wrIdx) | 実験後にファイル転送 |
| リアルタイム取得 | 可 (実験中ストリーミング) | 不可 (実験後バッチ読み出し) |
| Phase | Phase 1〜 (暫定) | Phase 3〜 (本格運用) |
| 8kHz × 100s | リングバッファ溢れリスクあり | 対応可 (76.8 MB) |

---

## 7. Data Area リンク接続マップ

### 7.1 ModeManager ↔ 各モジュール

```
MAIN.resetOut            (%Q*)  ──►  GVL_SEQ.resetReq           (%I*)
MAIN.resetOut            (%Q*)  ──►  ControllerCore.Inputs.resetReq
MAIN.resetOut            (%Q*)  ──►  ExperimentLogger.Inputs.resetReq
MAIN.resetOut            (%Q*)  ──►  GVL_DRV.resetReq           (%I*)   ← D12 追加
MAIN.experimentActiveOut (%Q*)  ──►  GVL_SEQ.experimentActive   (%I*)
MAIN.preArmOut           (%Q*)  ──►  ExperimentLogger.Inputs.preArmReq
MAIN.experimentActiveOut (%Q*)  ──►  ExperimentLogger.Inputs.loggingReq
MAIN.enableCurrentOut     (%Q*)  ──►  GVL_DRV.enableCurrentOutput (%I*)
MAIN.ctrlWord            (%Q*)  ──►  GVL_DRV.controlWordIn      (%I*)
GVL_DRV.statusWordOut    (%Q*)  ──►  MAIN.statWord              (%I*)
GVL_SEQ.playbackDone     (%Q*)  ──►  MAIN.seqPlaybackDone       (%I*)
GVL_SEQ.playbackDone     (%Q*)  ──►  GVL_DRV.playbackDone       (%I*)
GVL_SEQ.playbackDone     (%Q*)  ──►  ExperimentLogger.Inputs.playbackDone
```

### 7.2 ExperimentSequencer → ControllerCore

```
GVL_SEQ.refValue         (%Q*)  ──►  ControllerCore.Inputs.refValue
GVL_SEQ.ffValue          (%Q*)  ──►  ControllerCore.Inputs.ffValue
```

### 7.3 ControllerCore → DriverAdapter + ログ

```
ControllerCore.Outputs.controlInput  ──►  GVL_DRV.controlInput     (%I*)
ControllerCore.Outputs.controlInput  ──►  GVL_SEQ_LOG.controlInputTap (%I*)
```

### 7.4 ExperimentSequencer → DriverAdapter

```
GVL_SEQ.distValue        (%Q*)  ──►  GVL_DRV.distValue          (%I*)
```

### 7.5 DriverAdapter ↔ VirtualMotorCore

```
GVL_DRV.targetTorque     (%Q*)  ──►  VirtualMotorCore.Inputs.VirtualMotor1Inputs.targetTorque  (INT, ‰ rated)
GVL_DRV.controlWordOut   (%Q*)  ──►  VirtualMotorCore.Inputs.controlWord1
VirtualMotorCore.Outputs.VirtualMotor1Outputs.positionActualValue
                                            ──►  GVL_DRV.positionActualValue (%I*)
VirtualMotorCore.Outputs.VirtualMotor1Outputs.velocityActualValue
                                            ──►  GVL_DRV.velocityActualValue (%I*)
VirtualMotorCore.Outputs.VirtualMotor1Outputs.torqueActualValue
                                            ──►  GVL_DRV.torqueActualValue  (%I*)
VirtualMotorCore.Outputs.statusWord1        ──►  GVL_DRV.statusWord     (%I*)
GVL_DRV.positionRel                         ──►  ControllerCore.Inputs.positionAct
GVL_DRV.positionRel                         ──►  GVL_SEQ_LOG.positionRelTap (%I*)
```

> D11: `currentIn (LREAL)` → `targetTorque (INT, ‰ rated)` に変更。
> D12: `positionOut → ControllerCore` の経路を `DriverAdapter.positionRel → ControllerCore` に変更。

### 7.6 各モジュール → ExperimentLogger (Phase 3〜)

```
DriverAdapter current-domain command [A]                    ──►  ExperimentLogger.Inputs.currentCmd
ExperimentSequencer.refValue                                ──►  ExperimentLogger.Inputs.refValue
ExperimentSequencer.ffValue                                 ──►  ExperimentLogger.Inputs.ffValue
ControllerCore.Outputs.controlInput                         ──►  ExperimentLogger.Inputs.controlInput
ControllerCore.Outputs.error                                ──►  ExperimentLogger.Inputs.error
(Phase 4: EtherCAT Motor 側)                                ──►  ExperimentLogger.Inputs.motorPosition   ← SIL: 未接続 (0)
(Phase 4: EtherCAT Motor 側)                                ──►  ExperimentLogger.Inputs.motorVelocity   ← SIL: 未接続 (0)
GVL_DRV.currentAct                                          ──►  ExperimentLogger.Inputs.motorCurrentAct  ← D13: DriverAdapter 経由
GVL_DRV.positionRel                                         ──►  ExperimentLogger.Inputs.loadPosition     ← D12: DriverAdapter 経由
GVL_DRV.velocityAct                                         ──►  ExperimentLogger.Inputs.loadVelocity     ← D11: DriverAdapter 経由
ModeManager.resetOut                                        ──►  ExperimentLogger.Inputs.resetReq
ModeManager.preArmOut                                       ──►  ExperimentLogger.Inputs.preArmReq
ModeManager.experimentActiveOut                             ──►  ExperimentLogger.Inputs.loggingReq
ExperimentSequencer.playbackDone                            ──►  ExperimentLogger.Inputs.playbackDone
```

> D12: `loadPosition` のソースを `ControllerCore.positionRel` → `GVL_DRV.positionRel` に変更。
> D13: `motorCurrentAct` を `GVL_DRV.currentAct` に接続 (SIL でも飽和後の実電流を記録可能)。
> D11: `loadVelocity` のソースを `VirtualMotorCore.velocityOut` → `GVL_DRV.velocityAct` に変更。

---

## 8. ADS ポート・シンボルリファレンス (実機確認済み)

> **確認日:** 2026-02-26  
> **確認方法:** `run_ads_discovery_demo.m` — `twincat_ads.SymbolBrowser.discover_ports_and_symbols`  
> **ターゲット AmsNetId:** `192.168.10.3.1.1`

### 8.1 ターゲット構成

| 項目 | 値 |
|---|---|
| AmsNetId | `192.168.10.3.1.1` |
| アーキテクチャ | x64 |
| 非 Windows CPU | 2 (CpuId 2, 3) |
| RT タスク: VirtualMotorTask | Port **351**, Priority 1, CycleTime 1 ms, Affinity CPU3 |
| RT タスク: StateTask | Port **355**, Priority 2, CycleTime 1 ms |

### 8.2 AMS ポート割り当て一覧

| AMS Port | モジュール | 実装 | Task | 確認シンボル数 |
|---|---|---|---|---|
| **351** | C++ TcCOM (ControllerCore, VirtualMotorCore, ExperimentLogger) | C++ | VirtualMotorTask (1 ms) | 46 |
| **851** | DriverAdapter | PLC ST | VirtualMotorTask (1 ms) | ~88 |
| **852** | StateMachineControl (ModeManager) | PLC ST | PlcTask (10 ms) | 124 |
| **853** | ExperimentSequencer + GVL_SEQ_LOG | PLC ST | VirtualMotorTask (1 ms) | 137 |

> Port **355** (StateTask) は PLC ランタイムではなくシステムタスクのため、シンボルブラウズ対象外。

### 8.3 Port 851 — DriverAdapter (PLC)

#### ユーザー GVL 変数 (`GVL_DRV`)

| ADS シンボル名 | 型 | Size (B) | リンク | R/W | 説明 |
|---|---|---|---|---|---|
| `GVL_DRV.positionActualValue` | `DINT` | 4 | `AT %I*` | R | Drive 実位置 [pulses] (D11 追加) |
| `GVL_DRV.velocityActualValue` | `DINT` | 4 | `AT %I*` | R | Drive 実速度 [pulses/s] (D11 追加) |
| `GVL_DRV.torqueActualValue` | `INT` | 2 | `AT %I*` | R | Drive 実トルク [‰ rated] (D11 追加) |
| `GVL_DRV.controlInput` | `LREAL` | 8 | `AT %I*` | R | ControllerCore 出力 |
| `GVL_DRV.distValue` | `LREAL` | 8 | `AT %I*` | R | ExperimentSequencer 外乱値 |
| `GVL_DRV.statusWord` | `UINT` | 2 | `AT %I*` | R | VirtualMotorCore StatusWord |
| `GVL_DRV.controlWordIn` | `UINT` | 2 | `AT %I*` | R | ModeManager ControlWord |
| `GVL_DRV.enableCurrentOutput` | `BOOL` | 1 | `AT %I*` | R | ModeManager 電流ゲート |
| `GVL_DRV.playbackDone` | `BOOL` | 1 | `AT %I*` | R | ExperimentSequencer fast-path 完了通知 |
| `GVL_DRV.resetReq` | `BOOL` | 1 | `AT %I*` | R | ModeManager リセット要求 (D12 追加) |
| `GVL_DRV.positionRel` | `LREAL` | 8 | `AT %Q*` | R | 相対位置 [rad] (D12 追加) |
| `GVL_DRV.velocityAct` | `LREAL` | 8 | `AT %Q*` | R | 速度 [rad/s] (D11 追加) |
| `GVL_DRV.currentAct` | `LREAL` | 8 | `AT %Q*` | R | 実電流 [A] (D13 追加) |
| `GVL_DRV.targetTorque` | `INT` | 2 | `AT %Q*` | R | Drive 境界の最終出力 [% rated] → VirtualMotorCore |
| `GVL_DRV.controlWordOut` | `UINT` | 2 | `AT %Q*` | R | CW 中継 → VirtualMotorCore |
| `GVL_DRV.statusWordOut` | `UINT` | 2 | `AT %Q*` | R | SW 中継 → ModeManager |

### 8.4 Port 852 — StateMachineControl (ModeManager)

#### GVL_MODE (フラグ・状態)

| ADS シンボル名 | 型 | Size (B) | R/W | 説明 |
|---|---|---|---|---|
| `GVL_MODE.modeFlags` | `UINT` | 2 | **W** | ビットフラグ一括制御（reset ビットは非推奨） |
| `GVL_MODE.resetReq` | `BOOL` | 1 | **W** | リセット要求（ADS が TRUE を書込み、PLC が受理後 FALSE に戻す） |
| `GVL_MODE.resetAckCounter` | `UDINT` | 4 | R | reset 受理カウンタ（受理ごとに +1） |
| `GVL_MODE.experimentActive` | `BOOL` | 1 | R | 実験実行中フラグ (ModeManager 出力) |
| `GVL_MODE.experimentState` | `UINT` | 2 | R | 状態値 0–3 |
| `GVL_MODE.MODEF_SERVO_ENABLE` | `UINT` | 2 | R | 定数 `16#0001` |
| `GVL_MODE.MODEF_EXPERIMENT_START_REQ` | `UINT` | 2 | R | 定数 `16#0002` |
| `GVL_MODE.MODEF_RESET_REQ` | `UINT` | 2 | R | 定数 `16#0004`（非推奨） |
| `GVL_MODE.STATE_IDLE` | `UINT` | 2 | R | 定数 `0` |
| `GVL_MODE.STATE_READY` | `UINT` | 2 | R | 定数 `1` |
| `GVL_MODE.STATE_RUNNING` | `UINT` | 2 | R | 定数 `2` |
| `GVL_MODE.STATE_DONE` | `UINT` | 2 | R | 定数 `3` |

#### MAIN (I/O + 内部変数)

| ADS シンボル名 | 型 | Size (B) | リンク | R/W | 説明 |
|---|---|---|---|---|---|
| `MAIN.ctrlWord` | `UINT` | 2 | `AT %Q*` | R | CiA 402 ControlWord 出力 |
| `MAIN.experimentActiveOut` | `BOOL` | 1 | `AT %Q*` | R | experimentActive 出力 |
| `MAIN.preArmOut` | `BOOL` | 1 | `AT %Q*` | R | logger pre-arm 出力 |
| `MAIN.resetOut` | `BOOL` | 1 | `AT %Q*` | R | ワンショットリセットパルス |
| `MAIN.enableCurrentOut` | `BOOL` | 1 | `AT %Q*` | R | 電流ゲート出力 |
| `MAIN.statWord` | `UINT` | 2 | `AT %I*` | R | StatusWord 入力 |
| `MAIN.seqPlaybackDone` | `BOOL` | 1 | `AT %I*` | R | Sequencer 完了入力 |
| `MAIN.enable` | `BOOL` | 1 | — | R | サーボ有効フラグ (内部) |
| `MAIN.enableEffective` | `BOOL` | 1 | — | R | 有効条件成立 (内部) |
| `MAIN.driveReady` | `BOOL` | 1 | — | R | ドライブ OPERATION_ENABLED 到達 |

#### FB_StateMachineControl (内部デバッグ用)

| ADS シンボル名 | 型 | Size (B) | 説明 |
|---|---|---|---|
| `MAIN.fbStateMachine.statusWord` | `UINT` | 2 | StatusWord コピー |
| `MAIN.fbStateMachine.enable` | `BOOL` | 1 | 有効フラグ |
| `MAIN.fbStateMachine.controlWord` | `UINT` | 2 | 生成した ControlWord |
| `MAIN.fbStateMachine.driveState` | `E_DriveState` | 2 | 現在のドライブ状態 |

### 8.5 Port 853 — ExperimentSequencer

#### GVL_SEQ (テーブル・制御変数)

| ADS シンボル名 | 型 | Size (B) | リンク | R/W | 説明 |
|---|---|---|---|---|---|
| `GVL_SEQ.refTable` | `ARRAY[0..99999] OF LREAL` | 800,000 | — | **W** | 位置指令テーブル [rad] |
| `GVL_SEQ.ffTable` | `ARRAY[0..99999] OF LREAL` | 800,000 | — | **W** | FF テーブル [A] |
| `GVL_SEQ.distTable` | `ARRAY[0..99999] OF LREAL` | 800,000 | — | **W** | 外乱テーブル [A] |
| `GVL_SEQ.tableLen` | `UDINT` | 4 | — | **W** | テーブル有効長 |
| `GVL_SEQ.idx` | `UDINT` | 4 | — | R | 現在の再生インデックス |
| `GVL_SEQ.refValue` | `LREAL` | 8 | `AT %Q*` | R | 現在の ref 出力 |
| `GVL_SEQ.ffValue` | `LREAL` | 8 | `AT %Q*` | R | 現在の FF 出力 |
| `GVL_SEQ.distValue` | `LREAL` | 8 | `AT %Q*` | R | 現在の外乱出力 |
| `GVL_SEQ.playbackDone` | `BOOL` | 1 | `AT %Q*` | R | 再生完了フラグ |
| `GVL_SEQ.resetReq` | `BOOL` | 1 | `AT %I*` | R | リセット要求入力 |
| `GVL_SEQ.experimentActive` | `BOOL` | 1 | `AT %I*` | R | 実験実行中入力 |

#### GVL_SEQ_LOG (リングバッファログ)

| ADS シンボル名 | 型 | Size (B) | R/W | 説明 |
|---|---|---|---|---|
| `GVL_SEQ_LOG.wrIdx` | `UDINT` | 4 | R | 書き込みインデックス |
| `GVL_SEQ_LOG.rdIdx` | `UDINT` | 4 | **W** | 読み出しインデックス |
| `GVL_SEQ_LOG.overflow` | `BOOL` | 1 | R | オーバーフロー検出 |
| `GVL_SEQ_LOG.seq` | `UDINT` | 4 | R | シーケンス番号 |
| `GVL_SEQ_LOG.tNs` | `ULINT` | 8 | R | タイムスタンプ [ns] |
| `GVL_SEQ_LOG.LOG_N` | `UDINT` | 4 | R | 定数 200,000 |
| `GVL_SEQ_LOG.logSeq` | `ARRAY[0..199999] OF UDINT` | 800,000 | R | ログ: シーケンス番号 |
| `GVL_SEQ_LOG.logRefValue` | `ARRAY[0..199999] OF LREAL` | 1,600,000 | R | ログ: 位置指令 |
| `GVL_SEQ_LOG.logFfValue` | `ARRAY[0..199999] OF LREAL` | 1,600,000 | R | ログ: FF 値 |
| `GVL_SEQ_LOG.logDistValue` | `ARRAY[0..199999] OF LREAL` | 1,600,000 | R | ログ: 外乱値 |
| `GVL_SEQ_LOG.logControlInput` | `ARRAY[0..199999] OF LREAL` | 1,600,000 | R | ログ: 制御出力 |
| `GVL_SEQ_LOG.logTargetCurrent` | `ARRAY[0..199999] OF LREAL` | 1,600,000 | R | ログ: 合計電流 |
| `GVL_SEQ_LOG.logPositionAct` | `ARRAY[0..199999] OF LREAL` | 1,600,000 | R | ログ: 実位置 |
| `GVL_SEQ_LOG.logT` | `ARRAY[0..199999] OF ULINT` | 1,600,000 | R | ログ: タイムスタンプ |
| `GVL_SEQ_LOG.logIdx` | `ARRAY[0..199999] OF UDINT` | 800,000 | R | ログ: repeat をまたいだ絶対インデックス |

### 8.6 Port 351 — C++ TcCOM モジュール

Port 351 は VirtualMotorTask に紐付く C++ TcCOM インスタンスのシンボルを公開する。  
`CreateSymbol="true"` が設定された Data Area シンボルとパラメータのみがシンボルブラウズ可能。

#### ControllerCore_Obj1 (Module1)

| ADS シンボル名 | 型 | Size (B) | R/W | 説明 |
|---|---|---|---|---|
| `ControllerCore_Obj1 (Module1).Inputs.refValue` | `LREAL` | 8 | R | 位置指令入力 |
| `ControllerCore_Obj1 (Module1).Inputs.ffValue` | `LREAL` | 8 | R | FF 入力 |
| `ControllerCore_Obj1 (Module1).Inputs.positionAct` | `LREAL` | 8 | R | 実位置入力 |
| `ControllerCore_Obj1 (Module1).Inputs.resetReq` | `BOOL` | 1 | R | リセット要求入力 |
| `ControllerCore_Obj1 (Module1).Outputs.controlInput` | `LREAL` | 8 | R | 制御出力 |
| `ControllerCore_Obj1 (Module1).Outputs.error` | `LREAL` | 8 | R | 位置誤差 |

> Port 351 のシンボルテーブルに PID/Notch/Lead/Reso/EnableParams が表示されることを確認済み (H1/C3 解消)。

| パラメータ | PTCID (AdsRW 用) |
|---|---|
| PIDParams | `#x00000001` |
| NotchParams | `#x00000002` |
| LeadParams | `#x00000004` |
| EnableParams | `#x00000005` |
| ResoParams | `#x00000006` |

#### ExperimentLogger_Obj1 (Module1)

| ADS シンボル名 | 型 | Size (B) | R/W | 説明 |
|---|---|---|---|---|
| `ExperimentLogger_Obj1 (Module1).LogControl.filePath` | `STRING(255)` | 256 | **W** | 出力ファイルパス |
| `ExperimentLogger_Obj1 (Module1).Outputs.LogStatus.recordsWritten` | `UDINT` | 4 | R | 書き込み済みレコード数 |
| `ExperimentLogger_Obj1 (Module1).Outputs.LogStatus.fileSizeKb` | `UDINT` | 4 | R | ファイルサイズ [KB] |
| `ExperimentLogger_Obj1 (Module1).Outputs.LogStatus.errorCode` | `UDINT` | 4 | R | エラーコード |

#### VirtualMotorCore_Obj1 (Module1)

| ADS シンボル名 | 型 | Size (B) | R/W | 説明 |
|---|---|---|---|---|
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.mass` | `LREAL` | 8 | **W** | 慣性 [kg⋅m²] |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.damping` | `LREAL` | 8 | **W** | 粘性 [N⋅m⋅s/rad] |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.tauLimit` | `LREAL` | 8 | **W** | トルクリミット [Nm] |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.velLimit` | `LREAL` | 8 | **W** | 速度リミット [rad/s] |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.taskDtNs` | `ULINT` | 8 | **W** | タスク周期 [ns] |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.ratedTorque` | `LREAL` | 8 | **W** | 定格トルク [Nm] (kt=1: =RATED_CURRENT) |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.maxPermille` | `LREAL` | 8 | **W** | 入力上限 [‰ rated] (0=無制限) |
| `VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.encoderResolution` | `ULONG` | 4 | **W** | エンコーダ分解能 [pulses/rev] |

---

### 8.7 ADS アクセスパターン早見表

#### ① テーブルアップロード → Port 853 一括書き込み

```
ADS Write:  Port=853  Symbol="GVL_SEQ.refTable"    Data=LREAL[N]  (800,000 B max)
ADS Write:  Port=853  Symbol="GVL_SEQ.ffTable"     Data=LREAL[N]  (800,000 B max)
ADS Write:  Port=853  Symbol="GVL_SEQ.distTable"   Data=LREAL[N]  (800,000 B max)
ADS Write:  Port=853  Symbol="GVL_SEQ.tableLen"    Data=UDINT
```

#### ② フラグ操作 → Port 852 書き込み

```
ADS Write:  Port=852  Symbol="GVL_MODE.modeFlags"  Data=UINT
ADS Write:  Port=852  Symbol="GVL_MODE.resetReq"   Data=BOOL (TRUE)
ADS Read:   Port=852  Symbol="GVL_MODE.resetAckCounter" → UDINT

 リセット:          `GVL_MODE.resetReq := TRUE`（`modeFlags` bit2 は非推奨）
 サーボ有効:        0x0001
 実験開始:          0x0003  (SERVO | START)
 停止:              0x0000
```

#### ③ 状態監視 → Port 852 読み取り

```
ADS Read:   Port=852  Symbol="GVL_MODE.experimentState"   → UINT (0–3)
ADS Read:   Port=852  Symbol="GVL_MODE.experimentActive"  → BOOL
ADS Read:   Port=852  Symbol="MAIN.driveReady"            → BOOL
```

#### ④ ControllerCore パラメータ注入 → Port 351

```
(CreateSymbol 有効化後)
ADS Write:  Port=351  Symbol="ControllerCore_Obj1 (Module1).PIDParams.pidB0"   Data=LREAL
ADS Write:  Port=351  Symbol="ControllerCore_Obj1 (Module1).EnableParams.enablePid"  Data=BOOL
  ...

(現状: AdsRW による直接アドレス指定)
ADS RW:     Port=351  IG=TBD  IO=PTCID  Data=ST_PID (40 B)
```

#### ⑤ VirtualMotorCore パラメータ注入 → Port 351

```
ADS Write:  Port=351  Symbol="VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.mass"   Data=LREAL
  ...
```

#### ⑥ リングバッファログ読み出し → Port 853

```
ADS Read:   Port=853  Symbol="GVL_SEQ_LOG.wrIdx"            → UDINT
ADS Read:   Port=853  Symbol="GVL_SEQ_LOG.logRefValue"      → LREAL[200000]  (部分読み可)
  ...
ADS Write:  Port=853  Symbol="GVL_SEQ_LOG.rdIdx"            ← rdIdx 更新
```

#### ⑦ ExperimentLogger 制御

```
ADS Write:  Port=351  Symbol="ExperimentLogger_Obj1 (Module1).LogControl.filePath"  Data=STRING
（file open は ModeManager `preArmOut` → `Inputs.preArmReq`、append/close は `experimentActiveOut` → `Inputs.loggingReq` の自動制御）
ADS Read:   Port=351  Symbol="ExperimentLogger_Obj1 (Module1).Outputs.LogStatus.recordsWritten"  → UDINT
ADS Read:   Port=351  Symbol="ExperimentLogger_Obj1 (Module1).Outputs.LogStatus.errorCode"       → UDINT
```

---

### 8.8 Data Area リンク接続一覧 (tsproj Mappings 検証済み)

> **検証日:** 2026-02-27  (D11/D12/D13 反映済み)

tsproj の `<Mappings>` セクションから抽出した **実際のデプロイ済みリンク** 一覧。  
§7 の概念図と異なる箇所がある場合は本セクションが正とする。

```
DriverAdapter ← ExperimentSequencer
  GVL_DRV.distValue             ← GVL_SEQ.distValue

DriverAdapter ← StateMachineControl
  GVL_DRV.controlWordIn         ← MAIN.ctrlWord
  GVL_DRV.enableCurrentOutput    ← MAIN.enableCurrentOut
  GVL_DRV.resetReq              ← MAIN.resetOut                      ← D12 追加
  GVL_DRV.statusWordOut         → MAIN.statWord

DriverAdapter ← ControllerCore
  GVL_DRV.controlInput          ← ControllerCore.Outputs.controlInput

DriverAdapter ↔ VirtualMotorCore
  GVL_DRV.positionActualValue   ← VirtualMotorCore.Outputs.VirtualMotor1Outputs.positionActualValue   ← D11
  GVL_DRV.velocityActualValue   ← VirtualMotorCore.Outputs.VirtualMotor1Outputs.velocityActualValue   ← D11
  GVL_DRV.torqueActualValue     ← VirtualMotorCore.Outputs.VirtualMotor1Outputs.torqueActualValue     ← D13
  GVL_DRV.statusWord            ← VirtualMotorCore.Outputs.statusWord1
  GVL_DRV.targetTorque          → VirtualMotorCore.Inputs.VirtualMotor1Inputs.targetTorque  (INT)     ← D11
  GVL_DRV.targetTorque          → VirtualMotorCore.Inputs.VirtualMotor2Inputs.targetTorque  (INT)     ← 両軸共通
  GVL_DRV.controlWordOut        → VirtualMotorCore.Inputs.controlWord1
  GVL_DRV.controlWordOut        → VirtualMotorCore.Inputs.controlWord2                               ← 両軸共通

DriverAdapter → ControllerCore
  GVL_DRV.positionRel           → ControllerCore.Inputs.positionAct                                  ← D12

ExperimentSequencer ← StateMachineControl
  GVL_SEQ.experimentActive      ← MAIN.experimentActiveOut
  GVL_SEQ.resetReq              ← MAIN.resetOut
  GVL_SEQ.playbackDone          → MAIN.seqPlaybackDone

ExperimentSequencer ← ControllerCore
  GVL_SEQ_LOG.controlInputTap   ← ControllerCore.Outputs.controlInput
  GVL_SEQ.refValue              → ControllerCore.Inputs.refValue
  GVL_SEQ.ffValue               → ControllerCore.Inputs.ffValue

ExperimentSequencer → ExperimentLogger
  GVL_SEQ.ffValue               → ExperimentLogger.Inputs.ffValue
  GVL_SEQ.refValue              → ExperimentLogger.Inputs.refValue

ExperimentSequencer ← DriverAdapter
  GVL_SEQ_LOG.positionRelTap    ← GVL_DRV.positionRel                                                ← D12

StateMachineControl → ControllerCore
  MAIN.resetOut                 → ControllerCore.Inputs.resetReq

StateMachineControl → ExperimentLogger
  MAIN.resetOut                 → ExperimentLogger.Inputs.resetReq
  MAIN.preArmOut                → ExperimentLogger.Inputs.preArmReq
  MAIN.experimentActiveOut      → ExperimentLogger.Inputs.loggingReq

ControllerCore → ExperimentLogger
  ControllerCore.Outputs.controlInput  → ExperimentLogger.Inputs.controlInput
  ControllerCore.Outputs.error         → ExperimentLogger.Inputs.error

DriverAdapter → ExperimentLogger
  DriverAdapter current-domain command [A]  → ExperimentLogger.Inputs.currentCmd
  GVL_DRV.positionRel                  → ExperimentLogger.Inputs.loadPosition      ← D12
  GVL_DRV.velocityAct                  → ExperimentLogger.Inputs.loadVelocity      ← D11
  GVL_DRV.currentAct                   → ExperimentLogger.Inputs.motorCurrentAct   ← D13
```

> SIL では `motorPosition`/`motorVelocity` は未接続（0埋め）。
> `loadPosition` は D12 により `DriverAdapter.positionRel` 、`loadVelocity` は D11 により `DriverAdapter.velocityAct`、
> `motorCurrentAct` は D13 により `DriverAdapter.currentAct` を使用する。


