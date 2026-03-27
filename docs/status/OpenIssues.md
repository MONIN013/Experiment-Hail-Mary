# Open Issues

> **位置づけ:** 未解決課題、技術的負債、後方互換コードの棚卸し  
> **対象読者:** 実装者、レビュー担当者、次フェーズ計画者  
> **更新条件:** 課題の追加、解消、優先度変更、撤去判断が発生したとき  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) / [TechnicalReference](../architecture/TechnicalReference.md) / [ExperimentLogger](../modules/ExperimentLogger.md)

後方互換・legacy bridge・到達不能 fallback の GitHub issue 一覧。
見出し番号は GitHub issue 番号に合わせる。

- コード精査日: `2026-03-27`
- GitHub 同期日: `2026-03-27`
- 親 issue: [#8 MATLAB レイヤー構造と構成オーナーシップのリファクタリング](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/8)

---

## 凡例

| 優先度 | 意味 |
|--------|------|
| 高 | コア実行経路に残る legacy branch。可読性と改修コストの両方を悪化させている |
| 中 | 公開 API / PLC 契約 / active verify 面に残る bridge。次の整理サイクルで止めるべき |
| 低 | 検証や archive に閉じるべき legacy residue。今すぐ壊れないが読み手を迷わせる |

---

## 高優先度

### `#19` ExperimentLogger/Module1.cpp - `__has_include` とハードコード VID フォールバック

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#19](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/19) |
| ファイル | `ExperimentLogger/Module1.cpp`, `ExperimentLogger/ExperimentLoggerClassFactory.cpp`, `ExperimentLogger/ExperimentLogger.rc` |
| 問題 | `Module1.cpp` だけが `ExperimentLoggerVersion.h` 不在時のフォールバック GUID を持つ。正規ビルドでは到達不能な互換分岐であり、version header を唯一の正本として読めなくしている。 |
| 対処 | `__has_include` ガードとハードコード GUID を削除し、`ExperimentLoggerVersion.h` を唯一の定義元に統一する。 |

---

### `#20` ExperimentRunner / preload_eval / out.eval - legacy 評価ブリッジ

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#20](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/20) |
| 旧項目 | 旧 docs 項目 `#5`, `#6`, `#7` を現行コードに合わせて統合・再定義 |
| ファイル | `matlab/+experiment/ExperimentRunner.m`, `matlab/+experiment/preload_eval.m`, `matlab/tests/unit/TestPreloadEval.m` |
| 問題 | `ExperimentRunner` が canonical な `out.raw` / `out.metrics` を持ちながら、内部で `to_legacy_raw(...) -> preload_eval(...) -> to_legacy_eval(...)` を回して `out.eval` を返している。`pre_roll_count` / `post_roll_count` は永久 zero、`TestPreloadEval` には `log_overflow` / `logT` の dead fixture も残る。 |
| 対処 | `to_legacy_raw(...)`, `to_legacy_eval(...)`, `out.eval` を撤去し、`preload_eval` を現行 raw schema に揃える。死んだ fixture と永久 zero フィールドも併せて削除する。 |

---

## 中優先度

### `#21` RunConfig と run_virtualmotor - legacy entry path

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#21](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/21) |
| ファイル | `matlab/+experiment/RunConfig.m`, `matlab/+experiment/run_virtualmotor.m`, `matlab/+experiment/VirtualMotorService.m` |
| 問題 | 現在の正本が `ExperimentConfig + ConnectionManager + ExperimentRunner` に移った後も、`RunConfig` と `run_virtualmotor` が旧 flat config と手組み transport 構築を残している。 |
| 対処 | `RunConfig` と `run_virtualmotor` を削除対象の legacy surface として扱い、呼び出し側・テスト・docs を canonical entry path に寄せる。 |

---

### `#22` PositionCommandConfig と send_position_command - legacy entry path

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#22](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/22) |
| ファイル | `matlab/+experiment/PositionCommandConfig.m`, `matlab/+experiment/send_position_command.m` |
| 問題 | `send_position_command` は `PositionCommandConfig` を受けて `ExperimentConfig` へ橋渡しするだけの wrapper になっている。公開 MATLAB 面を増やすだけで、可読性を著しく損なっている。 |
| 対処 | `PositionCommandConfig` と `send_position_command` を legacy API として撤去し、PLC-only 実行の説明と実装を canonical runner 側へ寄せる。 |

---

### `#23` ExperimentConfig - legacy config 受理と旧ポート alias

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#23](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/23) |
| ファイル | `matlab/+experiment/ExperimentConfig.m` |
| 問題 | `ExperimentConfig` が `RunConfig` / `PositionCommandConfig` object と `ams_port` / `control_ams_port` / `module_ams_port` alias を受理し、canonical config 自身が legacy knowledge を抱えている。 |
| 対処 | `ExperimentConfig` は canonical field だけを受理する方向に整理し、legacy object 受理と alias 変換を削除する。 |

---

### `#24` mode-flags 旧互換面 - `mode_flags_*` / `MODEF_RESET_REQ`

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#24](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/24) |
| ファイル | `matlab/+experiment/PositionCommandConfig.m`, `matlab/+experiment/send_position_command.m`, `matlab/+experiment/ModeManagerControl.m` |
| 問題 | `mode_flags_ams_port`, `mode_flags_transport` は現行実装で使われていないのに validation と docs の面だけ残っている。`MODEF_RESET_REQ` も「非対応として reject するためだけ」に残っている。 |
| 対処 | reset handshake を唯一の正本 contract とし、未使用 `mode_flags_*` と reject 専用コードを削除する。 |

---

### `#25` MATLAB/PLC 状態監視 - `experimentState : UINT` 依存の撤去

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#25](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/25) |
| 旧項目 | 旧 docs 項目 `#10` を GitHub issue に昇格 |
| ファイル | `StateMachineControl/GVLs/GVL_MODE.TcGVL`, `matlab/+experiment/VirtualMotorSymbols.m`, `matlab/+experiment/ModeManagerControl.m`, `matlab/run_verify_xar.m` |
| 問題 | PLC 側は `modeState : E_ModeState` を持つのに、MATLAB は依然として `experimentState : UINT` を読み続けている。状態表現が二重化され、移行が止まっている。 |
| 対処 | 状態監視を `modeState` 正本へ移し、`experimentState : UINT` を削除できる状態まで contract・テスト・docs を更新する。 |

---

### `#26` active 検証面に残る port `851` 互換

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#26](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/26) |
| ファイル | `matlab/+experiment/SystemConfig.m`, `matlab/run_verify_xar.m`, `matlab/tests/unit/TestSystemConfig.m`, `docs/architecture/SystemArchitecture.md`, `docs/architecture/MatlabSpec.md` |
| 問題 | checked-in `.tsproj` の active orchestration では正本でない `851` を、`SystemConfig.DRIVER_PORT` と verify script が現役 port のように扱っている。 |
| 対処 | active verify path から `851` を外し、`SystemConfig` と docs を現行 active contract のみへ寄せる。 |

---

## 低優先度

### `#27` AdsTransport.m - `should_fallback_array_read` レガシーワークアラウンド

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#27](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/27) |
| 旧項目 | 旧 docs 項目 `#9` を GitHub issue に昇格 |
| ファイル | `matlab/+twincat_ads/AdsTransport.m` |
| 問題 | 旧 .NET ADS client の `System.UInt64[]` マーシャリング問題を前提にした例外文字列マッチ fallback が transport に残っている。必要性が不明なまま可読性だけを落としている。 |
| 対処 | 現行 client で再現性を確認し、不要なら workaround を削除する。残すなら適用条件を明文化する。 |

---

### `#28` DriverAdapterPLC/ - active 実装ツリー外への退避

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#28](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/28) |
| ファイル | `DriverAdapterPLC/`, `docs/architecture/SystemArchitecture.md`, `docs/modules/DriverAdapter.md`, `docs/overview/ProjectOverview.md` |
| 問題 | docs では一貫して legacy と説明しているのに、`DriverAdapterPLC/` が現役実装と同じルート階層に残っている。active / archive の境界が repo layout から読めない。 |
| 対処 | `DriverAdapterPLC/` を明示的な archive / legacy 領域へ移し、現役実装の一部に見えない配置へ変える。 |

---

### `#29` ClassFactory.cpp - `TCDBG_UNIT_VERSION` dead branch

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#29](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/29) |
| 旧項目 | 旧 docs 項目 `#11` を GitHub issue に昇格 |
| ファイル | `VirtualMotorCore/VirtualMotorCoreClassFactory.cpp`, `ExperimentLogger/ExperimentLoggerClassFactory.cpp`, `ControllerCore/ControllerCoreClassFactory.cpp` |
| 問題 | `TCDBG_UNIT_VERSION` を前提にした条件コンパイルが 3 モジュールに残るが、現行 repo には定義供給元も運用方針も見当たらない。実質 dead branch である。 |
| 対処 | 実運用が無いなら削除する。残すなら定義供給方法と使い方を docs に明文化する。 |
