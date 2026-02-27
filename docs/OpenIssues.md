# 未解決課題一覧 — ExperimentHailMary

> **最終更新:** 2026-02-27 (フラグ Set/Clear 責任分担の不整合追記)  
> **目的:** プロジェクト全体の未解決課題を一元管理する。  
> **参照:** [ArchitectureSpec.md](ArchitectureSpec.md) / [ExperimentProcedure.md](ExperimentProcedure.md) / [TechnicalReference.md](TechnicalReference.md)

---

## Critical — 実験実行を阻害

現時点で Critical 項目なし。

---

## High — 機能不全またはバグ

### H4. `modeFlags` が `AT %I*` のため TwinCAT 側でクリア不可

**対象:** `StateMachineControl/GVLs/GVL_MODE.TcGVL` L19, `matlab/+experiment/send_position_command.m` L69/L96/L102/L115  
**現状:** `GVL_MODE.modeFlags` は `AT %I*`（入力リンク）で宣言されており、TwinCAT PLC コードからの書き込みが構造的に不可能。フラグの Set（`MODEF_SERVO_ENABLE`, `MODEF_EXPERIMENT_START_REQ`）も Clear（`0x0000`）も MATLAB が ADS 経由で全て行っている。`MAIN` は `modeFlags` を読み取るのみ（`servoEnableReq`, `experimentStartReq` のデコード）。  
**設計意図との乖離:** フラグの立ち上げ（Set）は MATLAB、クリア（Clear）は TwinCAT 側が行う方針だが、`AT %I*` 制約により TwinCAT がクリアできない。  
**リスク:**
1. MATLAB プロセスがクラッシュまたは ADS 通信が切断した場合、`modeFlags` が `0x0003`（サーボ+実験開始）のまま残留し、TwinCAT 側が安全停止できない
2. `send_position_command.m` の `cleanup_transports` で `modeFlags := 0` を書いているが、プロセス異常終了時にはこのクリーンアップが実行されない

**提案:**
1. `GVL_MODE.modeFlags` から `AT %I*` を除去し、通常の `VAR_GLOBAL` に変更する
2. TwinCAT `MAIN` に `modeFlags` のクリアロジックを追加する（例: 実験完了時に `EXPERIMENT_START_REQ` ビットをクリア）
3. ADS 通信切断検出（ウォッチドッグ/タイムアウト）による `modeFlags` 自動クリア機構の導入を検討する
4. MATLAB 側の cleanup からは `modeFlags := 0` の書き込みを削除し、TwinCAT 側のクリア完了を待つ方式に移行する

### H3. `motor_torque_act` は SIL で 0 埋め（設計決定済み）

**現状:** Phase 1–3 (SIL) では実機トルク信号ソースがないため、ExperimentLogger の `motorTorqueAct` は 0 埋め運用（ArchitectureSpec に明記済み）。

**残課題（改善検討）:**
1. 0 埋めのまま運用継続（現状維持）

---

## Medium — 設計不整合・改善（非推奨/互換性フォールバック）

### M6. `LogControl.logging` 非推奨互換パスが C++ 実装に残存

**対象:** `ExperimentLogger/Module1.cpp` L266  
**現状:** `loggingCmd = (m_Inputs.loggingReq != false) || (m_LogControl.logging != false)` — 旧手動制御 `LogControl.logging` が OR されたまま残っている。`Inputs.loggingReq` による自動制御への移行は完了済み（M3 解決）だが、旧互換パスが残存しているため、意図しない手動操作でロギングが開始されるリスクがある。  
**提案:** `LogControl.logging` の OR 分岐を削除し、`Inputs.loggingReq` のみで制御。合わせて `ExperimentLogger.tmc` の `LogControl.logging` パラメータも撤去する。  
**関連ドキュメント:** `docs/ExperimentLogger.md` L37-39, `docs/TechnicalReference.md` L399/L735/L815, `docs/ExperimentProcedure.md` L210/L216, `docs/ArchitectureSpec.md` L483 — いずれも "(deprecated)" / "(非推奨)" 表記で残っている。コード撤去と同時にドキュメントからも互換制御の記載を削除すること。

### M7. `modeFlags` の UINT/UDINT 型フォールバック

**対象:** `matlab/+experiment/ModeManagerControl.m` L138-153, `matlab/+experiment/send_position_command.m` L449-453/L555-559  
**現状:** `modeflags_type()` は `t.u16` が存在すれば `System.UInt16` を、なければ `System.UInt32` にフォールバックする。`cast_modeflags_value()` も同様に `UInt16` / `UInt32` を動的に切り替える。  
PLC 側 `GVL_MODE.modeFlags` は `UINT` (16bit) で定義されているため、型は一意に決まるはず。`u16` フィールドの有無で判定する互換分岐は不要。  
**提案:** `VirtualMotorSymbols.types` に常に `u16` を含めるか、`modeflags_type()` を `UINT` 固定にし、フォールバック分岐を撤去する。

### M8. `send_position_command.m` の `cleanup_transports` 内デッドコード

**対象:** `matlab/+experiment/send_position_command.m` L182-195  
**現状:** `wrote_stop` を `false` で初期化し、ModeFlags 書き込み成功後に `true` に設定しているが、次の `if ~wrote_stop` ブロックは `wrote_stop = true` の直後にあるため**絶対に到達しない**。`plc_symbols.experimentActive` に `false` を書くフォールバックは実質的にデッドコード。  
**提案:** デッドコードブロックを削除し、`wrote_stop` 変数自体も除去する。

### M9. `send_position_command.m` のログ読取り `logT`/`logIdx` try-catch 互換フォールバック

**対象:** `matlab/+experiment/send_position_command.m` L508-517  
**現状:** `read_upper_logs` 内で `logT`（UInt64 配列）と `logIdx`（UInt32 配列）の読み取りを個別に try-catch で囲んでおり、失敗時に空配列を返すフォールバックがある。コメントは「MATLAB/.NET interop で UInt64[] がマーシャリングできない場合」に言及。  
`VirtualMotorService.m` L462-472, L574-582 にも同一パターンのフォールバックが存在。  
**提案:** 現在使用中の ADS ライブラリで UInt64 マーシャリングが正常動作するか検証し、問題がなければ try-catch フォールバックを撤去。動作しない場合は根本対応（バイト配列での手動デシリアライズ等）を行い、暗黙的な 0 埋めフォールバックを除去する。

### M10. `SymbolTraversal.symbol_identity_key` の多段フォールバック

**対象:** `matlab/+twincat_ads/+internal/SymbolTraversal.m` L111-131  
**現状:** シンボル同一性キーの生成で .NET `RuntimeHelpers.GetHashCode` → `InstancePath`/`InstanceName` → `class(symbol)` の 3 段フォールバックを持つ。最終段 `fallback#<class>` はクラス名のみなので、同一型の異なるシンボルが同一キーとなり、重複除去で取りこぼす可能性がある。  
**提案:** .NET 環境であれば `GetHashCode` が常に利用可能なはず。非 .NET 環境のサポートが不要なら最終段フォールバックを除去し、代わりにエラーとする。必要であれば `class + index` など一意性を保証するキーに改善する。

### M11. `ModeManagerControl.try_read_experiment_active` の二重トランスポートフォールバック

**対象:** `matlab/+experiment/ModeManagerControl.m` L157-175  
**現状:** `experimentActive` の読み取りで、まず `control_transport` で `ctrl.experimentActiveSymbol` を試し、失敗時に `plc_transport` で `plc_symbols.experimentActive` にフォールバックする。`GVL_SEQ.modeFlags` 廃止（解決済み）後は `control_transport` 経由で `GVL_MODE.experimentActive` が常に読めるはず。  
**提案:** plc_transport フォールバックを撤去し、control_transport 単一経路にする。

### M13. MATLAB が `GVL_SEQ.idx` を直接クリアしている（ハンドシェイク迂回）

**対象:** `matlab/+experiment/send_position_command.m` L70, `ExperimentSequencer/POUs/PRG_ExperimentSequencer.TcPOU` L3-4  
**現状:** `send_position_command.m` のリセットシーケンスで `plc_transport.write_scalar(plc_symbols.idx, uint32(0), t.u32)` により MATLAB が Port 853 経由で `GVL_SEQ.idx` を直接 0 に書き込んでいる。一方、TwinCAT 側でも `resetReq = TRUE` 時に `GVL_SEQ.idx := 0` をクリアしている。  
**設計意図との乖離:** クリアは TwinCAT 側が `resetReq` ハンドシェイク経由で行う方針だが、MATLAB が `resetReq` とは独立に直接書き込みを行っており、責任分担が不明確。  
**リスク:** MATLAB のダイレクト書き込みと TwinCAT の resetReq 処理が同一スキャンで競合した場合、タイミング依存の不整合が発生する可能性がある。  
**提案:** `GVL_SEQ.idx` のクリアを `resetReq` ハンドシェイク経由に一本化し、MATLAB の直接書き込み (`write_scalar(plc_symbols.idx, ...)`) を削除する。

### M12. `send_position_command.m` の `read_control_runtime_diag` 内 `u16` フォールバック

**対象:** `matlab/+experiment/send_position_command.m` L449-453  
**現状:** `t.u16` フィールドが存在しなければ `t.u32` にフォールバックして `MAIN.statWord`, `MAIN.ctrlWord` を読んでいる。PLC 側はこれらを `UINT` (16bit) で定義しており、`u32` で読むと型不一致リスクがある。  
**提案:** M7 と同様、型定義を統一してフォールバックを廃止する。

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

### L7. `VirtualMotorService.wait_until_done_streaming` のストリーミング失敗時フォールバック

**対象:** `matlab/+experiment/VirtualMotorService.m` L319-340  
**現状:** ストリーミングログ読み取り中に例外が発生すると、非ストリーミングモード (`wait_until_done`) にフォールバックし、空のログデータを返す。`log_stream_fallback_used` フラグは `host_stats` に記録されるが、ユーザは実験結果にログデータが含まれていないことに気付きにくい。  
**提案:** `log_stream_require_success=true` (デフォルト) の場合は即座にエラーとする現行動作で問題ないが、`false` の場合のフォールバックが暗黙的すぎる。フォールバック時にログ品質を明示する仕組み（結果ファイルに警告フラグを含めるなど）を強化する。

### L8. C++ モジュールの TODO プレースホルダ未記入

**対象:**
- `VirtualMotorCore/VirtualMotorCore.rc` L36/L38 — "TODO: Add legal copyright", "TODO: Add product name"
- `ExperimentLogger/ExperimentLogger.rc` L36/L38 — 同上
- `ControllerCore/ControllerCore.rc` L36/L38 — 同上
- `VirtualMotorCore/Module1.cpp` L125/L152/L165 — "TODO: Add initialization/deinitialization"
- `ControllerCore/Module1.cpp` L134/L150/L177/L190 — 同上

**提案:** リソースファイルの LegalCopyright / ProductName を適切な値に置換する。C++ の TODO コメントは TwinCAT テンプレートの残骸であり、カスタム初期化が不要であれば削除するか、明示的に "No additional initialization needed" に書き換える。

### L10. `MockAdsTransport` が `modeFlags` の TwinCAT 側クリア動作を模擬していない

**対象:** `matlab/tests/fixtures/MockAdsTransport.m` L66  
**現状:** `MockAdsTransport` は `GVL_MODE.resetReq` に `TRUE` が書き込まれた際に即座にクリア＋カウンタ更新を行うが、`modeFlags` に対しては何もしない（書き込まれた値がそのまま残る）。実機で TwinCAT 側が `modeFlags` をクリアする設計に移行した場合、Mock がその振る舞いをシミュレートしないとテストの忠実度が低下する。  
また `resetReq` の即座クリアも実機のスキャンサイクル遅延（≥1ms）を反映しておらず、タイミング依存のバグがテストで検出されない可能性がある。  
**提案:** H4 の修正に合わせて、Mock に `modeFlags` の自動クリア動作を追加する。`resetReq` についても遅延クリアオプション（例: 次回 `read_scalar` まで値を保持）の導入を検討する。

### L9. `send_position_command.m` — `GVL_SEQ.modeFlags` 拒否テストの保守

**対象:** `matlab/tests/unit/TestSendPositionCommand.m` L199-220 `splitPortsRejectsLegacyModeFlagsSymbol`  
**現状:** `GVL_SEQ.modeFlags` を渡すとエラーになることを検証するテスト。`GVL_SEQ.modeFlags` 自体は PLC から削除済み（解決済み課題参照）。テスト自体は防御的で有用だが、テスト名の "Legacy" はもはや存在しないシンボルへの参照。  
**提案:** テストは維持しつつ、名前を `rejectsUnsupportedModeFlagsSymbol` 等に変更し、コメントに経緯を追記する。

---

## 解決済み (参照用)

<details>
<summary>2026-02-27 までに解消された問題一覧</summary>

| 問題 | 解決日 | 内容 |
|------|--------|------|
| M1. `enablePid` 初期値 `false` のままでよいか | 2026-02-27 | `enablePid` デフォルトを `true` に変更（ControllerCore 実装 + tsproj 既定値） |
| M2. ADS アクセスが ModeManager-only 設計に非準拠 | 2026-02-27 | MATLAB 既定の modeFlags 宛先を `GVL_MODE.modeFlags` に統一 |
| M3. `LogControl.logging` と ModeManager の連携未定義 | 2026-02-27 | `ExperimentLogger.Inputs.loggingReq` を追加し、`MAIN.experimentActiveOut` 連動で自動開始/停止 |
| M4. `load_position` / `load_velocity` のマッピング設計確定 | 2026-02-27 | `loadPosition <- ControllerCore.positionRel`、`loadVelocity <- VirtualMotor1Outputs.velocityOut` に確定 |
| M5. ControllerCore に位置オフセット機構を実装 | 2026-02-27 | `positionOffset` / `positionRel` 実装、誤差計算を相対位置化、`positionRelTap` へ移行 |
| `GVL_SEQ.experimentActive` AT リンク不足 | 2026-02-25 | `AT %I*` 追加済み |
| `GVL_SEQ.playbackDone` AT リンク不足 | 2026-02-25 | `AT %Q*` 追加済み |
| `GVL_SEQ.resetReq` AT リンク不足 | 2026-02-25 | `AT %I*` 追加済み |
| `GVL_MODE.experimentActive` AT リンク不足 | 2026-02-25 | `MAIN.experimentActiveOut AT %Q*` で出力 |
| リセット時 `tableLen := 0` 問題 | 2026-02-25 | リセット処理から `tableLen := 0` を除去 |
| ControllerCore `resetReq` 入力なし | 2026-02-25 | `ControllerCoreServices.h` に追加 + エッジ検出実装 |
| ExperimentLogger `resetReq` 入力なし | 2026-02-25 | `ExperimentLoggerServices.h` に追加 + エッジ検出実装 |
| `GVL_DRV.enableTorqueOutput` AT リンク不足 | 2026-02-25 | `AT %I*` 追加済み |
| `kTimestampStepNs` 固定値問題 | 2026-02-26 | タスク周期自動取得に変更 |
| `GVL_MODE.modeFlags` に `AT %I*` なし | 2026-02-26 | `AT %I*` 追加済み |
| MAIN の `modeFlags` 自己クリア問題 | 2026-02-26 | ADS writer がクリアする方式に変更 |
| 主要 tsproj Mapping 18 接続 | 2026-02-26 | tsproj で確認済み |
| modeFlags 単一路化（互換経路廃止） | 2026-02-27 | `GVL_SEQ.modeFlags` を削除し、`GVL_MODE.modeFlags` のみを制御経路として運用 |
| ExperimentLogger の CyclicCaller 未設定 (`C2`) | 2026-02-26 | `CyclicCaller` が `#x02010040` (VirtualMotorTask) に設定済み |
| ExperimentLogger 向け tsproj Mapping 未定義 / `ControllerCore.Outputs.error` 反映未確認 (`H2`+`H4`) | 2026-02-26 | 主要 Mapping および `Outputs.error → Inputs.error` を tsproj で確認済み |
| ControllerCore の TMC Reload 未実施 (`C3`) | 2026-02-26 | `run_ads_discovery_demo.m` 再確認で Port 351 に `PID/Notch/Lead/Reso/EnableParams` が表示されることを確認 |
| `PIDParams` に `CreateSymbol` 属性が未設定 (`H1`) | 2026-02-26 | `ControllerCore/ControllerCore.tmc` で `PIDParams` が `CreateSymbol="true"` になっていることを確認 |

</details>

