# ExperimentSequencer

> **位置づけ:** テーブル再生と進行状態管理を担うモジュール仕様  
> **対象読者:** PLC 実装者、テーブル再生ロジックの保守担当者  
> **更新条件:** テーブル入力、状態遷移、出力契約が変わったとき  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) §2A / [ModeManager](./ModeManager.md)

---

## 1. 概要

ExperimentSequencer はテーブル再生専用の PLC モジュールである。  
`refTable` / `ffTable` / `distTable` を 1 サンプルずつ再生し、`refValue` / `ffValue` / `distValue` を出力する。

`FB_ExperimentSequencerCore` が start/reset edge、`E_SeqState`、`idx` / `trialIndex`、repeat境界、最終sample保持を所有する。`PRG_ExperimentSequencer` は `GVL_SEQ` 境界として table長を物理上限へclampし、coreが要求する現在indexの3 sampleを読み、core出力を既存GVLへ反映する。

本モジュールは以下を担当する:

1. テーブル長クランプ (`tableLenClamped`)
2. 再生状態管理 (`E_SeqState`)
3. 繰り返し再生 (`repeatCount`, `trialIndex`)
4. 完了/異常通知 (`playbackDone`, `seqError`)
5. 再生インデックス管理 (`idx`, `trialIndex`, `tableLenClamped`)

> `modeFlags` 入力は持たない。開始/停止は `experimentActive` と `resetReq` によって制御する。

---

## 2. 状態定義 (`E_SeqState`)

| 値 | 状態 | 意味 |
|---|---|---|
| `0` | `IDLE` | 待機。出力ゼロ。 |
| `10` | `PLAYING` | テーブル再生中。 |
| `20` | `COMPLETE` | 再生完了。`experimentActive=FALSE` で IDLE 復帰。 |
| `90` | `FAULT` | 入力異常。`resetReq` 立上りで復帰。 |

FAULT 遷移条件:

- `tableLen = 0`
- `repeatCount = 0`

---

## 3. I/O 仕様 (`GVL_SEQ`)

### 3.1 入力 (`AT %I*`)

| 変数名 | 型 | 説明 |
|---|---|---|
| `resetReq` | `BOOL` | リセット要求 (立上りエッジ検出) |
| `experimentActive` | `BOOL` | 再生実行フラグ |

### 3.2 出力 (`AT %Q*`)

| 変数名 | 型 | 説明 |
|---|---|---|
| `refValue` | `LREAL` | 位置指令値 (`refTable[idx]`) |
| `ffValue` | `LREAL` | FF 値 (`ffTable[idx]`) |
| `distValue` | `LREAL` | 外乱値 (`distTable[idx]`) |
| `playbackDone` | `BOOL` | 全 trial 再生完了 |
| `seqError` | `BOOL` | `seqState=FAULT` のとき TRUE |

### 3.3 内部管理変数

| 変数名 | 型 | 説明 |
|---|---|---|
| `tableLen` | `UDINT` | 要求テーブル長 |
| `tableLenClamped` | `UDINT` | `N_REF_MAX/N_FF_MAX/N_DIST_MAX` でクランプ後 |
| `idx` | `UDINT` | 現 trial 内インデックス |
| `repeatCount` | `UDINT` | trial 繰返し回数 |
| `trialIndex` | `UDINT` | 現在 trial 番号 |
| `seqState` | `E_SeqState` | 状態機械状態 |

---

## 4. テーブル仕様

| 変数名 | 型 | サイズ |
|---|---|---|
| `refTable` | `ARRAY[0..N_REF_MAX-1] OF LREAL` | `N_REF_MAX=100000` |
| `ffTable` | `ARRAY[0..N_FF_MAX-1] OF LREAL` | `N_FF_MAX=100000` |
| `distTable` | `ARRAY[0..N_DIST_MAX-1] OF LREAL` | `N_DIST_MAX=100000` |

`tableLenClamped = min(tableLen, N_REF_MAX, N_FF_MAX, N_DIST_MAX)` として運用する。

---

## 5. 再生フロー

1. `resetReq` 立上りで `idx` / `trialIndex` / `playbackDone` を初期化し `IDLE` に戻る。
2. `IDLE` で `experimentActive` 立上り時、`tableLenClamped` と `repeatCount` を検証。
3. 正常時 `PLAYING` へ遷移し、1 スキャンあたり 1 サンプルを出力。
4. `idx` が trial 終端に到達:
- 最終 trial なら `playbackDone := TRUE` かつ `COMPLETE`。
- 途中 trial なら `idx := 0`、`trialIndex++` で継続。
5. `experimentActive=FALSE` で `IDLE` へ戻し、出力をゼロ化。

---

## 6. ADS シンボル (主要)

| シンボル | 型 | R/W |
|---|---|---|
| `GVL_SEQ.refTable` | `ARRAY[...] OF LREAL` | W |
| `GVL_SEQ.ffTable` | `ARRAY[...] OF LREAL` | W |
| `GVL_SEQ.distTable` | `ARRAY[...] OF LREAL` | W |
| `GVL_SEQ.tableLen` | `UDINT` | W |
| `GVL_SEQ.repeatCount` | `UDINT` | W |
| `GVL_SEQ.experimentActive` | `BOOL` | I/O Mapping |
| `GVL_SEQ.playbackDone` | `BOOL` | R |
| `GVL_SEQ.seqError` | `BOOL` | R |
| `GVL_SEQ.seqState` | `E_SeqState` | R |
