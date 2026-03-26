# ExperimentLogger

> **位置づけ:** 実験データのファイルロギングを担うモジュール仕様  
> **対象読者:** C++ TcCOM 実装者、ロギング基盤の保守担当者  
> **更新条件:** 入出力項目、ロギング条件、ファイル形式契約が変わったとき  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) / [TechnicalReference](../architecture/TechnicalReference.md) / [OpenIssues](../status/OpenIssues.md)

## 概要
ExperimentLogger は実験データをバイナリ形式で保存する C++ TcCOM ロガーである。`Inputs.preArmReq` により `SERVO_READY` 中に file open を先行完了し、`Inputs.loggingReq` はレコード追記とセッション close のみを担う。`Inputs.playbackDone` は同一タスク内の fast path として働き、再生完了スキャンで新規レコード追記を即時停止する。MATLAB 側の評価経路はこの `.bin` ファイル読み出しのみを正規経路とする。

## 入力
| 項目 | 型 | ソース | 備考 |
|---|---|---|---|
| `currentCmd` | `LREAL` | DriverAdapter | command current [A]; `% rated` drive signals are converted back to current units before logging |
| `refValue` | `LREAL` | ExperimentSequencer | reference |
| `ffValue` | `LREAL` | ExperimentSequencer | feedforward |
| `controlInput` | `LREAL` | ControllerCore | controller output |
| `error` | `LREAL` | ControllerCore | `ref - loadPosition` |
| `motorPosition` | `LREAL` | (Phase 4) | SIL: unconnected (0) |
| `motorVelocity` | `LREAL` | (Phase 4) | SIL: unconnected (0) |
| `motorCurrentAct` | `LREAL` | DriverAdapter `currentAct` (D13) | motor current (SIL: via VirtualMotorCore → DriverAdapter) |
| `loadPosition` | `LREAL` | DriverAdapter `positionRel` (D12) | zero-based per run |
| `loadVelocity` | `LREAL` | DriverAdapter `velocityAct` (D11) | SIL load velocity |
| `resetReq` | `BOOL` | ModeManager | reset edge |
| `loggingReq` | `BOOL` | ModeManager `experimentActiveOut` | append gate and session close trigger |
| `preArmReq` | `BOOL` | ModeManager `preArmOut` | pre-open trigger in `SERVO_READY` |
| `playbackDone` | `BOOL` | ExperimentSequencer `GVL_SEQ.playbackDone` | same-task write-stop fast path |

## 出力
| 項目 | 型 | 備考 |
|---|---|---|
| `LogStatus.recordsWritten` | `UDINT` | written records |
| `LogStatus.fileSizeKb` | `UDINT` | file size in KB |
| `LogStatus.errorCode` | `UDINT` | 0 = OK, otherwise internal `0xE000000x` code or underlying HRESULT |
| `loggerReady` | `BOOL` | `ACTIVE` かつ有効 file handle 保持、close/error pending なしのとき `TRUE`。ModeManager が `SERVO_READY → RUNNING` 遷移前の確認に使用 |
| `fileReleased` | `BOOL` | 直近セッションの close 正常完了後に `TRUE` |

## 制御パラメータ
| シンボル | 型 | 備考 |
|---|---|---|
| `ExperimentLogger_Obj1 (Module1).LogControl.filePath` | `STRING(255)` | output path; parent directory must already exist |

`Inputs.preArmReq` だけが file open を開始できる。`Inputs.loggingReq` は file open を兼務せず、logger がすでに `ACTIVE` でなければ不正要求として扱う。`Inputs.playbackDone` は ModeManager から close 責務を奪わず、新規レコード追記だけを即時停止する。

## 実行時動作
1. `preArmReq` 立上りでセッション実行状態を初期化し、非同期 file open を開始する。open 完了後に pre-armed な `ACTIVE` 状態へ入る。
2. `loggingReq` 立上りでは file FSM がすでに `ACTIVE` であることを要求し、満たさなければエラーとしてセッション失敗扱いにする。
3. `loggingReq = TRUE` かつ `playbackDone = FALSE` かつセッション未失敗の間は、1 スキャンにつき 1 件の `LogRecord` を追記する。`WRITE_WAIT` 中も別バッファへ蓄積を継続する。
4. `playbackDone = TRUE` になったスキャンでは、新規レコード追記を即時停止する。
5. `loggingReq` 立下りで残バッファを flush し、file close を開始する。
6. `loggingReq = FALSE` のまま `preArmReq` が立下る場合、実行に入らなかった pre-open 済み file を close する。
7. `resetReq` 立上りでは安全にセッション停止へ入り、保留中の非同期 close 完了後に実行状態を初期化する。
8. 非同期 `OPEN_WAIT` / `WRITE_WAIT` / `CLOSE_WAIT` の失敗は wait 状態に居座らせず、`ITcFileAccessAsync` を解放してセッションを中断し、`ERROR` または reset teardown 後の `IDLE` へ遷移する。生の失敗コードは `errorCode` に保持する。
9. `OPEN_WAIT` 完了時は返却 file handle の妥当性を検証してから logger ready と判定する。handle 無効の open 完了は致命的失敗として扱う。
10. `loggingReq` 立下り時は `Write -> Write -> ... -> Close` の順でバッファを drain し、`WRITE_WAIT` 中に捕捉したレコードを落とさない。
11. `fileReleased` は reset と新規 pre-arm でクリアされ、close 経路がエラーなく `IDLE` へ戻ったときだけ `TRUE` になる。

## マッピング (SIL)
- `loadPosition <- DriverAdapter.positionRel` (D12: ControllerCore.positionRel から変更)
- `loadVelocity <- DriverAdapter.velocityAct` (D11: VirtualMotorCore.velocityOut から変更)
- `motorCurrentAct <- DriverAdapter.currentAct` (D13: SIL でも接続済み)
- `preArmReq <- ModeManager.preArmOut` (Issue #12: pre-open in `SERVO_READY`)
- `playbackDone <- ExperimentSequencer.GVL_SEQ.playbackDone` (H6: same-task fast-path stop)
- `motorPosition` / `motorVelocity` は SIL では未接続で 0 埋めとなる。
