# Open Issues

> **位置づけ:** 未解決課題、技術的負債、後方互換コードの棚卸し  
> **対象読者:** 実装者、レビュー担当者、次フェーズ計画者  
> **更新条件:** 課題の追加、解消、優先度変更、撤去判断が発生したとき  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) / [TechnicalReference](../architecture/TechnicalReference.md) / [ExperimentLogger](../modules/ExperimentLogger.md)

後方互換・legacy bridge・到達不能 fallback の GitHub issue 一覧。見出し番号は GitHub issue 番号に合わせる。

* コード精査日: `2026-03-27`
* GitHub 同期日: `2026-03-27` (`gh issue list` で live 確認)
* 親 issue: [#8 MATLAB レイヤー構造と構成オーナーシップのリファクタリング](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/8)

> このブランチでは `#19`, `#20`, `#21`, `#22`, `#23`, `#24`, `#26`, `#29` の修正を実装済み。GitHub 側の issue state は merge / review 前のため open のまま残り得る。

---

## 凡例

| 優先度 | 意味 |
|--------|------|
| 高 | コア実行経路に残る legacy branch。可読性と改修コストの両方を悪化させている |
| 中 | 公開 API / PLC 契約 / active verify 面に残る bridge。次の整理サイクルで止めるべき |
| 低 | 検証や archive に閉じるべき legacy residue。今すぐ壊れないが読み手を迷わせる |

---

## 中優先度

### `#25` MATLAB/PLC 状態監視 - `experimentState : UINT` 依存の撤去

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#25](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/25) |
| ファイル | `StateMachineControl/GVLs/GVL_MODE.TcGVL`, `matlab/+experiment/VirtualMotorSymbols.m`, `matlab/+experiment/ModeManagerControl.m`, `matlab/run_verify_xar.m` |
| 問題 | PLC 側は `modeState : E_ModeState` を持つのに、MATLAB は依然として `experimentState : UINT` を読み続けている。状態表現が二重化されている。 |
| 対処 | 状態監視を `modeState` 正本へ移し、`experimentState : UINT` を削除できる状態まで contract・テスト・docs を更新する。 |

---

## 低優先度

### `#27` AdsTransport.m - `should_fallback_array_read` レガシーワークアラウンド

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#27](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/27) |
| ファイル | `matlab/+twincat_ads/AdsTransport.m` |
| 問題 | 旧 .NET ADS client の `System.UInt64[]` マーシャリング問題を前提にした例外文字列マッチ fallback が transport に残っている。必要性が未確認。 |
| 対処 | 現行 client で再現性を確認し、不要なら workaround を削除する。残すなら適用条件を docs に明文化する。 |

---

### `#28` DriverAdapterPLC/ - active 実装ツリー外への退避

| 項目 | 内容 |
|------|------|
| 状態 | GitHub issue 化済み: [#28](https://github.com/KosekiLab/Experiment-Hail-Mary/issues/28) |
| ファイル | `DriverAdapterPLC/`, `docs/architecture/SystemArchitecture.md`, `docs/modules/DriverAdapter.md`, `docs/overview/ProjectOverview.md` |
| 問題 | docs では legacy と説明しているが、`DriverAdapterPLC/` が現役実装と同じルート階層に残っている。active / archive の境界が repo layout から読みにくい。 |
| 対処 | `DriverAdapterPLC/` を明示的な archive / legacy 領域へ移し、現役実装の一部に見えない配置へ変える。 |
