# Current System

> **位置づけ:** TE1400（Simulink → TcObject）方式の旧システム記録  
> **対象読者:** 旧方式との比較が必要な実装者、移行作業者  
> **更新条件:** 原則更新しない。旧方式の補足や移行注記が必要なときのみ更新  
> **関連文書:** [SystemArchitecture](../architecture/SystemArchitecture.md) / [ProjectOverview](../overview/ProjectOverview.md) / [NewProjectBlock.pu](../architecture/diagrams/NewProjectBlock.pu)
> **補足 (2026-02-24):** 本文書は旧方式の記録。現行リポジトリでは TwinCAT 側の次世代構成（`ExperimentSequencer` + `ControllerCore` + `VirtualMotorCore`）へ移行中。
> 
---

## 機能一覧

### experiment_state.slx
10ms周期で動作する状態遷移管理プログラムです。
主にTwinCATの状態遷移を管理するプログラムです。
なぜかドライバの制限もここで行っています。
### input
- StatusWord: TwinCATから取得するドライバの状態を示すマジックワード
- servo_activate: サーボアクティベートフラグ

### output
- ControlWord: ドライバに送信する状態遷移マジックワード
- OPERATION_MODE: TwinCATに送信する動作モードを示す値
- MAX_TORQUE: TwinCATに送信する最大torque値
- MAX_VELOCITY: TwinCATに送信する最大速度

### 基本機能
- ドライバの状態遷移管理
statuswordとservo_activateに基づいて、ControlWordを生成し、ドライバの状態遷移を管理します。
servo_activateがFalseの場合はサーボオンに対応するControlWordを生成しません。基本はControlWordを6->7->15 と遷移させます。

### experiment_control.slx

モーター制御を行うメインプログラムです。現在は TE1400 ライセンスを使用し Build を行い、TcObject として TwinCAT に登録後、エクスターナルモードで動作させています。

> **注記 (2026-02):** TE1400 試用版 100kB 制限により、次世代設計では TE1400 を使用せず C++ TcCOM に移行。
> また、ロギングについても TE1400 File Writer の代わりに C++ TcCOM ファイルライタを採用。
> → [SystemArchitecture](../architecture/SystemArchitecture.md)
### input
- experiment_activate: 実験開始フラグ
- servo_activate: サーボアクティベートフラグ
- PosisionActualValue: TwinCATから取得する現在位置
- VelocityActualValue: TwinCATから取得する現在速度
- TorqueActualValue: TwinCATから取得する現在トルク
- feedforward_signal: フィードフォワード信号配列
- reference_position: 位置指令値配列

### output
- servo_activate: サーボアクティベートフラグ
- stop_logging: ロギング停止フラグ
- TargetTorque: TwinCATに送信する目標トルク値
- motor_position: 現在のモータ位置
- load_position: 現在の負荷モータ位置
- motor_torque: 現在のモータのトルク値
- load_torque: 現在の負荷モータのトルク値
- motor_velocity: 現在のモータ速度
- load_velocity: 現在の負荷モータ速度
- MATファイルとして出力
  - time: 時間データ
  - motor_position: モータ位置データ
  - load_position: 負荷モータ位置データ
  - motor_torque: モータトルクデータ
  - load_torque: 負荷モータトルクデータ
  - motor_velocity: モータ速度データ
  - load_velocity: 負荷モータ速度データ
  - reference_position: 参照位置データ

### 基本機能
8kzの制御周期で以下の処理を行います。
- 実験制御
servo_activateがTrueになるとサーボをアクティベートし、その後experiment_activateがTrueになると実験を開始します。
実験開始後は
- 8kzのサンプル時間毎にcounterをインクリメントし、時間データを生成
- 実験時間が終了するとstop_loggingをTrueにしてロギングを停止。実験を終了。
- reference_positionをcounterに基づいてそのサンプル時間における位置指令値を取得。
- feedforward_signalをcounterに基づいてそのサンプル時間におけるフィードフォワード信号を取得。
- エンコーダ分解能に基づいて指令値を量子化
- 現在位置との差分を計算
- FB制御を実行し、制御入力uを生成
- uにサチュレーションをかけてドライバの制限に対応
- uをドライバの入力(ここでは定格の0.1%区切りの値)として整形し、TargetTorqueとしてTwinCATに送信
- TwinCATから取得した各種データをメートル法単位に変換
- ロギング
以上の処理を実験時間が終了するまで繰り返します。

---

## 問題点

1. **指令値を変更するたびに Build を行う必要がある。**
2. **制御器に変更を加えるたびに Build を行う必要がある。**

> これらの問題を解決するため、次世代プロジェクト（→ [SystemArchitecture](../architecture/SystemArchitecture.md)）では
> 制御構造を C++ TcCOM で TwinCAT 側に固定し、テーブルリプレイ方式 + ADS パラメータ注入で Build を排除する設計を採用する。
> ロギングは C++ TcCOM ファイルライタで 8kHz×100s の長時間記録に対応する。
> TE1400 は試用版 100kB 制限により廃止。
> ブロック図は [NewProjectBlock.pu](../architecture/diagrams/NewProjectBlock.pu) を参照。
