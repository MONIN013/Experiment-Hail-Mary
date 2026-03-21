# Docs README

この `docs/` は、文書の寿命と読者で整理している。現行仕様の正本は `overview` と `architecture` に置き、運用中の課題や計画は `status` と `plans` に分離する。旧方式は `legacy` に退避し、現行仕様と混同しない。

## 読み始め順

1. [ProjectOverview](./overview/ProjectOverview.md)
2. [SystemArchitecture](./architecture/SystemArchitecture.md)
3. [ExperimentProcedure](./operations/ExperimentProcedure.md)
4. [TechnicalReference](./architecture/TechnicalReference.md)
5. 必要に応じて [modules/](./modules/) 配下の各モジュール仕様

## ディレクトリの目的

- `overview/`: プロジェクト全体像、設計方針、読み始め文書
- `architecture/`: 恒久設計、技術リファレンス、図面、MATLAB 実装仕様
- `modules/`: モジュール単位の詳細仕様
- `operations/`: 実験手順、命名規約などの運用資料
- `status/`: 未解決課題、現時点の懸念、棚卸し
- `plans/`: 改修計画、移行計画
- `legacy/`: 旧方式の記録。現行仕様の正本ではない

## 現行の正本

- 全体方針: [ProjectOverview](./overview/ProjectOverview.md)
- システム設計: [SystemArchitecture](./architecture/SystemArchitecture.md)
- 運用手順: [ExperimentProcedure](./operations/ExperimentProcedure.md)
- 実装寄り参照: [TechnicalReference](./architecture/TechnicalReference.md)

## 運用ルール

- 新規文書は用途に応じたディレクトリへ配置する
- ファイル名は役割が分かる PascalCase を使う
- 文書先頭に `位置づけ / 対象読者 / 更新条件 / 関連文書` を記載する
- 旧方式や廃止予定仕様は `legacy/` に置き、本文でも旧方式であることを明記する
