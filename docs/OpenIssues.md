# 未解決課題一覧 — ExperimentHailMary

> **最終更新:** 2026-02-26  
> **目的:** プロジェクト全体の未解決課題を一元管理する。  
> **参照:** [ArchitectureSpec.md](ArchitectureSpec.md) / [ExperimentProcedure.md](ExperimentProcedure.md) / [TechnicalReference.md](TechnicalReference.md)

---

## Critical — 実験実行を阻害

現時点で Critical 項目なし。

---

## High — 機能不全またはバグ

### H3. `motor_torque_act` は SIL で 0 埋め（設計決定済み）

**現状:** Phase 1–3 (SIL) では実機トルク信号ソースがないため、ExperimentLogger の `motorTorqueAct` は 0 埋め運用（ArchitectureSpec に明記済み）。

**残課題（改善検討）:**
1. 0 埋めのまま運用継続（現状維持）

---

## Medium — 設計不整合・改善

### M1. `enablePid` 初期値 `false` のままでよいか（仕様変更検討）

**現状:** 実装・ArchitectureSpec ともに `enablePid` のデフォルトは `false` で一致している。MATLAB 側が明示的に `enablePid = true` を書き込まなければ制御が効かない。

**対象:** `ControllerCore/Module1.cpp` — `memset(&m_EnableParams, 0, ...)` で全 `false` 初期化。

**選択肢:**
1. コードを修正し `enablePid` のデフォルトを `true` にする

### M2. ADS アクセスが ModeManager-only 設計に非準拠

**進捗 (2026-02-26):** `RunConfig` / `run_virtualmotor` / `VirtualMotorService` は ModeManager-only 制御へ修正済み。旧主要フローでの `GVL_SEQ` 直接状態制御書込み（`experimentActive`, `resetReq`, `idx`）は廃止。

**進捗 (追記):** `send_position_command.m` / `VirtualMotorService` 間の ModeManager 制御 helper は共通化済み（`experiment.ModeManagerControl`）。主要 MATLAB 単体テストで回帰確認済み。

**残課題:** 補助API/README/デモの整理レベル（重複実装は解消済み）。`M2` を解決済みに移す条件は「主要回帰テスト pass を維持し、運用上の直接状態制御再導入がないこと」。

**あるべき姿:**
- 状態制御は `GVL_MODE.modeFlags` **のみ** で ModeManager 経由
- テーブル・パラメータ・ログは大容量/別ポートのため直接アクセスを維持

**対象（残）:** MATLAB の補助API/デモ/ドキュメントで状態制御経路の一貫性を維持する軽微整理。

### M3. `LogControl.logging` と ModeManager の連携未定義

**影響:** ExperimentLogger のロギング開始/停止が ModeManager の実験ライフサイクルと連動していない。MATLAB が手動で制御する必要がある。

**選択肢:**
1. ModeManager が `experimentActive` の立ち上がり/立ち下がりで `logging` を自動制御、ただしロギング終了はサンプル数から得られる実験終了と同時にModeManagerが行う。
開始はADS、終了はサンプル数で自動制御する方式がシンプルで確実。

### M4. `load_position` / `load_velocity` のマッピング設計確定

**影響:** tsproj では Motor1 出力を `motorPosition`/`motorVelocity`、Motor2 出力を `loadPosition`/`loadVelocity` にリンクしている。VirtualMotorCore は 2 軸同一パラメータで動作しているため、Motor1 = Motor 側、Motor2 = Load 側 という割り当てが実験上正しいか確認が必要。

---

## Low — 品質改善・ドキュメント整備

### L1. `MODEF_RESET_SEQ_REQ` 非推奨エイリアス未撤去

**対象:** `StateMachineControl/GVLs/GVL_MODE.TcGVL` — `MODEF_RESET_SEQ_REQ` は `MODEF_RESET_REQ` と同値の旧名。MATLAB 側で参照がないことを確認後に削除。

### L2. ArchitectureSpec §4.1 旧表記指摘の残骸（清掃）

**現状:** 旧指摘（`PIDParams.notch_b0` 等）は現行 `ArchitectureSpec.md` では解消済み。未解決課題一覧から削除または解決済みへ移動する。

### L3. ArchitectureSpec §4.2 VirtualMotorCore 命名差の旧指摘（清掃）

**現状:** 旧指摘（`VirtualMotorParameter.M`, `.D`, `.Kt` 等）は現行 `ArchitectureSpec.md` では解消済み。未解決課題一覧から削除または解決済みへ移動する。

### L4. 暫定 SIL ログ (`GVL_SEQ_LOG`) 撤去計画

**影響:** Phase 3 の ExperimentLogger 本格運用開始後、GVL_SEQ_LOG リングバッファは不要になる。ExperimentSequencer のメモリ使用量削減のため撤去計画が必要。

### L5. VirtualMotorCore Axis 2 の ADS シンボル公開

**影響:** `VirtualMotor2Inputs`, `controlWord2`, `VirtualMotor2Outputs`, `statusWord2` が Port 351 で公開されているが Axis 2 は未使用。不要な ADS 公開を削減すべき。

### L6. ExperimentLogger の一部 Inputs に不要な `CreateSymbol`

**対象:** `ExperimentLogger.tmc` — `Inputs.torqueCmd`, `Inputs.refValue`, `Inputs.resetReq` に `CreateSymbol="true"` が設定されているが、I/O リンク専用のため ADS 公開は不要。

---

## 解決済み (参照用)

<details>
<summary>2026-02-26 までに解消された問題一覧</summary>

| 問題 | 解決日 | 内容 |
|------|--------|------|
| `GVL_SEQ.experimentActive` AT リンク不足 | 2026-02-25 | `AT %I*` 追加済み |
| `GVL_SEQ.playbackDone` AT リンク不足 | 2026-02-25 | `AT %Q*` 追加済み |
| `GVL_SEQ.resetReq` AT リンク不足 | 2026-02-25 | `AT %I*` 追加済み |
| `GVL_MODE.experimentActive` AT リンク不足 | 2026-02-25 | `MAIN.experimentActiveOut AT %Q*` で出力 |
| リセット時 `tableLen := 0` 問題 | 2026-02-25 | リセット処理から `tableLen := 0` を除去 |
| ControllerCore `resetReq` 入力なし | 2026-02-25 | `ControllerCoreServices.h` に追加 + エッジ検出実装 |
| ExperimentLogger `resetReq` 入力なし | 2026-02-25 | `ExperimentLoggerServices.h` に追加 + エッジ検出実装 |
| `GVL_DRV.enableTorqueOutput` AT リンク不足 | 2026-02-25 | `AT %I*` 追加済み |
| `kTimestampStepNs` 固定値問題 | 2026-02-26 | タスク周期自動取得に変更 |
| `GVL_SEQ.modeFlags` に `AT %Q*` なし | 2026-02-26 | `AT %Q*` 追加済み |
| `GVL_MODE.modeFlags` に `AT %I*` なし | 2026-02-26 | `AT %I*` 追加済み |
| MAIN の `modeFlags` 自己クリア問題 | 2026-02-26 | ADS writer がクリアする方式に変更 |
| 主要 tsproj Mapping 18 接続 | 2026-02-26 | tsproj で確認済み (旧 ModeManagerBugReport §2.1 統合) |
| tsproj Mapping: `modeFlags` 転送未接続 (`C1`) | 2026-02-26 | `GVL_SEQ.modeFlags → GVL_MODE.modeFlags` リンクを tsproj で確認済み |
| ExperimentLogger の CyclicCaller 未設定 (`C2`) | 2026-02-26 | `CyclicCaller` が `#x02010040` (VirtualMotorTask) に設定済み |
| ExperimentLogger 向け tsproj Mapping 未定義 / `ControllerCore.Outputs.error` 反映未確認 (`H2`+`H4`) | 2026-02-26 | 主要 Mapping および `Outputs.error → Inputs.error` を tsproj で確認済み |
| ControllerCore の TMC Reload 未実施 (`C3`) | 2026-02-26 | `run_ads_discovery_demo.m` 再確認で Port 351 に `PID/Notch/Lead/Reso/EnableParams` が表示されることを確認 |
| `PIDParams` に `CreateSymbol` 属性が未設定 (`H1`) | 2026-02-26 | `ControllerCore/ControllerCore.tmc` で `PIDParams` が `CreateSymbol=\"true\"` になっていることを確認（一覧更新漏れを解消） |

</details>
