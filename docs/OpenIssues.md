# Open Issues

> **更新:** 2026-03-05

---

## 1. ExperimentLogger — `ADS_E_PENDING` 誤識別は修正済み、実機 E2E 確認は未実施

### 背景

`VirtualMotorTask` (Port 351) 上で `ITcFileAccessAsync::FileOpen` を呼ぶと Page Fault が発生していた。
初期の調査で、根本原因のひとつは `ITcFileAccessAsync` インスタンスの初期化不備と判明:
- `TcSetObjPara` 3 本 (`AdsProvider` / `SegmentSize` / `TimeoutMs`) が未設定
- `TcSetObjState` による SAFEOP → OP 遷移が未実施

その後の追跡で、別の実障害として `ADS_E_PENDING (0x98110708)` を `S_PENDING (0x00000001)` と誤比較していたことも判明した。
これにより `FileOpen()` / `Check()` が返す pending を failure と誤認し、`m_sessionFailed = true` に落ちて logger が stuck していた。

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
| Pending 判定 | `FAILED_AND_NOT_PENDING(hr)` で `ADS_E_PENDING` を進行中として扱うよう修正済み |
| Async wait-state hardening | `PollAsyncOp()` failure で wait state 残留しないよう修正済み |
| `loggerReady` contract | `ACTIVE` かつ valid handle 保持時のみ `TRUE` に修正済み |
| `errorCode` | internal code に加え raw `HRESULT` を保持するよう修正済み |
| `SetObjStateOS` / `SetObjStateSO` rollback | 余分な `SAFEOP` 明示遷移を除去済み |
| `SetObjStateSP` 解放 | `SAFEOP -> PREOP` 遷移を行わずシンプル解放へ修正済み |

`debugStage` を用いた段階的切り分けは削除済み。現行コードは常に本番パスを通る。

### オープン課題

上記の修正は実装済みだが、**実機での E2E 動作確認が未実施**。

今回の修正では、次の実障害対策が入っている:
- `OPEN_WAIT` / `WRITE_WAIT` / `CLOSE_WAIT` で `Check()` が失敗しても wait state に固着しない
- `OPEN_WAIT` 完了時に file handle を検証し、無効 handle のまま `loggerReady=TRUE` にならない
- `ADS_E_PENDING` を genuine failure と誤認しない
- async 中に発生した close 要求をラッチし、open/write 完了直後に確実に close へ進む

確認すべき項目:
1. `loggingReq` 立ち上がりで `FileOpen` が成功し Page Fault が発生しないこと
2. セッション中にバイナリレコードが書き込まれること
3. `loggingReq` 立ち下がりでフラッシュ・クローズが正常完了し `C:\ExperimentData\experiment_logger.bin` が生成されること
4. `run_position_command_demo` 完走 + ログファイル生成

残課題は **実機での E2E 検証のみ**。

### 検証基準

- `loggingReq` 立ち上がり〜立ち下がりで `LogStatus.errorCode = 0` を確認
- ログファイルが生成され、`recordsWritten > 0` かつ `fileSizeKb > 0` を確認
- 3 回連続で PASS

---

## 2. ExperimentLoggerInterfaces.h — カスタム TcCOM インターフェース未定義

`ExperimentLogger/ExperimentLoggerInterfaces.h` の InterfaceIDs / EventClasses セクションが空。
現行の外部通信は ADS データエリア (`ADI_Module1Inputs` / `ADI_Module1Outputs`) とパラメータ `PID_Module1LogControl` のみで機能しており、カスタム TcCOM インターフェースは現時点では不要。

状態: **要件が確定次第、インターフェース定義を追加する。現状は問題なし。**

---

## 3. DriverAdapter -> ExperimentLogger `currentCmd` 経路が未接続

### 背景

設計仕様では `ExperimentLogger.Inputs.currentCmd` に DriverAdapter 側の電流指令 [A] を記録する想定だが、
現ブランチの `GVL_DRV` には `currentCmd AT %Q* : LREAL` が定義されていない。
`PRG_DriverAdapter` 内の `targetCurrentA` はローカル変数のため I/O マッピングに利用できない。

### 影響

- logger の `currentCmd` フィールドが未接続または未定義値になる可能性がある。
- 再現解析時に「指令電流 vs 実電流」の比較精度が低下する。

### 解決条件

1. `DriverAdapter/GVLs/GVL_DRV.TcGVL` に `currentCmd AT %Q* : LREAL` を追加
2. `PRG_DriverAdapter` で `targetCurrentA` 計算後に `GVL_DRV.currentCmd` へ代入
3. `ExperimentLogger.Inputs.currentCmd` へ I/O マッピング接続
4. `run_check_logger_bin.m` 等で `currentCmd` が期待波形で記録されることを確認

状態: **未着手（ドキュメント側のみ反映済み）**

---

## 4. Issue #5 完了: SIL 暫定ロギング撤去

- `ExperimentLogger` 単一路へ移行完了。
- PLC/MATLAB から暫定リングバッファ経路を削除。
- 詳細は `docs/GvlSeqLogMigrationPlan.md` の実施結果を参照。
