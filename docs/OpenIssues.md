# 未解決課題一覧 — ExperimentHailMary

> **最終更新:** 2026-03-02 (M21 定格電流ベース単位統一, M22 電流制限追加, MATLAB 構成レビュー欄追加、M6–M13/M16/M19/M20 解消反映、D11/D12/D13 I/F整合、MATLAB fail-fast化)  
> **目的:** プロジェクト全体の未解決課題を一元管理する。  
> **参照:** [ArchitectureSpec.md](ArchitectureSpec.md) / [ExperimentProcedure.md](ExperimentProcedure.md) / [TechnicalReference.md](TechnicalReference.md)

---

## Critical — 実験実行を阻害

現時点で Critical 項目なし。

---

## High — 機能不全またはバグ

### H6. `playbackDone` → `loggingReq` のクロスタスク遅延によるログ終端誤差

**対象:** `ExperimentHailMary.tsproj` Mapping、`ExperimentLogger/Module1.cpp` L265、`StateMachineControl/POUs/MAIN.TcPOU` L159  
**現状:** ExperimentLogger の `Inputs.loggingReq` は `MAIN.experimentActiveOut`（PlcTask 10 ms）から I/O Mapping で供給されている。ExperimentSequencer が `playbackDone = TRUE` を発行してからロガーの `loggingReq` が `FALSE` になるまで、以下のラウンドトリップが発生する:

```
ExperimentSequencer (VirtualMotorTask)  ─ playbackDone = TRUE ─►
    I/O Mapping (VirtualMotorTask Out → PlcTask In)            … 最大 10 ms
ModeManager / MAIN (PlcTask 10 ms)     ─ experimentActiveOut = FALSE ─►
    I/O Mapping (PlcTask Out → VirtualMotorTask In)            … 最大 1 ms / 125 µs
ExperimentLogger (VirtualMotorTask)    ─ loggingReq goes FALSE
```

**最悪遅延と余剰サンプル数:**

| フェーズ | 制御周期 | PlcTask | ラウンドトリップ最悪 | 余剰ゼロサンプル |
|---|---|---|---|---|
| Phase 1–3 | 1 ms | 10 ms | ~11 ms | ~11 サンプル |
| Phase 4 | 125 µs (8 kHz) | 10 ms | ~10.125 ms | **~81 サンプル** |

ExperimentSequencer は `playbackRunning := FALSE` と同時に出力を 0 にするため、余剰サンプルのデータ値自体はゼロだが、ログ長が `tableLen` と一致しなくなり、MATLAB 側でのトリム処理が必要になる。8 kHz 運用で 81 サンプル（約 10 ms）の不定長テールは FRF 解析のウィンドウ設計に影響する。

**stateTask を高速化できない理由:** ModeManager は CiA 402 状態遷移・watchdog・ADS ハンドシェイクなど低頻度ロジックを担当しており、125 µs で回す必要性がない。PlcTask を高速化するとリアルタイム負荷が増加し、Phase 4 の EtherCAT DC 同期設計に影響を与える。

**提案 — 同一タスク内 fast-path 停止信号:**

ExperimentSequencer の `GVL_SEQ.playbackDone` を同一 VirtualMotorTask 内で ExperimentLogger に直接マッピングし、ModeManager ラウンドトリップを迂回する。

1. ExperimentLogger に `Inputs.playbackDone` (`BOOL`) を追加する（`ExperimentLoggerServices.h`, `ExperimentLogger.tmc`）。
2. tsproj に `GVL_SEQ.playbackDone → ExperimentLogger.Inputs.playbackDone` マッピングを追加する（同一タスク内マッピング＝同一スキャンで反映）。
3. `Module1.cpp` の記録判定を変更:
   ```cpp
   // 現行: loggingCmd のみ
   const bool loggingCmd = (m_Inputs.loggingReq != false) || (m_LogControl.logging != false);
   // 改修: playbackDone で即時抑止
   const bool loggingCmd = m_Inputs.loggingReq && !m_Inputs.playbackDone;
   ```
4. `loggingReq`（ModeManager 経由）はファイルのオープン/クローズ制御に引き続き使用する。`playbackDone` はレコード書き込みの即時停止のみを担当する。これにより ModeManager の状態管理権限を維持しつつ、ログ終端の精度を 1 スキャン以内に保証する。

**代替案（不採用理由）:**

- **(B) ExperimentSequencer が `loggingReq` を直接駆動:** ModeManager の状態管理責務と衝突し、層分離の原則に反する。
- **(C) Logger が `tableLen` / `idx` を受け取り自前カウント:** I/O ポート追加 + カウントロジックの重複。Sequencer の内部状態に Logger が依存する結合が生じる。
- **(D) PlcTask を 1 ms に高速化:** CiA 402 やハンドシェイクに不必要。RT 負荷増大。

**関連:** M6（`LogControl.logging` 非推奨互換パス）、ExperimentProcedure.md §6 の実験完了フロー

---

## Medium — 設計不整合・改善（非推奨/互換性フォールバック）

### ~~M6. `LogControl.logging` 非推奨互換パスが C++ 実装に残存~~ → 解消
**解消 (2026-02-27):** `ExperimentLogger` の記録判定を `Inputs.loggingReq` 単独に統一し、`LogControl.logging` を Services/TMC/C++ 実装から撤去。

**対象:** `ExperimentLogger/Module1.cpp` L266  
**現状:** `loggingCmd = (m_Inputs.loggingReq != false) || (m_LogControl.logging != false)` — 旧手動制御 `LogControl.logging` が OR されたまま残っている。`Inputs.loggingReq` による自動制御への移行は完了済み（M3 解決）だが、旧互換パスが残存しているため、意図しない手動操作でロギングが開始されるリスクがある。  
**提案:** `LogControl.logging` の OR 分岐を削除し、`Inputs.loggingReq` のみで制御。合わせて `ExperimentLogger.tmc` の `LogControl.logging` パラメータも撤去する。  
**関連ドキュメント:** `docs/module-specs/ExperimentLogger.md` L37-39, `docs/TechnicalReference.md` L399/L735/L815, `docs/ExperimentProcedure.md` L210/L216, `docs/ArchitectureSpec.md` L483 — いずれも "(deprecated)" / "(非推奨)" 表記で残っている。コード撤去と同時にドキュメントからも互換制御の記載を削除すること。

### ~~M7. `modeFlags` の UINT/UDINT 型フォールバック~~ → 解消
**解消 (2026-02-27):** `modeflags_type()` を `UINT` (`u16`) 固定化し、`UInt32` 互換フォールバックを撤去。

**対象:** `matlab/+experiment/ModeManagerControl.m` L138-153, `matlab/+experiment/send_position_command.m` L449-453/L555-559  
**現状:** `modeflags_type()` は `t.u16` が存在すれば `System.UInt16` を、なければ `System.UInt32` にフォールバックする。`cast_modeflags_value()` も同様に `UInt16` / `UInt32` を動的に切り替える。  
PLC 側 `GVL_MODE.modeFlags` は `UINT` (16bit) で定義されているため、型は一意に決まるはず。`u16` フィールドの有無で判定する互換分岐は不要。  
**提案:** `VirtualMotorSymbols.types` に常に `u16` を含めるか、`modeflags_type()` を `UINT` 固定にし、フォールバック分岐を撤去する。

### ~~M8. `send_position_command.m` の `cleanup_transports` 内デッドコード~~ → 解消
**解消 (2026-02-27):** 旧 stop 書込み互換パスのデッドコードを削除済み（現行実装は modeFlags/reset handshake のみ）。

**対象:** `matlab/+experiment/send_position_command.m` L182-195  
**現状:** `wrote_stop` を `false` で初期化し、ModeFlags 書き込み成功後に `true` に設定しているが、次の `if ~wrote_stop` ブロックは `wrote_stop = true` の直後にあるため**絶対に到達しない**。`plc_symbols.experimentActive` に `false` を書くフォールバックは実質的にデッドコード。  
**提案:** デッドコードブロックを削除し、`wrote_stop` 変数自体も除去する。

### ~~M9. `send_position_command.m` のログ読取り `logT`/`logIdx` try-catch 互換フォールバック~~ → 解消
**解消 (2026-02-27):** `send_position_command` / `VirtualMotorService` の `logT` / `logIdx` フォールバックを撤去し、読取失敗時は明示エラー化。

**対象:** `matlab/+experiment/send_position_command.m` L508-517  
**現状:** `read_upper_logs` 内で `logT`（UInt64 配列）と `logIdx`（UInt32 配列）の読み取りを個別に try-catch で囲んでおり、失敗時に空配列を返すフォールバックがある。コメントは「MATLAB/.NET interop で UInt64[] がマーシャリングできない場合」に言及。  
`VirtualMotorService.m` L462-472, L574-582 にも同一パターンのフォールバックが存在。  
**提案:** 現在使用中の ADS ライブラリで UInt64 マーシャリングが正常動作するか検証し、問題がなければ try-catch フォールバックを撤去。動作しない場合は根本対応（バイト配列での手動デシリアライズ等）を行い、暗黙的な 0 埋めフォールバックを除去する。

### ~~M10. `SymbolTraversal.symbol_identity_key` の多段フォールバック~~ → 解消
**解消 (2026-02-27):** `fallback#<class>` を廃止し、同一性キー生成不能時は `identityUnavailable` エラーを送出。

**対象:** `matlab/+twincat_ads/+internal/SymbolTraversal.m` L111-131  
**現状:** シンボル同一性キーの生成で .NET `RuntimeHelpers.GetHashCode` → `InstancePath`/`InstanceName` → `class(symbol)` の 3 段フォールバックを持つ。最終段 `fallback#<class>` はクラス名のみなので、同一型の異なるシンボルが同一キーとなり、重複除去で取りこぼす可能性がある。  
**提案:** .NET 環境であれば `GetHashCode` が常に利用可能なはず。非 .NET 環境のサポートが不要なら最終段フォールバックを除去し、代わりにエラーとする。必要であれば `class + index` など一意性を保証するキーに改善する。

### ~~M11. `ModeManagerControl.try_read_experiment_active` の二重トランスポートフォールバック~~ → 解消
**解消 (2026-02-27):** `experimentActive` 読取を `control_transport` 単一路化し、失敗時は明示エラー化。

**対象:** `matlab/+experiment/ModeManagerControl.m` L157-175  
**現状:** `experimentActive` の読み取りで、まず `control_transport` で `ctrl.experimentActiveSymbol` を試し、失敗時に `plc_transport` で `plc_symbols.experimentActive` にフォールバックする。`GVL_SEQ.modeFlags` 廃止（解決済み）後は `control_transport` 経由で `GVL_MODE.experimentActive` が常に読めるはず。  
**提案:** plc_transport フォールバックを撤去し、control_transport 単一経路にする。

### ~~M13. MATLAB が `GVL_SEQ.idx` を直接クリアしている（ハンドシェイク迂回）~~ → 解消
**解消 (2026-02-27):** `send_position_command` から `GVL_SEQ.idx` 直接クリアを削除し、reset handshake に一本化。

**対象:** `matlab/+experiment/send_position_command.m` L70, `ExperimentSequencer/POUs/PRG_ExperimentSequencer.TcPOU` L3-4  
**現状:** `send_position_command.m` のリセットシーケンスで `plc_transport.write_scalar(plc_symbols.idx, uint32(0), t.u32)` により MATLAB が Port 853 経由で `GVL_SEQ.idx` を直接 0 に書き込んでいる。一方、TwinCAT 側でも `resetReq = TRUE` 時に `GVL_SEQ.idx := 0` をクリアしている。  
**設計意図との乖離:** クリアは TwinCAT 側が `resetReq` ハンドシェイク経由で行う方針だが、MATLAB が `resetReq` とは独立に直接書き込みを行っており、責任分担が不明確。  
**リスク:** MATLAB のダイレクト書き込みと TwinCAT の resetReq 処理が同一スキャンで競合した場合、タイミング依存の不整合が発生する可能性がある。  
**提案:** `GVL_SEQ.idx` のクリアを `resetReq` ハンドシェイク経由に一本化し、MATLAB の直接書き込み (`write_scalar(plc_symbols.idx, ...)`) を削除する。

### ~~M12. `send_position_command.m` の `read_control_runtime_diag` 内 `u16` フォールバック~~ → 解消
**解消 (2026-02-27):** `MAIN.statWord`/`ctrlWord`/`driveState` の読取型を `u16` 固定化し、`u32` fallback を撤去。

**対象:** `matlab/+experiment/send_position_command.m` L449-453  
**現状:** `t.u16` フィールドが存在しなければ `t.u32` にフォールバックして `MAIN.statWord`, `MAIN.ctrlWord` を読んでいる。PLC 側はこれらを `UINT` (16bit) で定義しており、`u32` で読むと型不一致リスクがある。  
**提案:** M7 と同様、型定義を統一してフォールバックを廃止する。


### ~~M16. VirtualMotor の `torqueConstant` パラメータと `ratedTorque` の関係整理~~ → 解消
**解消 (2026-02-27):** `torqueConstant` を VirtualMotorCore/tsproj/MATLAB 契約から削除し、`ratedTorque` に一本化。

**対象:** `VirtualMotorCore/VirtualMotorCoreServices.h`, `VirtualMotorCore/Module1.cpp`  
**現状:** 旧方式では入力が `currentIn` [A] であったため `torqueConstant` [N·m/A] が必要だった。D11 で入力が `targetTorque` [‰ rated] に変更されるため、入力→内部 Nm 変換は `ratedTorque` で行う。`torqueConstant` の役割を再検討する必要がある。  
**提案:**  
- (A) `torqueConstant` を廃止し、`ratedTorque` に一本化。電流指令モードは将来対応時に再追加  
- (B) `torqueConstant` を保持し、内部シミュレーションの物理定数として使用。`targetTorque` 入力の変換には使わない  
**関連:** D11, [module-specs/VirtualMotorCore.md](module-specs/VirtualMotorCore.md) §2.3

### M17. ExperimentLogger の `loadPosition` マッピング元変更の検証

**対象:** `ExperimentHailMary.tsproj` Mapping, `ExperimentLogger/ExperimentLoggerServices.h`  
**現状:** D12 により `loadPosition` のマッピング元が `ControllerCore.Outputs.positionRel` から `DriverAdapter.positionRel` に変更される。tsproj の Mapping 整合性を確認する必要がある。  
**進捗 (2026-02-27):** PLC先行適用として `ExperimentHailMary.tsproj` のマッピングを `DriverAdapter` 出力基準に更新済み。`loadPosition <- GVL_DRV.positionRel`、`loadVelocity <- GVL_DRV.velocityAct`、`motorCurrentAct <- GVL_DRV.currentAct` を設定。VirtualMotorCore 側の新I/F反映完了後に最終統合確認を行う。  
**提案:** 実装時に tsproj Mapping を更新し、ADS Discovery で接続を確認する。  
**関連:** D12, M4 (解消済み)

### M21. 定格電流ベース単位統一 — `RATED_CURRENT=1.2A`, `rated_torque` → `rated_current`

**対象:** DriverAdapter `GVL_DRV`, MATLAB `RunConfig`/`VirtualMotorService`/`simulate_position`/`preload_eval`/`write_vm_params`, VirtualMotorCore デフォルト定数, ドキュメント全般  
**現状 (実装済み 2026-03-02):** 旧構成は `RATED_CURRENT=0.318 A` / `ratedTorque=0.318 Nm` で運用していた。MATLAB は `rated_torque` パラメータ名で VirtualMotor に注入していた。ControllerCore/ExperimentSequencer の出力はドキュメント上 [Nm] だが kt=1 前提で [A] と数値同一であった。  
**設計決定:** kt=1 を維持し、`RATED_CURRENT=1.2 A` / `ratedTorque=1.2 Nm` に変更。VirtualMotor 外では `rated_torque` を使用せず `rated_current` に統一。制御チェーンの単位表記を [A] に統一。  
**変更内容:**

| コンポーネント | 変更 |
|---|---|
| `GVL_DRV` | `RATED_CURRENT := 1.2`, `RATED_CURRENT_INV_X1000 := 1000.0 / 1.2`, `RATED_CURRENT_DIV_1000 := 1.2 / 1000.0` |
| `VirtualMotorCore/Module1.cpp` | `kDefaultRatedTorqueNm = 1.2` |
| `RunConfig.m` | `rated_torque` → `rated_current` (default `1.2`) |
| `write_vm_params.m` | `params.rated_torque` → `params.rated_current` |
| `VirtualMotorService.m` | `cfg.rated_torque` → `cfg.rated_current` |
| `simulate_position.m` | `cfg.rated_torque` → `cfg.rated_current` |
| `preload_eval.m` | `rated_torque` → `rated_current` |
| `run_position_command_demo.m` | `kt` → `rated_current` |
| ドキュメント | `[Nm]` → `[A]` (controlInput, distValue, ffValue, ffTable, distTable), `0.318` → `1.2` |

**残タスク:** ControllerCore `ControllerCoreServices.h` のコメント内 [Nm] 表記を [A] に修正（機能変更なし）。  
**関連:** M16 (解消), D11

### M22. DriverAdapter / VirtualMotorCore への電流制限追加

**対象:** DriverAdapter `GVL_DRV`/`PRG_DriverAdapter`, VirtualMotorCore `Module1.cpp`/`VirtualMotorCoreServices.h`/`VirtualMotorCore.tmc`, MATLAB `RunConfig`/`VirtualMotorService`/`write_vm_params`/`VirtualMotorSymbols`  
**現状 (実装済み 2026-03-02):** 旧構成では DriverAdapter は INT 型の範囲 [-32768, 32767] でのみクランプ（物理的制限なし）。VirtualMotorCore は `tauLimit` [Nm] でシミュレーション内飽和 + Fault を実施していた。  
**設計決定:**

1. **DriverAdapter — `MAX_CURRENT_A` (Build 時定数):**  
   `GVL_DRV.MAX_CURRENT_A := 1.5` [A] を追加。`PRG_DriverAdapter` で `targetCurrentA` を `±MAX_CURRENT_A` に ‰変換**前**にクランプ。INT 飽和 [-32768, 32767] は型安全のため残置。

2. **VirtualMotorCore — `maxPermille` (ADS 注入パラメータ):**  
   `ST_VirtualMotorParams.maxPermille` (`double`, デフォルト `0.0` = 無制限) を追加。`StepVirtualMotor` の先頭で `|targetTorquePermille| > maxPermille` チェック。超過時 `internalFault = true` → FAULT 遷移。既存の `tauLimit` (Nm ベース飽和 + Fault) はそのまま維持。

**変更内容:**

| コンポーネント | 変更 |
|---|---|
| `GVL_DRV` | `MAX_CURRENT_A : LREAL := 1.5` 追加 |
| `PRG_DriverAdapter` | `targetCurrentA := clamp(targetCurrentA, ±MAX_CURRENT_A)` を ‰変換前に追加 |
| `VirtualMotorCoreServices.h` | `ST_VirtualMotorParams` に `double maxPermille` フィールド追加 |
| `Module1.cpp` | `StepVirtualMotor` に maxPermille チェック追加 |
| `VirtualMotorCore.tmc` | `maxPermille` SubItem 追加, BitSize 448→512 |
| `RunConfig.m` | `max_permille` プロパティ追加 (default `0.0`) |
| `VirtualMotorSymbols.m` | `maxPermille` シンボル・プローブ追加 |
| `VirtualMotorService.m` | `vmParams.maxPermille` 書込み追加 |
| `write_vm_params.m` | `maxPermille` ADS 書込み追加 |
| ドキュメント | DriverAdapter.md §3/§5, VirtualMotorCore.md §2/§4/§7, TechRef §3/§4, ArchSpec §2B |

**設計根拠:**
- `MAX_CURRENT_A` は Build 時定数: モーター物理仕様に依存し、ドライバ変更時に `RATED_CURRENT` と同時に再設定。実験ごとの動的変更は不要。
- `maxPermille` は ADS 注入パラメータ: 実験条件に応じた入力レベル制限として柔軟に設定可能。DriverAdapter の故障・暴走に対する二重保護として機能。
- `tauLimit` 維持: VirtualMotor 内部の Nm 飽和は物理シミュレーション精度のため残す。`maxPermille` は入力レベルの保護。

**関連:** M21, D11

### ~~M19. ControllerCore の `positionRel` 出力が D12「廃止」にもかかわらず残存~~ → 解消
**解消 (2026-02-27):** `ControllerCore.Outputs.positionRel` を Services/TMC/tsproj/実装から撤去し、`GVL_SEQ_LOG.positionRelTap` は `GVL_DRV.positionRel` へ統一。

**対象:** `ControllerCore/ControllerCoreServices.h` L109 (`Module1Outputs.positionRel`)、`ControllerCore/Module1.cpp` L210  
**現状:** D12 の設計決定では「ControllerCore の `positionOffset` / `positionRel` 出力は廃止」とされている（ArchitectureSpec §2.3 D12 移行注記）。しかし実装では:
```cpp
m_Outputs.positionRel = m_Inputs.positionAct;  // 単なるパススルー
```
が残存し、`Module1Outputs` 構造体にも `double positionRel;` フィールドが存在する。  
さらに tsproj Mapping（TechRef §8.8）で `GVL_SEQ_LOG.positionRelTap ← ControllerCore.Outputs.positionRel` と `ExperimentLogger.Inputs.loadPosition ← ControllerCore.Outputs.positionRel` のリンクが引き続き使用されている。  
**影響:** D12 の設計意図（相対位置化は DriverAdapter に一元化）と実装が矛盾。ControllerCore の `positionRel` は入力のパススルーに過ぎず、DriverAdapter の `positionRel`（相対位置化済み）とは異なる値になりうる。入力が未更新の場合、Logger に誤った値が記録される。  
**提案:** tsproj Mapping を `GVL_DRV.positionRel` 基準に更新した上で、ControllerCore の `positionRel` 出力と関連コードを撤去する。TMC および tsproj の Data Area 定義も同時に変更すること。  
**関連:** D12, M17, M18

### ~~M20. VirtualMotorCore の I/O 型が CiA 402 の符号付き型と不一致~~ → 解消
**解消 (2026-02-27):** `targetTorque/torqueActualValue` を `INT`、`position/velocityActualValue` を `DINT` の符号付き型に統一。

**対象:** `VirtualMotorCore/VirtualMotorCoreServices.h` — `ST_VirtualMotorOutputs`, `ST_VirtualMotorInputs`  
**現状:** CiA 402 では以下の符号付き型が規定されている:
- `positionActualValue`: INT32 (DINT, 符号付き)
- `velocityActualValue`: INT32 (DINT, 符号付き)
- `torqueActualValue`: INT16 (INT, 符号付き)
- `targetTorque`: INT16 (INT, 符号付き)

しかし VirtualMotorCore の C++ 実装では:
- `ST_VirtualMotorOutputs.positionActualValue`: `DWORD` (UDINT, **符号なし** 32bit)
- `ST_VirtualMotorOutputs.velocityActualValue`: `DWORD` (UDINT, **符号なし** 32bit)
- `ST_VirtualMotorOutputs.torqueActualValue`: `WORD` (UINT, **符号なし** 16bit)
- `ST_VirtualMotorInputs.targetTorque`: `WORD` (UINT, **符号なし** 16bit)

DriverAdapter 側 GVL は正しく符号付き型 (`DINT`, `DINT`, `INT`, `INT`) で宣言されている。  
**影響:** `SaturatingRoundToDint` が `LONG` (符号付き) を返し `DWORD` (符号なし) に代入する暗黙変換は、ビットパターンの転送上は問題ないが、TMC 型定義で unsigned として公開されると ADS Discovery やデバッグツールで負の値が巨大な正の値として表示される。  
**提案:** `ST_VirtualMotorOutputs` / `ST_VirtualMotorInputs` の型を CiA 402 準拠の符号付き型に変更する:
- `DWORD → LONG` (positionActualValue, velocityActualValue)
- `WORD → SHORT` (torqueActualValue, targetTorque)
TMC の `<SubItem>` 定義も併せて更新する。  
**関連:** D11

---

## Low — 品質改善・ドキュメント整備

### L4. 暫定 SIL ログ (`GVL_SEQ_LOG`) 撤去計画

**影響:** Phase 3 の ExperimentLogger 本格運用開始後、GVL_SEQ_LOG リングバッファは不要になる。ExperimentSequencer のメモリ使用量削減のため撤去計画が必要。

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


### L9. ArchitectureSpec.md 内の D12 反映漏れ（positionRel の接続元）
**対象:** `docs/ArchitectureSpec.md` §3.9  
**現状:** §3.9 の ASCII 接続マップ図で `position_act ◄──────── VirtualMotorCore (Load 側 1慣性近似)` と記載されているが、§3.4 は D12 に基づき `DriverAdapter.positionRel → ControllerCore.position_act` に更新済み。同一ドキュメント内で §3.4 と §3.9 が矛盾している。  
**提案:** §3.9 の図を D12 反映後のフローに更新する。

### L10. ExperimentLogger module-spec のマッピングソースが D12/D13 前

**対象:** `docs/module-specs/ExperimentLogger.md` — Mapping (SIL) セクション  
**現状:**
- `loadPosition <- ControllerCore.Outputs.positionRel` → D12: `DriverAdapter.positionRel` に変更すべき
- `motorCurrentAct` が「SIL: unconnected (0)」→ D13: `DriverAdapter.currentAct` に接続済み
- `loadVelocity <- VirtualMotorCore.Outputs.VirtualMotor1Outputs.velocityOut` → D11: `velocityActualValue` (+ DriverAdapter 変換後は `GVL_DRV.velocityAct`)

**提案:** M17 の PLC 先行更新に合わせて module-spec のマッピング記述を更新する。  
**関連:** M17, M18, D12, D13

### L11. DriverAdapter module-spec の変数名不一致 (`currentActualValue` vs `torqueActualValue`)

**対象:** `docs/module-specs/DriverAdapter.md` §5.1 疑似コード、§8 信号フロー図  
**現状:** 疑似コードで `GVL_DRV.currentActualValue` と記載されているが、実装 (`GVL_DRV.TcGVL`, `PRG_DriverAdapter.TcPOU`) では `GVL_DRV.torqueActualValue` を使用している。§8 の信号フロー図も `currentActualValue (INT)` と旧名が残っている。  
**提案:** `currentActualValue` → `torqueActualValue` に統一する。  
**関連:** D11

### L15. MATLAB 構成レビュー（2026-03-02）

**対象:** `matlab/+experiment/`, `matlab/+twincat_ads/`, `matlab/README.md`, `docs/MatlabSpec.md`, `.gitignore`  
**現状:** MATLAB 層は `+experiment` / `+twincat_ads` への分離自体はできているが、構成全体としては以下の設計負債が残っている。

- `send_position_command.m` と `VirtualMotorService.run()` が reset handshake、table 書込み、modeFlags 制御、完了待ち、ログ読出しまでほぼ同じ実験実行フローを別実装で保持している。
- 設定値が `SystemConfig`, `RunConfig`, 各関数のローカル default, デモスクリプトに分散しており、`851/852/853/351`, `LOG_N=200000`, `TABLE_MAX_N=100000`, `done_timeout_s=30.0`, `reset_timeout_s=5.0` などが多重定義されている。
- `VirtualMotorSymbols` が ADS シンボル契約、required probe、型定義、既定シンボル名を同時に抱えており、契約定義と運用都合が分離されていない。
- `ModeManagerControl` が symbol 解決 helper に加えて heartbeat policy、状態定数、done 判定、`pause(0.01)` ポーリング間隔といった実行 policy まで内包している。
- `matlab/README.md` と `docs/MatlabSpec.md` に実装との差分がある。例として README には現状存在しない `run_preload_and_plot.m` が残存し、`run_position_command_demo.m` / `MatlabSpec.md` は `Kp=180` 前提の記述だが実装は `Kp=90`、`duration_s=3.0` になっている。
- `matlab/simulink/` 配下に追跡対象の `.slx` と生成物が同居している一方、repo の `.gitignore` には MATLAB / Simulink 向けの除外規則がなく、ソースレビューと生成物の境界が弱い。

**影響:** 現状の機能不全ではないが、新規実験追加・PLC ポート変更・ModeManager 契約追加のたびに変更点が広がりやすい。仕様の単一ソースが崩れ、README/Spec を参照した運用判断を誤るリスクがある。  
**提案:**

1. 実験実行フローを 1 つの中核 API に集約し、`send_position_command` は軽量ラッパー、`VirtualMotorService` は高レベル orchestration に責務を限定する。
2. 設定値を「環境固定値」「仕様固定値」「実験条件」に分離し、公開 API の default を一箇所に寄せる。
3. `VirtualMotorSymbols` / `ModeManagerControl` から policy と契約定義を切り離し、symbol contract と runtime behavior を分離する。
4. `matlab/README.md` と `docs/MatlabSpec.md` を現実装に同期し、デモ条件 (`Kp`, `duration_s`) を単一ソース化する。
5. `matlab/simulink/` と `matlab/results/` の役割を明文化し、`.gitignore` に MATLAB / Simulink 生成物除外を追加する。

**関連:** L4, L7, `matlab/+experiment/send_position_command.m`, `matlab/+experiment/VirtualMotorService.m`, `matlab/+experiment/RunConfig.m`, `matlab/+experiment/SystemConfig.m`

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
| H4. `modeFlags` が `AT %I*` のため TwinCAT 側でクリア不可 | 2026-02-27 | `modeFlags` を通常 `VAR_GLOBAL` 化、`MAIN` に完了時 start bit クリアと heartbeat watchdog (`hostHeartbeatCounter`, timeout=500ms) を実装。通信断時は PLC が `modeFlags`/`experimentActive` を安全側クリア |
| H5. リセット後 `experimentActive` / `experimentState` が即座にクリアされない | 2026-02-27 | `resetEdge` で `GVL_MODE.experimentActive := FALSE` を即時実行。`send_position_command`/`VirtualMotorService` の `wait_for_reset_idle` タイムアウトは warning から error に変更 |
| `GVL_SEQ.experimentActive` AT リンク不足 | 2026-02-25 | `AT %I*` 追加済み |
| `GVL_SEQ.playbackDone` AT リンク不足 | 2026-02-25 | `AT %Q*` 追加済み |
| `GVL_SEQ.resetReq` AT リンク不足 | 2026-02-25 | `AT %I*` 追加済み |
| `GVL_MODE.experimentActive` AT リンク不足 | 2026-02-25 | `MAIN.experimentActiveOut AT %Q*` で出力 |
| リセット時 `tableLen := 0` 問題 | 2026-02-25 | リセット処理から `tableLen := 0` を除去 |
| ControllerCore `resetReq` 入力なし | 2026-02-25 | `ControllerCoreServices.h` に追加 + エッジ検出実装 |
| ExperimentLogger `resetReq` 入力なし | 2026-02-25 | `ExperimentLoggerServices.h` に追加 + エッジ検出実装 |
| `GVL_DRV.enableCurrentOutput` AT リンク不足 | 2026-02-25 | `AT %I*` 追加済み |
| `kTimestampStepNs` 固定値問題 | 2026-02-26 | タスク周期自動取得に変更 |
| `GVL_MODE.modeFlags` に `AT %I*` なし | 2026-02-26 | `AT %I*` 追加済み |
| MAIN の `modeFlags` 自己クリア問題 | 2026-02-26 | ADS writer がクリアする方式に変更 |
| 主要 tsproj Mapping 18 接続 | 2026-02-26 | tsproj で確認済み |
| modeFlags 単一路化（互換経路廃止） | 2026-02-27 | `GVL_SEQ.modeFlags` を削除し、`GVL_MODE.modeFlags` のみを制御経路として運用 |
| ExperimentLogger の CyclicCaller 未設定 (`C2`) | 2026-02-26 | `CyclicCaller` が `#x02010040` (VirtualMotorTask) に設定済み |
| ExperimentLogger 向け tsproj Mapping 未定義 / `ControllerCore.Outputs.error` 反映未確認 (`H2`+`H4`) | 2026-02-26 | 主要 Mapping および `Outputs.error → Inputs.error` を tsproj で確認済み |
| ControllerCore の TMC Reload 未実施 (`C3`) | 2026-02-26 | `run_ads_discovery_demo.m` 再確認で Port 351 に `PID/Notch/Lead/Reso/EnableParams` が表示されることを確認 |
| `PIDParams` に `CreateSymbol` 属性が未設定 (`H1`) | 2026-02-26 | `ControllerCore/ControllerCore.tmc` で `PIDParams` が `CreateSymbol="true"` になっていることを確認 |
| M18. TechnicalReference.md の D11/D12/D13 反映漏れ | 2026-02-27 | §2.1, §2.4, §3.1, §3.2, §4.2, §4.3, §7.1, §7.5, §7.6, §8.3, §8.6, §8.8 を D11/D12/D13 に合わせて一括更新 |
| L9. ArchitectureSpec §3.9 接続マップ図 | 2026-02-27 | `position_act ← VirtualMotorCore` を `position_act ← DriverAdapter.positionRel` に更新 |
| L10. ExperimentLogger module-spec マッピング | 2026-02-27 | `loadPosition/loadVelocity/motorCurrentAct` を DriverAdapter 経由に更新 |
| L11. DriverAdapter module-spec 変数名不一致 | 2026-02-27 | `currentActualValue` → `torqueActualValue` に統一 |
| L12. ExperimentProcedure §4 `enableCurrentOut` 不一致 | 2026-02-27 | トルクゲート記述を MAIN `CASE modeState` による状態ごとの制御に更新 |
| L13. TechnicalReference §1.2 リセット疑似コード | 2026-02-27 | レベルトリガからエッジ検出方式に更新 |
| L14. ExperimentProcedure §3.3 リセットテーブル | 2026-02-27 | ExperimentSequencer の検出方式を「エッジ」に更新、M14 欄注を削除 |
| VirtualMotorCore に `resetReq` 入力がない | 2026-02-27 | 設計決定: 実機モータードライバにもソフトウェアリセット（位置/速度ゼロ復帰）機能はないため、VirtualMotorCore は実機同等の仕様として `resetReq` を持たない。実験間の初期化は ControllerCore の `positionOffset := positionAct` による相対位置補正で対応する |
| H3. `motor_current_act` は SIL で 0 埋め | 2026-02-27 | D13: VirtualMotorCore に `torqueActualValue` (‰ rated, INT) 出力を追加。DriverAdapter で A 変換後 ExperimentLogger の `motorCurrentAct` に接続。SIL でも飽和後の実電流が記録可能 |
| M15. DriverAdapter にリセット入力がない | 2026-02-27 | D12: 相対位置化を ControllerCore → DriverAdapter に移管。`GVL_DRV.resetReq AT %I*` を追加し、エッジ検出で `positionOffsetRad := positionRad` をキャプチャ。ControllerCore / ExperimentLogger と同一のエッジ検出方式で統一 |
| M14. ExperimentSequencer のリセットがレベルセンシティブ | 2026-02-27 | `PRG_ExperimentSequencer` に `resetReqPrev` を導入しエッジ検出に修正。ControllerCore / ExperimentLogger / DriverAdapter と統一 |

</details>
