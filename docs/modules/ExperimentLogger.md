# ExperimentLogger

> **位置づけ:** 実験データのファイルロギングを担うモジュール仕様  
> **対象読者:** C++ TcCOM 実装者、ロギング基盤の保守担当者  
> **更新条件:** 入出力項目、ロギング条件、ファイル形式契約が変わったとき  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) / [TechnicalReference](../architecture/TechnicalReference.md) / [OpenIssues](../status/OpenIssues.md)

## 概要
ExperimentLogger は実験データをバイナリ形式で保存する C++ TcCOM ロガーである。`Inputs.control.preArmReq` により `SERVO_READY` 中に file open を先行完了し、`Inputs.control.loggingReq` はレコード追記とセッション close のみを担う。`Inputs.control.playbackDone` は同一タスク内の fast path として働き、再生完了スキャンで新規レコード追記を即時停止する。`Inputs.record.*` には記録対象信号のみを集約する。MATLAB 側の評価経路はこの `.bin` ファイル読み出しのみを正規経路とする。

## 入力
| 項目 | 型 | ソース | 備考 |
|---|---|---|---|
| `record.currentCmd` | `LREAL` | DriverAdapter | command current [A]; `% rated` drive signals are converted back to current units before logging |
| `record.refValue` | `LREAL` | ExperimentSequencer | reference |
| `record.ffValue` | `LREAL` | ExperimentSequencer | feedforward |
| `record.controlInput` | `LREAL` | ControllerCore | controller output |
| `record.error` | `LREAL` | ControllerCore | `ref - loadPosition` |
| `record.motor.position` | `LREAL` | DriverAdapter `motor.positionRel` | zero-based per run |
| `record.motor.velocity` | `LREAL` | DriverAdapter `motor.velocityAct` | motor velocity |
| `record.motor.currentAct` | `LREAL` | DriverAdapter `motor.currentAct` (D13) | motor current (SIL: via VirtualMotorCore → DriverAdapter) |
| `record.load.position` | `LREAL` | DriverAdapter `load.positionRel` (D12) | zero-based per run |
| `record.load.velocity` | `LREAL` | DriverAdapter `load.velocityAct` (D11) | SIL load velocity |
| `control.resetReq` | `BOOL` | ModeManager | reset edge |
| `control.loggingReq` | `BOOL` | ModeManager `experimentActiveOut` | append gate and session close trigger |
| `control.preArmReq` | `BOOL` | ModeManager `preArmOut` | pre-open trigger in `SERVO_READY` |
| `control.playbackDone` | `BOOL` | ExperimentSequencer `GVL_SEQ.playbackDone` | same-task write-stop fast path |

## 出力
| 項目 | 型 | 備考 |
|---|---|---|
| `status.recordsWritten` | `UDINT` | written records |
| `status.fileSizeKb` | `UDINT` | file size in KB |
| `status.errorCode` | `UDINT` | 0 = OK, otherwise internal `0xE000000x` code or underlying HRESULT |
| `status.loggerReady` | `BOOL` | `ACTIVE` かつ有効 file handle 保持、close/error pending なしのとき `TRUE`。ModeManager が `SERVO_READY → RUNNING` 遷移前の確認に使用 |
| `status.fileReleased` | `BOOL` | 直近セッションの close 正常完了後に `TRUE` |

## 制御パラメータ
| シンボル | 型 | 備考 |
|---|---|---|
| `ExperimentLogger_Obj1 (Module1).LogControl.filePath` | `STRING(255)` | output path; parent directory must already exist |

`Inputs.control.preArmReq` だけが file open を開始できる。`Inputs.control.loggingReq` は file open を兼務せず、logger がすでに `ACTIVE` でなければ不正要求として扱う。`Inputs.control.playbackDone` は ModeManager から close 責務を奪わず、新規レコード追記だけを即時停止する。

## 実行時動作
1. `control.preArmReq` 立上りでセッション実行状態を初期化し、非同期 file open を開始する。open 完了後に pre-armed な `ACTIVE` 状態へ入る。
2. `control.loggingReq` 立上りでは file FSM がすでに `ACTIVE` であることを要求し、満たさなければエラーとしてセッション失敗扱いにする。
3. `control.loggingReq = TRUE` かつ `control.playbackDone = FALSE` かつセッション未失敗の間は、1 スキャンにつき 1 件の `LogRecord` を `Inputs.record.*` から追記する。`WRITE_WAIT` 中も別バッファへ蓄積を継続する。
4. `control.playbackDone = TRUE` になったスキャンでは、新規レコード追記を即時停止する。
5. `control.loggingReq` 立下りで残バッファを flush し、file close を開始する。
6. `control.loggingReq = FALSE` のまま `control.preArmReq` が立下る場合、実行に入らなかった pre-open 済み file を close する。
7. `control.resetReq` 立上りでは安全にセッション停止へ入り、保留中の非同期 close 完了後に実行状態を初期化する。
8. 非同期 `OPEN_WAIT` / `WRITE_WAIT` / `CLOSE_WAIT` の失敗は wait 状態に居座らせず、`ITcFileAccessAsync` を解放してセッションを中断し、`ERROR` または reset teardown 後の `IDLE` へ遷移する。生の失敗コードは `status.errorCode` に保持する。
9. `OPEN_WAIT` 完了時は返却 file handle の妥当性を検証してから logger ready と判定する。handle 無効の open 完了は致命的失敗として扱う。
10. `control.loggingReq` 立下り時は `Write -> Write -> ... -> Close` の順でバッファを drain し、`WRITE_WAIT` 中に捕捉したレコードを落とさない。
11. `status.fileReleased` は reset と新規 pre-arm でクリアされ、close 経路がエラーなく `IDLE` へ戻ったときだけ `TRUE` になる。

## マッピング (SIL)
- `record.motor.position <- DriverAdapter.motor.positionRel`
- `record.motor.velocity <- DriverAdapter.motor.velocityAct`
- `record.motor.currentAct <- DriverAdapter.motor.currentAct` (D13: SIL でも接続済み)
- `record.load.position <- DriverAdapter.load.positionRel` (D12: ControllerCore.positionRel から変更)
- `record.load.velocity <- DriverAdapter.load.velocityAct` (D11: VirtualMotorCore.velocityOut から変更)
- `control.preArmReq <- ModeManager.preArmOut` (Issue #12: pre-open in `SERVO_READY`)
- `control.playbackDone <- ExperimentSequencer.GVL_SEQ.playbackDone` (H6: same-task fast-path stop)
