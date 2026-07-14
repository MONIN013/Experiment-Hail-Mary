# Project Overview

> **位置づけ:** プロジェクト全体の目的、設計原則、現在地を示す入口文書  
> **対象読者:** 実装者、実験設計者、初回参入者  
> **更新条件:** 全体方針、フェーズ定義、正本ドキュメントの導線が変わったとき  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) / [TechnicalReference](../architecture/TechnicalReference.md) / [ExperimentProcedure](../operations/ExperimentProcedure.md)

---

## プロジェクト設計仕様

本プロジェクトの最終目標は、
**MATLAB + TwinCAT を用いた 8kHz トルク制御実験環境において、Build 回数を極限まで削減しつつ、再現性と同期性を保証する実験基盤を確立すること**である。

---

## 実装ステータス (2026-03-26)

* 現行の checked-in 構成は **125 us / 8 kHz の `VirtualMotorTask` を前提とした統合系** である。
* `ExperimentSequencer`, `ControllerCore`, `DriverAdapter`, `VirtualMotorCore`, `ExperimentLogger` は `VirtualMotorTask` 上に配置されている。
* `StateMachineControl` (ModeManager) は `PlcTask1` (10 ms) で動作し、reset handshake / heartbeat watchdog / logger handshake を担う。
* MATLAB 側の主実行面は `experiment.ExperimentConfig + experiment.ConnectionManager + experiment.ExperimentRunner` に一本化されている。
* `config` 名前空間は `EnvironmentConfig` と `MatlabEnvironment` を正本にし、実験入口は `ExperimentConfig.defaults()` が `cfg.env` に環境 snapshot を内包する。
* MATLAB の PATH は `run('matlab/setup_matlab_environment.m')` を一度実行して `userpath/startup.m` へ登録し、`prefdir` の cache を読む運用にしている。
* DriverAdapter の正本は C++ TcCOM `DriverAdapter/` のみである。

> 旧来の `1 ms SIL` 前提や Phase 途中の記述は履歴情報であり、現行構成の正本ではない。詳細は [SystemArchitecture](../architecture/SystemArchitecture.md) を参照。

---

## 1. 技術的目標

### 1.1 周期同期性の保証

* 8kHz 制御周期で完結するリアルタイム構造を確立する
* 異時刻信号混在を排除する
* EtherCAT DC とタスク構成を整合させる

### 1.2 Build 依存性の排除

* 制御構造を固定化する
* パラメタ更新のみで実験条件変更を可能にする
* TE1400 に依存せず、C++ TcCOM と PLC ST で制御構造を直接実装する

### 1.3 層分離の徹底

* TwinCAT: リアルタイム制御専任
* MATLAB: 実験統括・解析専任
* RT と非 RT の責任を混在させない

---

## 2. 実験基盤としての目標

### 2.1 再現性の確保

* 実験条件を完全に再現可能にする
* 制御周期の揺らぎを排除する

### 2.2 同定・周波数応答測定の信頼性向上

* FRF 歪みを防止する
* ILC 収束性を保証する
* 注入信号の位相整合を保証する

### 2.3 安全性の確保

* ModeManager による状態管理
* Status Word の適切なフィードバック
* Control Word の責任分離
* heartbeat watchdog と explicit abort の両立

---

## 3. 設計上の制約条件

* 制御周期: 8kHz 固定
* リアルタイム層は MATLAB に依存しない
* ADS 通信は非同期補助のみ
* 実験用途であり、構成変更を素早く回せることを優先する

---

## 4. 本プロジェクトの本質

本プロジェクトは単なる制御実装ではない。

目的は、

* 実験系の物理的妥当性を保証し
* 同期性を破壊する設計を排除し
* 制御理論評価に耐えるデータを取得できる環境を構築する

ことである。

---

## 5. 詳細設計仕様

本文書の設計思想を具体化したモジュール仕様・I/O 定義・パラメータ一覧は以下を参照:

* **[SystemArchitecture](../architecture/SystemArchitecture.md)** — 現行モジュール境界、配線、公開契約
* **[TechnicalReference](../architecture/TechnicalReference.md)** — GVL / ADS / tsproj mapping に即した技術参照
* **[ExperimentProcedure](../operations/ExperimentProcedure.md)** — 運用手順
* **[NewProjectBlock.pu](../architecture/diagrams/NewProjectBlock.pu)** — ブロック図
