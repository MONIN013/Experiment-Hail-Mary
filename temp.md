# ドキュメント vs 実装 差異調査レポート（未解決のみ）

更新日: 2026-03-05  
対象ブランチ: master  
未解決件数: 2件

---

## サマリー表（残件）

| # | 重要度 | 種類 | 対象モジュール | 状態 | 次アクション |
|---|---|---|---|---|---|
| D-03 | 🔴 重大 | 未実装 | DriverAdapter → ExperimentLogger `currentCmd` 出力経路 | 未着手 | `GVL_DRV.currentCmd` 追加 + I/O マッピング接続 |
| D-09 | 🟠 中程度 | 命名不一致 | `enableCurrentOut` vs `enableCurrentOutput` | 保留 | 命名統一方針を決定して一括リネーム |

---

## D-03 DriverAdapter: `currentCmd` 出力が未実装

| 項目 | 内容 |
|---|---|
| **種類** | 未実装 |
| **ドキュメント** | `docs/module-specs/ExperimentLogger.md`: `Inputs.currentCmd` は DriverAdapter 起点 |
| **実装** | `DriverAdapter/GVLs/GVL_DRV.TcGVL` に `currentCmd` 出力変数なし。`PRG_DriverAdapter` の `targetCurrentA` は内部変数 |
| **影響** | ExperimentLogger 側 `currentCmd` が未接続になる可能性 |
| **推奨アクション** | `GVL_DRV.currentCmd AT %Q* : LREAL` 追加、`PRG_DriverAdapter` で代入、Logger 入力へ I/O 接続 |

---

## D-09 ModeManager/DriverAdapter 間の命名不一致（保留）

| 項目 | 内容 |
|---|---|
| **種類** | 命名不一致 |
| **送信側実装** | `StateMachineControl/POUs/MAIN.TcPOU`: `enableCurrentOut` |
| **受信側実装** | `DriverAdapter/GVLs/GVL_DRV.TcGVL`: `enableCurrentOutput` |
| **ドキュメント** | `ModeManager.md` は `enableCurrentOut`、`ArchitectureSpec.md` と `DriverAdapter.md` は `enableCurrentOutput` |
| **推奨アクション** | 統一名を決定し、実装・仕様・I/Oマッピングを同時更新 |

---

## 備考（今回反映済み）

D-01, D-02, D-04, D-05, D-06, D-07, D-08, D-10, D-11, D-12, D-13, D-14, D-15, D-16, D-17, D-18, D-19 は修正済み。
