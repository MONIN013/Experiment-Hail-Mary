# 未解決課題一覧 — ExperimentHailMary

> **最終更新:** 2026-02-26  
> **目的:** プロジェクト全体の未解決課題を一元管理する。  
> **参照:** [ArchitectureSpec.md](ArchitectureSpec.md) / [ExperimentProcedure.md](ExperimentProcedure.md) / [TechnicalReference.md](TechnicalReference.md)

---

## Critical — 実験実行を阻害

### C1. tsproj Mapping: `modeFlags` 転送が未接続

**影響:** MATLAB から実験が開始できない（`GVL_MODE.modeFlags` の値が ExperimentSequencer に到達しない）。

| 作業 | 内容 | GUI/コード |
|------|------|------------|
| A1 | `GVL_SEQ.modeFlags` に `AT %Q*` を付与 | コード (PLC) |
| A2 | `GVL_MODE.modeFlags` に `AT %I*` を付与 | コード (PLC) |
| A3 | MAIN の `modeFlagsOut` 変数と Q/I リンク追加 | コード (PLC) |
| A4 | tsproj Mapping: `MAIN.modeFlagsOut → GVL_SEQ.modeFlags` を追加 | GUI (tsproj) |
| A5 | PLC ビルド + Activate Configuration | GUI |

> `modeFlags` が `AT %I*` になると ModeManager 側で自動書き戻しが効かなくなる。  
> MODEF_RESET_REQ の自動クリアロジックを MATLAB 側（書込み元がクリア）に移行する必要がある。

### C2. ExperimentLogger の CyclicCaller 未設定

**影響:** ExperimentLogger のインスタンスは tsproj に存在するが、`CyclicCaller` が `#x00000000` のまま。VirtualMotorTask に紐付けないと `CycleUpdate()` が呼ばれず、ロギングが動作しない。

| 作業 | 内容 | GUI/コード |
|------|------|------------|
| 1 | tsproj で ExperimentLogger インスタンスの CyclicCaller を VirtualMotorTask の OTCID に設定 | GUI (tsproj) |
| 2 | ExperimentLogger 向けの全 tsproj Mapping を定義（§C4 参照） | GUI (tsproj) |
| 3 | Activate Configuration + 動作確認 | GUI |

### C3. ControllerCore の TMC Reload 未実施

**影響:** ControllerCore のフィルタ係数パラメータ (`NotchParams`, `LeadParams`, `ResoParams`, `EnableParams`) が Port 351 のシンボルテーブルに表示されない。MATLAB からのシンボルアクセスによるパラメータ注入が不可。

| 作業 | 内容 | GUI/コード |
|------|------|------------|
| 1 | TwinCAT XAE で ControllerCore の TMC Reload を実行 | GUI |
| 2 | Activate Configuration | GUI |
| 3 | `run_ads_discovery_demo.m` で Port 351 シンボルを再確認 | MATLAB |

---

## High — 機能不全またはバグ

### H1. `PIDParams` に `CreateSymbol` 属性が未設定

**影響:** PIDParams のみが ADS シンボルブラウズで見えない。他の `*Params` は `CreateSymbol="true"` が設定済み。

| 作業 | 内容 | 対象ファイル |
|------|------|------------|
| 1 | TMC で `PIDParams` DataArea に `CreateSymbol="true"` を追加 | `ControllerCore/ControllerCore.tmc` |
| 2 | C++ リビルド + TMC Reload + Activate | GUI |

### H2. ExperimentLogger 向け tsproj Mapping 未定義

**影響:** ExperimentLogger の入力ポートに信号が届かない。

必要な Mapping:

```
DriverAdapter.targetTorque                                  →  ExperimentLogger.Inputs.torqueCmd
ExperimentSequencer.refValue                                →  ExperimentLogger.Inputs.refValue
ExperimentSequencer.ffValue                                 →  ExperimentLogger.Inputs.ffValue
ControllerCore.Outputs.controlInput                         →  ExperimentLogger.Inputs.controlInput
ControllerCore.Outputs.error                                →  ExperimentLogger.Inputs.error
VirtualMotorCore.Outputs.VirtualMotor1Outputs.positionOut   →  ExperimentLogger.Inputs.motorPosition
VirtualMotorCore.Outputs.VirtualMotor1Outputs.velocityOut   →  ExperimentLogger.Inputs.motorVelocity
VirtualMotorCore.Outputs.VirtualMotor2Outputs.positionOut   →  ExperimentLogger.Inputs.loadPosition
VirtualMotorCore.Outputs.VirtualMotor2Outputs.velocityOut   →  ExperimentLogger.Inputs.loadVelocity
ModeManager.resetOut                                        →  ExperimentLogger.Inputs.resetReq
```

> `motorTorqueAct` は Phase 1–3 (SIL) ではソースなし。0 埋めで許容するか設計判断が必要（→ H3）。

### H3. `motor_torque_act` の SIL ソース方針未決定

**影響:** ExperimentLogger の `motorTorqueAct` フィールドが常に 0 になる。Phase 1–3 では実機トルク信号がない。

**選択肢:**
1. 0 埋めのまま Phase 4 まで放置
2. VirtualMotorCore 内部のトルク計算値を出力ポートに追加し、暫定接続

### H4. ControllerCore `error` 出力の tsproj 反映確認

**影響:** `ControllerCore.Outputs.error` が tsproj Mapping に含まれていない可能性がある。ExperimentLogger およびデバッグモニタリングに必要。

| 作業 | 内容 |
|------|------|
| 1 | tsproj Mapping で `ControllerCore.Outputs.error → ExperimentLogger.Inputs.error` が存在するか確認 |
| 2 | 不在であれば追加 |

---

## Medium — 設計不整合・改善

### M1. `enablePid` 初期値が `false`（ArchitectureSpec は `true` 想定）

**影響:** ControllerCore のデフォルトで PID が無効。MATLAB 側が明示的に `enablePid = true` を書き込まなければ制御が効かない。

**対象:** `ControllerCore/Module1.cpp` — `memset(&m_EnableParams, 0, ...)` で全 `false` 初期化。

**選択肢:**
1. コードを修正し `enablePid` のデフォルトを `true` にする
2. ArchitectureSpec を修正しデフォルト `false` と明記（MATLAB が常に設定する前提）

### M2. ADS アクセスが ModeManager-only 設計に非準拠

**影響:** MATLAB が `GVL_SEQ` に直接状態制御シンボル (`experimentActive`, `resetReq`, `idx`) を書き込む構造が残存。

**あるべき姿:**
- 状態制御は `GVL_MODE.modeFlags` **のみ** で ModeManager 経由
- テーブル・パラメータ・ログは大容量/別ポートのため直接アクセスを維持

**対象:** MATLAB `+experiment/RunConfig.m` 等の ADS 接続先修正 + ExperimentSequencer の `GVL_SEQ.idx` への直接書込み廃止。

### M3. `LogControl.logging` と ModeManager の連携未定義

**影響:** ExperimentLogger のロギング開始/停止が ModeManager の実験ライフサイクルと連動していない。MATLAB が手動で制御する必要がある。

**選択肢:**
1. ModeManager が `experimentActive` の立ち上がり/立ち下がりで `logging` を自動制御
2. MATLAB が実験シーケンスの一部として明示的に制御（現状維持）

### M4. `load_position` / `load_velocity` のマッピング設計確定

**影響:** tsproj では Motor1 出力を `motorPosition`/`motorVelocity`、Motor2 出力を `loadPosition`/`loadVelocity` にリンクしている。VirtualMotorCore は 2 軸同一パラメータで動作しているため、Motor1 = Motor 側、Motor2 = Load 側 という割り当てが実験上正しいか確認が必要。

---

## Low — 品質改善・ドキュメント整備

### L1. `MODEF_RESET_SEQ_REQ` 非推奨エイリアス未撤去

**対象:** `StateMachineControl/GVLs/GVL_MODE.TcGVL` — `MODEF_RESET_SEQ_REQ` は `MODEF_RESET_REQ` と同値の旧名。MATLAB 側で参照がないことを確認後に削除。

### L2. ArchitectureSpec §4.1 のシンボル名が旧表記

**対象:** `ArchitectureSpec.md` §4.1 — `PIDParams.notch_b0` 等の `notch_*` 接頭辞が残存。実装は `pidB0`, `leadB0` 等に更新済み。

> ArchitectureSpec 更新時に修正予定。

### L3. ArchitectureSpec §4.2 VirtualMotorCore 命名差

**対象:** ArchitectureSpec §4.2 — `VirtualMotorParameter.M`, `.D`, `.Kt` 等の旧名が残存。実装は `VirtualMotor1Parameter.mass`, `.damping`, `.torqueConstant` に更新済み。

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

</details>
