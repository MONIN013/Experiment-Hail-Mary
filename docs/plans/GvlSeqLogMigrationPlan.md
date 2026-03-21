# Gvl Seq Log Migration Plan

> **位置づけ:** `GVL_SEQ_LOG` から `ExperimentLogger` への段階移行計画  
> **対象読者:** ロギング基盤の保守担当者、移行作業者  
> **更新条件:** 移行フェーズ、完了条件、前提仕様が変わったとき  
> **関連文書:** [OpenIssues](../status/OpenIssues.md) / [MatlabSpec](../architecture/MatlabSpec.md) / [TechnicalReference](../architecture/TechnicalReference.md) / [ExperimentProcedure](../operations/ExperimentProcedure.md) / [SystemArchitecture](../architecture/SystemArchitecture.md)

## 1. 目的

`GVL_SEQ_LOG` は SIL 期の暫定リングバッファとして機能しているが、長期運用では
`ExperimentLogger` (ファイルロギング) を正規パスに統一する。
本計画は「即時撤去」ではなく、実行経路を安全に段階移行するための基準を定義する。

## 2. フェーズ定義

### Phase A (現行)
- `run_position_command_demo.m` は `ExperimentLogger` を優先評価する
- `GVL_SEQ_LOG` は 代替経路 として残す
- `send_position_command` は `out.logger` を返し、logger 状態を可視化する

### Phase B
- 代替経路 利用をデバッグ/CI 限定に縮小
- 通常手順は `ExperimentLogger` のみを合否判定に使用
- `GVL_SEQ_LOG` 依存テストを段階的に分離

### Phase C
- MATLAB からの `GVL_SEQ_LOG` 読み取り導線を削除
- PLC 側 `GVL_SEQ_LOG` の定義・配線・メモリを撤去
- 関連ドキュメントを `ExperimentLogger` 単一パスに更新

## 3. 依存関係棚卸し (2026-03-05)

### コード
- `matlab/+experiment/VirtualMotorSymbols.m` (`GVL_SEQ_LOG.*` シンボル定義)
- `matlab/+experiment/read_experiment_logs.m` (`GVL_SEQ_LOG` 一括読出し)
- `matlab/+experiment/send_position_command.m` (`GVL_SEQ_LOG` 代替経路 読出し)
- `matlab/+experiment/VirtualMotorService.m` (`GVL_SEQ_LOG` ストリーミング)
- `ExperimentSequencer/GVLs/GVL_SEQ_LOG.TcGVL`
- `ExperimentSequencer/POUs/PRG_ExperimentSequencer.TcPOU`

### テスト
- `matlab/tests/unit/TestSendPositionCommand.m`
- `matlab/tests/unit/TestVirtualMotorService.m`
- `matlab/tests/unit/TestWriteHelpers.m`
- `matlab/tests/unit/TestVirtualMotorSymbols.m`

### ドキュメント
- `docs/architecture/MatlabSpec.md`
- `docs/architecture/TechnicalReference.md`
- `docs/operations/ExperimentProcedure.md`
- `docs/architecture/SystemArchitecture.md`

## 4. Phase A 完了条件

- `run_position_command_demo.m` が logger 優先判定で実行できる
- `out.logger.error_after == 0` かつ `out.logger.records_after > 0` の確認手段がある
- logger 読み取り失敗時に `GVL_SEQ_LOG` 代替経路 へ退避できる
- 既存 MATLAB テストに回帰がない

## 5. Phase B/C への進行条件

### B 進行条件
- logger 優先パスで連続 3 回以上の実行が安定
- 代替経路 が常用されていないことをログで確認
- 主要解析フローが bin 読み取りを前提に成立

### C 進行条件
- `GVL_SEQ_LOG` 依存コード/テストの移行先がすべて確定
- PLC メモリ削減効果とリスクをレビュー済み
- `TechnicalReference` / `MatlabSpec` の更新案が揃っている

## 6. 実施結果 (2026-03-05)

- Phase C を完了し、SIL 暫定ロギング経路を撤去。
- ExperimentSequencer の暫定リングバッファ定義を削除。
- MATLAB 側 代替経路 (read_logger_bin 以外) を廃止。
- ExperimentLogger bin 単一路で評価する運用へ更新。


