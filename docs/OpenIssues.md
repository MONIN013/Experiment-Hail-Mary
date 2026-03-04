# Open Issues

> **更新:** 2026-03-04

---

## 1. ExperimentLogger — FileOpen E2E 動作確認未実施

### 背景

`VirtualMotorTask` (Port 351) 上で `ITcFileAccessAsync::FileOpen` を呼ぶと Page Fault が発生していた。
調査の結果、根本原因は `ITcFileAccessAsync` インスタンスの初期化不備と判明:
- `TcSetObjPara` 3 本 (`AdsProvider` / `SegmentSize` / `TimeoutMs`) が未設定
- `TcSetObjState` による SAFEOP → OP 遷移が未実施

### 現在の実装状態

| 項目 | 状態 |
|---|---|
| `TcCreateInstance(CID_TcFileAccessAsync)` | `EnsureFileAccessAsync()` で lazy 生成 |
| `PID_TcFileAccessAsyncAdsProvider` 設定 | `InitializeFileAccessAsyncObject()` で設定 (`m_spCyclicCaller.GetOID()`) |
| `PID_TcFileAccessAsyncSegmentSize` 設定 | `InitializeFileAccessAsyncObject()` で設定 (4096 bytes) |
| `PID_TcFileAccessAsyncTimeoutMs` 設定 | `InitializeFileAccessAsyncObject()` で設定 (5000 ms) |
| `TcSetObjState(SAFEOP)` / `TcSetObjState(OP)` | `TransitionFileAccessAsyncToState()` 経由で実施 |
| `SetObjStatePS` / `SO` / `OS` / `SP` | 実装済み |
| File FSM (`EFileFsmState`) | `IDLE` / `OPEN_WAIT` / `ACTIVE` / `WRITE_WAIT` / `CLOSE_WAIT` / `ERROR` |

`debugStage` を用いた段階的切り分けは削除済み。現行コードは常に本番パスを通る。

### オープン課題

上記の修正は実装済みだが、**実機での E2E 動作確認が未実施**。

確認すべき項目:
1. `loggingReq` 立ち上がりで `FileOpen` が成功し Page Fault が発生しないこと
2. セッション中にバイナリレコードが書き込まれること
3. `loggingReq` 立ち下がりでフラッシュ・クローズが正常完了し `C:\ExperimentData\experiment_logger.bin` が生成されること
4. `run_position_command_demo` 完走 + ログファイル生成

### 検証基準

- `loggingReq` 立ち上がり〜立ち下がりで `LogStatus.errorCode = 0` を確認
- ログファイルが生成され、`recordsWritten > 0` かつ `fileSizeKb > 0` を確認
- 3 回連続で PASS

---

## 2. ExperimentLoggerInterfaces.h — カスタム TcCOM インターフェース未定義

`ExperimentLogger/ExperimentLoggerInterfaces.h` の InterfaceIDs / EventClasses セクションが空。
現行の外部通信は ADS データエリア (`ADI_Module1Inputs` / `ADI_Module1Outputs`) とパラメータ `PID_Module1LogControl` のみで機能しており、カスタム TcCOM インターフェースは現時点では不要。

状態: **要件が確定次第、インターフェース定義を追加する。現状は問題なし。**

