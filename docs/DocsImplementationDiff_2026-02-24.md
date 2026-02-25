# docs と現在実装の差分メモ (2026-02-24)

## 目的

`docs/ProjectArchitecture.md` / `docs/ArchitectureSpec.md` と、現在の TwinCAT プロジェクト実装の差分をざっくり整理する。

## 前提

- `docs/CurrentProject.md` は旧 TE1400 方式の記録であり、現行実装と一致しない箇所がある（意図通り）。
- 現在は「次世代構成」への移行途中。

## 結論（ざっくり）

- `ExperimentSequencer` / `DriverAdapter` / `ControllerCore` / `VirtualMotorCore` の部品は存在する。
- ただし `tsproj` の実配線はまだ docs の最終想定どおりにはなっていない。
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

### 1.2 ModeManager 拡張（mode_flags / experiment_active）が未実装

docs では `StateMachineControl` を拡張して、少なくとも以下を扱う想定:

- `mode_flags`
- `experiment_active`
- `experiment_state`

現状の `StateMachineControl` は CiA402 の ControlWord/StatusWord 制御が中心で、上記の実験シーケンス用 GVL/IF は未確認（未実装扱い）。

### 1.3 ExperimentLogger のシステム統合が未完

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

### 4.2 `PRG_SEQ_SILLogger` が別 POU として残っている

docs の記述では、暫定ログは `GVL_SEQ_LOG` に保持しつつ `ExperimentSequencer` へ置換していく流れだが、現状は `PRG_SEQ_SILLogger` という独立 POU が残っている。

- `target_torque = control_input + dist_value` をロガ内で再計算
- リングバッファ書き込み

責務分離の最終形（Dist 加算は `DriverAdapter`）に対しては、まだ移行途中。

### 4.3 互換エイリアスが残っている

`GVL_SEQ` に以下の互換用定数が残っている:

- `TABLE_MAX_N`

docs の「`GVL_EXP*` 互換は維持しない」方針と完全一致ではないが、移行補助としては合理的。

## 5. 一致している点（現状でも良い）

- `GVL_SEQ` / `GVL_SEQ_LOG` の命名は docs 方針と一致
- `ExperimentSequencer` のテーブル再生（`ref/ff/dist`、`idx`、`table_len` クランプ、再生完了処理）は概ね docs 方針どおり
- `DriverAdapter` の ST ロジック（`control_input + dist_value`、CW/SW 中継）は docs 方針どおり
- タスク周期の基本方針（1 ms SIL + 10 ms supervision）は `tsproj` 上でも概ね一致

## 6. 次にやるとよさそうなこと（メモ）

1. `tsproj` の配線を docs どおり `DriverAdapter` 経由へ切り替える
2. `StateMachineControl` を `ModeManager` 相当に拡張（`mode_flags`, `experiment_active`）
3. `ControllerCore` の TMC / `tsproj` DataArea を再同期（`error` 出力確認）
4. `ExperimentLogger` を `tsproj` に統合し、暫定 `PRG_SEQ_SILLogger` の役割を縮小/撤去する
