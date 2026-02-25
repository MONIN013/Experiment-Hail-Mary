# docs と現在実装の差分メモ (2026-02-24)

## 目的

`docs/ProjectArchitecture.md` / `docs/ArchitectureSpec.md` と、現在の TwinCAT プロジェクト実装の差分をざっくり整理する。

## 前提

- `docs/CurrentProject.md` は旧 TE1400 方式の記録であり、現行実装と一致しない箇所がある（意図通り）。
- 現在は「次世代構成」への移行途中。
- `tsproj` / `<Mappings>` / TMC 再読み込み確認は GUI 作業で行う（本メモ更新ではコード側の差異修正を優先）。

## 結論（ざっくり）

- `ExperimentSequencer` / `DriverAdapter` / `ControllerCore` / `VirtualMotorCore` の部品は存在する。
- `StateMachineControl` は `GVL_MODE` を持つ ModeManager 相当へ拡張し、`mode_flags` / `experiment_active` / `experiment_state` を公開する構成に更新した。
- `ExperimentSequencer` は `experiment_active` を外部入力（ModeManager）として扱うように修正し、暫定 SIL ログは `PRG_ExperimentSequencer` に統合した。
- `tsproj` の実配線（GUI Mapping）はまだ docs の最終想定どおりにはなっていない（GUI 作業対象）。
- `ControllerCore` と `ExperimentLogger` は docs 記載より実装が進んでいる部分がある。
- `ControllerCore` の公開 I/O（特に `error` 出力）まわりに、`tsproj` と TMC の不一致候補がある。

## 1. docs が先行している差分（統合未完）

### 1.1 DriverAdapter 経由の配線になっていない

docs の Phase 1 想定は以下:

- `ExperimentSequencer -> ControllerCore -> DriverAdapter -> VirtualMotorCore`
- `StateMachineControl(=ModeManager相当) <-> DriverAdapter`

現状の `ExperimentHailMary.tsproj` マッピングでは、主に以下の直結になっている:

- `ControllerCore.position_act <- VirtualMotorCore.position_out`
- `ControllerCore.control_input -> VirtualMotorCore.current_in`
- `StateMachineControl MAIN.uiCtrlWord/uiStatWord <-> VirtualMotorCore`

つまり、`DriverAdapter` インスタンス自体は存在するが、配線の本線にまだ入っていない。

### 1.2 ModeManager 拡張（mode_flags / experiment_active）はコード側で修正済み

docs では `StateMachineControl` を拡張して、少なくとも以下を扱う想定:

- `mode_flags`
- `experiment_active`
- `experiment_state`

2026-02-25 時点のコード更新で以下を反映:

- `GVL_MODE.mode_flags`
- `GVL_MODE.experiment_active`
- `GVL_MODE.experiment_state`（`IDLE/READY/RUNNING/DONE`）
- `MAIN` に `bSeqPlaybackDone` 入力を追加（Sequencer 完了通知受け）

※ 実際の PLC 間接続（`GVL_MODE` ↔ `GVL_SEQ`）は GUI Mapping 側の作業。

### 1.3 ExperimentLogger のシステム統合が未完（GUI Mapping/運用統合）

`ExperimentLogger` の C++ プロジェクト/コード/TMC は存在するが、`tsproj` の `<Mappings>` では接続されていない。

- 実装はある
- 統合（インスタンス化/配線/運用）が未完

## 2. 実装が docs より進んでいる差分

### 2.1 ControllerCore は「最小ループ」以上を実装済み

`docs/ProjectArchitecture.md` では最小ループ相当の説明だが、実装は以下まで入っている:

- `error` 出力
- PID / Lead / Notch / Reso のチェーン
- 各ブロックの enable/bypass
- `control_input = (FB chain output) + ff_value`

### 2.2 ExperimentLogger は C++ ファイルロガ本体が実装済み

docs では Phase 3 導入扱いだが、実装上は既に以下がある:

- 96 byte 固定長レコード
- 1 ms 前提タイムスタンプ生成
- 8000 レコードバッファ（約 1 秒分）
- `CreateFileA` / `WriteFile` によるバイナリ書き込み

## 3. docs と実装の不一致（要注意）

### 3.1 ControllerCore の `error` 出力が `tsproj` 側で見えていない可能性

コード生成物/TMC には `Outputs.control_input` と `Outputs.error` があるが、`ExperimentHailMary.tsproj` の `ControllerCore` インスタンス定義断片では `Outputs` の `ByteSize=8` かつ `control_input` のみが見える。

可能性:

- `tsproj` 側の TMC 取り込みが古い
- 手動編集/再読み込み不足

`ExperimentLogger` 統合時に `ControllerCore.error` を使う前提なら先に確認が必要。

## 4. ExperimentSequencer / SIL 暫定ログまわりの差分

### 4.1 ExperimentSequencer が「テーブルリプレイ専用」から少しはみ出している

docs では `ExperimentSequencer` は `ref/ff/dist` のスカラ出力専任だが、現状 `GVL_SEQ` には SIL ログ用入力がある:

- `control_input AT %I*`
- `position_act_log AT %I*`

これは暫定ロガ（`PRG_SEQ_SILLogger`）のための実用的な拡張として入っている。

### 4.2 `PRG_SEQ_SILLogger` が別 POU として残っている（2026-02-25 コード更新で解消）

docs の記述では、暫定ログは `GVL_SEQ_LOG` に保持しつつ `ExperimentSequencer` へ置換していく流れ。

2026-02-25 時点のコード更新で以下を反映:

- `PRG_SEQ_SILLogger` のロジックを `PRG_ExperimentSequencer` へ統合
- `ExperimentSequencer` タスク呼び出しを `PRG_ExperimentSequencer` のみへ整理
- `GVL_SEQ_LOG` は引き続き暫定リングバッファとして保持

暫定ログでの `target_torque = control_input + dist_value` 再計算は継続（Phase 3 `ExperimentLogger` 統合までは許容）。

### 4.3 互換エイリアスが残っている

`GVL_SEQ` に以下の互換用定数が残っている:

- `TABLE_MAX_N`

docs の「`GVL_EXP*` 互換は維持しない」方針と完全一致ではないが、移行補助としては合理的。

## 5. 一致している点（現状でも良い）

- `GVL_SEQ` / `GVL_SEQ_LOG` の命名は docs 方針と一致
- `ExperimentSequencer` のテーブル再生（`ref/ff/dist`、`idx`、`table_len` クランプ、再生完了処理）は概ね docs 方針どおり
- `DriverAdapter` の ST ロジック（`control_input + dist_value`、CW/SW 中継）は docs 方針どおり
- タスク周期の基本方針（1 ms SIL + 10 ms supervision）は `tsproj` 上でも概ね一致

## 6. 次にやるとよさそうなこと（メモ / GUI 作業中心）

1. GUI で `tsproj` の配線を docs どおり `DriverAdapter` / `ModeManager` 経由へ切り替える
2. GUI で `ControllerCore` / `StateMachineControl` / `ExperimentSequencer` の TMC を再読み込みし、公開 I/O を再同期する
3. `ControllerCore` の `error` 出力が `tsproj` 側で見えることを確認する（`ExperimentLogger` 統合前提）
4. `ExperimentLogger` を `tsproj` に統合する（GUI Mapping + 運用開始）
