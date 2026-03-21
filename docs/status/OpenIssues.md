# Open Issues

> **位置づけ:** 未解決課題、技術的負債、後方互換コードの棚卸し  
> **対象読者:** 実装者、レビュー担当者、次フェーズ計画者  
> **更新条件:** 課題の追加、解消、優先度変更、撤去判断が発生したとき  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) / [TechnicalReference](../architecture/TechnicalReference.md) / [GvlSeqLogMigrationPlan](../plans/GvlSeqLogMigrationPlan.md)

後方互換・フォールバックコードの技術的負債リスト。
コード精査日: 2026-03-05

---

## 凡例

| 優先度 | 意味 |
|--------|------|
| 高 | 一括撤去可能な連鎖。他の作業を阻害している |
| 中 | 放置すると混乱を招く。次のリファクタリングサイクルで対処 |
| 低 | 技術的負債だが機能に影響しない |

---

## 高優先度

### `#1` ExperimentLogger/Module1.cpp — `__has_include` ビルド成果物フォールバック

| 項目 | 内容 |
|------|------|
| ファイル | `ExperimentLogger/Module1.cpp` L7-15 |
| 問題 | `ExperimentLoggerVersion.h` が存在しない場合にハードコード UUID `{ 0xe98592e3, ... }` でフォールバックする `__has_include` ガードが残存。他モジュール（VirtualMotorCore, ControllerCore）には同等のフォールバックがなく一貫性がない。 |
| 根拠 | 正規ビルドでは常にヘッダが存在するためフォールバックブランチは到達不能。不正な UUID が誤ってリンクされるリスクがある。 |
| 対処 | `__has_include` ガードとハードコード UUID ブランチを削除し、直接 `#include "ExperimentLoggerVersion.h"` のみにする。 |

---

### `#5` out.raw — GVL_SEQ_LOG 命名規則の残存フィールド

| 項目 | 内容 |
|------|------|
| ファイル | `matlab/+experiment/send_position_command.m` L187-195、`matlab/+experiment/VirtualMotorService.m` L123-130 |
| 問題 | `out.raw` / `raw` struct のフィールド名（`logRefValue`, `logFfValue`, `logDistValue`, `logControlInput`, `logTargetCurrent`, `logPositionAct`, `logSeq`）が GVL_SEQ_LOG 時代の命名規則のまま。ExperimentLogger 移行後は命名根拠がない。 |
| 補足 | `logT`, `log_wrIdx`, `log_overflow`, `logIdx` の 4 フィールドは削除済み（GitHub issue 作成済み・コード修正完了）。残存するのは有効データを保持するフィールドの命名規則のみ。 |
| 対処 | `ref_value`, `ff_value` 等 ExperimentLogger バイナリの列名と一致するスネークケースに統一する。 |

---

## 中優先度

### `#6` preload_eval.m — `pre_roll_count` / `post_roll_count` 永久ゼロ

| 項目 | 内容 |
|------|------|
| ファイル | `matlab/+experiment/preload_eval.m` L49-50 |
| 問題 | `pre_roll_count = uint32(0)` と `post_roll_count = uint32(0)` がハードコード。GVL_SEQ_LOG リングバッファの折り返し処理の名残で、ExperimentLogger では折り返しが発生しないため永遠に 0。 |
| 対処 | フィールドごと削除し、下流の参照箇所（`metrics.acceptance.logNot_overflowed` 等）も整理する。 |

---

### `#7` TestPreloadEval.m — 常に PASS する `log_overflow = false` フィクスチャ

| 項目 | 内容 |
|------|------|
| ファイル | `matlab/tests/unit/TestPreloadEval.m` L47 付近 |
| 問題 | テストフィクスチャが `raw.log_overflow = false` と `raw.logT = zeros(3,1)` を手動セット。`log_overflow` は運用上常に `false` であるため、それを検証するアサーションは常に PASS し、テストとして機能しない。 |
| 対処 | `log_overflow` / `logT` フィクスチャ設定行とその対応アサーションを削除する（`#6` の撤去と合わせて対処）。 |

---

### `#10` GVL_MODE.TcGVL — `experimentState : UINT` と `modeState : E_ModeState` 並存

| 項目 | 内容 |
|------|------|
| ファイル | `StateMachineControl/GVLs/GVL_MODE.TcGVL` L24 |
| 問題 | `experimentState : UINT := STATE_IDLE`（旧形式）と `modeState : E_ModeState := E_ModeState.IDLE`（新形式）が並存。MATLAB 側が旧 `UINT` 形式のシンボルを読んでいるため新形式への移行が止まっている。 |
| 対処 | MATLAB 側を `modeState : E_ModeState` 読み取りに対応させた上で `experimentState : UINT` を削除する。 |

---

## 低優先度

### `#9` AdsTransport.m — `should_fallback_array_read` レガシーワークアラウンド

| 項目 | 内容 |
|------|------|
| ファイル | `matlab/+twincat_ads/AdsTransport.m` L169, L193 |
| 問題 | `.NET ADS クライアントの旧バージョンにおける `System.UInt64[]` マーシャリングバグのワークアラウンド。エラーメッセージをハードコード文字列マッチで判定している（`should_fallback_array_read`）。現行クライアントバージョンではバグが修正済みの可能性が高く、フォールバック経路が到達不能になっていると考えられる。 |
| 対処 | 使用中の .NET ADS クライアントバージョンでの再現性を確認し、不要であれば `should_fallback_array_read` とフォールバック経路を削除する。 |

---

### `#11` ClassFactory.cpp — `TCDBG_UNIT_VERSION` 条件コンパイル 常デッドブランチ

| 項目 | 内容 |
|------|------|
| ファイル | `VirtualMotorCore/VirtualMotorCoreClassFactory.cpp` L20-22、`ExperimentLogger/ExperimentLoggerClassFactory.cpp` L20-22、`ControllerCore/ControllerCoreClassFactory.cpp` L20-22 |
| 問題 | `#if defined(TCDBG_UNIT_VERSION)` ブロックが全 3 モジュールに存在するが、通常ビルドでは `TCDBG_UNIT_VERSION` が未定義のため常にデッドブランチ。 |
| 補足 | 以前のレビューで「ControllerCore にはない」と記載されていたが、**3 モジュール全てに存在する**。一貫性は問題ではなく、デッドコードであること自体が問題。 |
| 対処 | 実際に TcDbgUnit が使用される計画がないならブロックごと削除する。使用計画があるなら定義配布方法を文書化する。 |
