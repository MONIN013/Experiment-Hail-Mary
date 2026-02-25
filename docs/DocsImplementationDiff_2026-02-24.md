# docs と現在実装の差分メモ (2026-02-24)

> **最終更新:** 2026-02-25（構成再整理: コード差分と GUI 作業を分離）

## 目的

`docs/ProjectArchitecture.md` / `docs/ArchitectureSpec.md` と、現在の TwinCAT プロジェクト実装の差分を整理する。

## 前提

- `docs/CurrentProject.md` は旧 TE1400 方式の記録であり、現行実装と一致しない箇所がある（意図通り）。
- 現在は「次世代構成」への移行途中。
- コード側の差分と、GUI（TwinCAT XAE）で行うべき作業を明確に分離する。

## 結論（サマリ）

| 区分 | 状態 |
|------|------|
| モジュール部品 | `ExperimentSequencer` / `DriverAdapter` / `ControllerCore` / `VirtualMotorCore` / `ExperimentLogger` のコードはすべて存在する |
| ModeManager 拡張 | `GVL_MODE` に `mode_flags` / `experiment_active` / `experiment_state` を追加済み（コード完了） |
| ExperimentSequencer | `experiment_active` を外部入力として扱い、暫定 SIL ログを `PRG_ExperimentSequencer` に統合済み |
| ControllerCore | docs の最小ループ以上に実装が進んでいる（PID/Lead/Notch/Reso チェーン + enable/bypass） |
| ExperimentLogger | C++ ファイルロガ本体は実装済み（docs では Phase 3 扱い） |
| **tsproj 配線** | **GUI Mapping がまだ docs の最終想定どおりになっていない（§G 参照）** |

---

## 1. コード側の差分 — 実装が docs より進んでいるもの

### 1.1 ControllerCore は「最小ループ」以上を実装済み

`docs/ProjectArchitecture.md` では最小ループ相当の説明だが、実装は以下まで入っている:

- `error` 出力
- PID / Lead / Notch / Reso のチェーン
- 各ブロックの enable/bypass
- `control_input = (FB chain output) + ff_value`

`ArchitectureSpec.md` §2 の仕様と実装は整合しており、docs を追い越す形で先行実装が完了している。

### 1.2 ExperimentLogger は C++ ファイルロガ本体が実装済み

docs では Phase 3 導入扱いだが、実装上は既に以下がある:

- 96 byte 固定長レコード
- 1 ms 前提タイムスタンプ生成
- 8,000 レコードバッファ（約 1 秒分 @ 1 ms）
- `ITcFileAccessAsync` による非同期バイナリ書き込み

詳細は [ExperimentLogger_Summary_2026-02-25.md](ExperimentLogger_Summary_2026-02-25.md) を参照。

### 1.3 ModeManager 拡張はコード側で修正済み

docs では `StateMachineControl` を拡張して以下を扱う想定:

- `mode_flags` / `experiment_active` / `experiment_state`

2026-02-25 時点のコード更新で以下を反映済み:

- `GVL_MODE.mode_flags`
- `GVL_MODE.experiment_active`
- `GVL_MODE.experiment_state`（`IDLE=0 / READY=1 / RUNNING=2 / DONE=3`）
- `MAIN` に `bSeqPlaybackDone` 入力を追加（Sequencer 完了通知受け）

---

## 2. コード側の差分 — docs 方針との軽微な不一致

### 2.1 ExperimentSequencer の責務境界（2026-02-25 解消済み）

docs では `ExperimentSequencer` は `ref/ff/dist` のスカラ出力専任とし、暫定SILログは `GVL_SEQ_LOG` で保持する方針。

2026-02-25 のコード更新で以下を反映済み:

- `GVL_SEQ` から SIL ログ用入力 `control_input AT %I*` / `position_act_log AT %I*` を撤去
- 暫定ログ入力タップを `GVL_SEQ_LOG` 側へ移設
  - `GVL_SEQ_LOG.control_input_tap AT %I*`
  - `GVL_SEQ_LOG.position_act_tap AT %I*`
- `PRG_ExperimentSequencer` の暫定ログ書き込み参照先を `GVL_SEQ_LOG.*_tap` へ更新

これにより、`GVL_SEQ` は docs 方針どおり `ref/ff/dist` のテーブル/状態/スカラ出力に限定された。

### 2.2 暫定 SIL ログの `PRG_ExperimentSequencer` 統合（2026-02-25 解消済み）

- `PRG_SEQ_SILLogger` のロジックを `PRG_ExperimentSequencer` へ統合済み
- `ExperimentSequencer` タスク呼び出しを `PRG_ExperimentSequencer` のみへ整理済み
- `GVL_SEQ_LOG` は引き続き暫定リングバッファとして保持

暫定ログでの `target_torque = control_input + dist_value` 再計算は継続（Phase 3 `ExperimentLogger` 統合までは許容）。

### 2.3 互換エイリアス `TABLE_MAX_N`（2026-02-25 解消済み）

`GVL_SEQ` に残っていた互換用定数 `TABLE_MAX_N` は 2026-02-25 のコード更新で撤去済み。

以後は docs 方針どおり、テーブル長上限は `N_REF_MAX` / `N_FF_MAX` / `N_DIST_MAX` のみを使用する。

---

## 3. 一致している点（現状で問題なし）

- `GVL_SEQ` / `GVL_SEQ_LOG` の命名は docs 方針と一致
- `ExperimentSequencer` のテーブル再生（`ref/ff/dist`、`idx`、`table_len` クランプ、再生完了処理）は概ね docs 方針どおり
- `DriverAdapter` の ST ロジック（`control_input + dist_value`、CW/SW 中継）は docs 方針どおり
- タスク周期の基本方針（1 ms SIL + 10 ms supervision）は `tsproj` 上でも概ね一致

---

## G. GUI 作業が必要な差分（tsproj Mapping / TMC 再読み込み / インスタンス登録）

> 本セクションの項目はすべて TwinCAT XAE GUI での操作が必要であり、コード編集では解決できない。

### G.1 DriverAdapter 経由の配線になっていない

**docs の Phase 1 想定:**

```
ExperimentSequencer → ControllerCore → DriverAdapter → VirtualMotorCore
StateMachineControl(=ModeManager) ↔ DriverAdapter
```

**現状の tsproj マッピング（直結）:**

- `ControllerCore.position_act ← VirtualMotorCore.position_out`
- `ControllerCore.control_input → VirtualMotorCore.current_in`
- `StateMachineControl MAIN.uiCtrlWord/uiStatWord ↔ VirtualMotorCore`

`DriverAdapter` インスタンスは存在するが、配線の本線にまだ入っていない。

**必要な GUI 作業:**
1. `ControllerCore.control_input → DriverAdapter.control_input` へ変更
2. `DriverAdapter.target_torque → VirtualMotorCore.current_in` へ変更
3. `ModeManager ↔ DriverAdapter` の CW/SW 中継を接続
4. `ExperimentSequencer.dist_value → DriverAdapter.dist_value` を接続

### G.2 PLC 間接続（GVL_MODE ↔ GVL_SEQ）の Mapping が未実施

コード側で `GVL_MODE` / `GVL_SEQ` は定義済みだが、PLC プロジェクト間の接続は tsproj の `<Mappings>` で行う必要がある。

**必要な GUI 作業:**
- `GVL_MODE.mode_flags → GVL_SEQ.mode_flags`
- `GVL_MODE.experiment_active → GVL_SEQ.experiment_active`
- `GVL_SEQ.bPlaybackDone → StateMachineControl MAIN.bSeqPlaybackDone`（完了通知）

### G.3 ControllerCore の `error` 出力が tsproj 側で見えていない可能性

コード/TMC には `Outputs.control_input` と `Outputs.error` があるが、tsproj の `ControllerCore` インスタンス定義では `Outputs` の `ByteSize=8`（= `control_input` の 8 bytes のみ）となっている。

**原因の可能性:**
- tsproj 側の TMC 取り込みが古い
- 手動編集/再読み込み不足

**必要な GUI 作業:**
1. TwinCAT XAE で ControllerCore の TMC を再読み込み
2. `Outputs` に `error` (LREAL, 8 bytes) が含まれることを確認（`ByteSize=16` になるはず）

> `ExperimentLogger` 統合時に `ControllerCore.error` を使う前提であるため、先行して対応が望ましい。

### G.4 ExperimentLogger の tsproj 統合（インスタンス化 / タスク割当 / 配線）

`ExperimentLogger` の C++ プロジェクト/コード/TMC は存在するが、tsproj に統合されていない。

**必要な GUI 作業:**
1. ExperimentLogger の TcCOM インスタンス（`ExperimentLogger_Obj1`）を作成
2. VirtualMotorTask (1 ms) へのタスク割り当て
3. 10 本の入力すべてについてマッピングを定義（詳細は [ExperimentLogger_Summary_2026-02-25.md](ExperimentLogger_Summary_2026-02-25.md) §4–5 参照）

### G.5 TMC 再読み込みによる公開 I/O の再同期

以下のモジュールについて、TMC を再読み込みして tsproj 上の I/O 定義を最新化する必要がある:

| モジュール | 再読み込みの理由 |
|-----------|----------------|
| `ControllerCore` | `error` 出力が tsproj に反映されていない可能性（§G.3） |
| `StateMachineControl` | `GVL_MODE` 拡張後の I/O が正しく公開されているか確認 |
| `ExperimentSequencer` | SIL ログ統合後の I/O が正しく公開されているか確認 |

---

## 4. 次にやるとよさそうなこと

### 4.1 コード作業

| # | 作業 | 備考 |
|---|------|------|
| C3 | `ExperimentLogger` の `kTimestampStepNs` パラメータ化 | Phase 4 (125 µs) 移行に備え |
| C4 | MATLAB 側で `LogControl.logging` の ADS 制御を実装 | ExperimentLogger 統合後 |

### 4.2 GUI 作業（TwinCAT XAE）

| # | 作業 | 前提条件 | 対応セクション |
|---|------|---------|---------------|
| G1 | TMC 再読み込み（ControllerCore / StateMachineControl / ExperimentSequencer） | — | §G.3, §G.5 |
| G2 | `ControllerCore.error` 出力が tsproj で見えることを確認 | G1 | §G.3 |
| G3 | tsproj の配線を DriverAdapter / ModeManager 経由へ切り替え | G1 | §G.1 |
| G4 | PLC 間接続（GVL_MODE ↔ GVL_SEQ）の Mapping 実施 | G1 | §G.2 |
| G5 | ExperimentLogger のインスタンス作成 / タスク割り当て / 配線 | G1, G2 | §G.4 |
