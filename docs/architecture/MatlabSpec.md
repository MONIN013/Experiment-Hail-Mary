# Matlab Spec

> **位置づけ:** `matlab/` 以下の現行 API と責務分離の正本
> **対象読者:** MATLAB 実装者、ADS 連携の保守担当者  
> **更新条件:** MATLAB 側 API、出力契約、TwinCAT との接続面が変わったとき
> **関連文書:** [ProjectOverview](../overview/ProjectOverview.md) / [SystemArchitecture](./SystemArchitecture.md) / [TechnicalReference](./TechnicalReference.md) / [NamingConvention](../operations/NamingConvention.md)

---

## 1. 概要

MATLAB 層は **実験統括・パラメータ設定・ログ取得・解析** を担当する。リアルタイム制御は TwinCAT 側に委譲し、MATLAB は ADS と logger `.bin` を使って以下を行う。

* `GVL_SEQ` への `ref/ff/dist` テーブル書込み
* `GVL_MODE` による reset / start / stop / 状態監視
* ControllerCore のパラメータ注入
* VirtualMotorCore のパラメータ注入 (`virtualMotor.writeParams`)
* logger `.bin` の読出しと再生評価

---

## 2. パッケージ構成

| パッケージ | パス | 役割 |
|---|---|---|
| `+config` | `matlab/+config/` | 環境設定、MATLAB 起動 bootstrap |
| `+experiment` | `matlab/+experiment/` | orchestration / 解析 / TwinCAT 実行補助 |
| `+virtualMotor` | `matlab/+virtualMotor/` | VirtualMotor parameter model / write |
| `+twincat_ads` | `matlab/+twincat_ads/` | 汎用 ADS 通信層 |
| `+twincat_ads/+internal` | `matlab/+twincat_ads/+internal/` | 非公開内部実装 |
| resources | `matlab/resources/` | clean clone で必要な tracked 実験入力 |

依存方向は `+experiment -> +config / +twincat_ads / +virtualMotor`、`+config -> +twincat_ads`、`+virtualMotor -> +twincat_ads` の非循環構造とする。setup は project-specific symbol を検査せず、exp01〜exp04 の preflight が runtime 契約を検査する。

---

## 3. 公開 API

現行の正本 API は以下のみ。

| クラス / 関数 | 役割 |
|---|---|
| `config.EnvironmentConfig.current()` | ローカル設定を反映した環境固定値 |
| `config.MatlabEnvironment` | startup / path cache / local config の管理 |
| `experiment.ConnectionManager` | `AdsSession` を使った transport 構築 |
| `experiment.ExperimentRunner` | 実験実行フロー本体 |
| `experiment.ExperimentConfig` | 実験実行の主 runtime config (`cfg.env` に環境 snapshot を内包) |
| `experiment.ControllerConfig` | ControllerCore 用の 4 段 biquad 設定 |
| `experiment.exp0n.run_and_collect` | 学生実験入口の接続、実行、logger bin 回収 |
| `experiment.exp0n.load_plant_data` / `load_trajectory` | plant / tracked trajectory の strict loader |
| `experiment.exp0n.assert_run_contract` | 学生実験の共通受入判定 |
| `experiment.exp01.nominal_overlay_plant` | nominal VirtualMotor plant の取得 |
| `experiment.exp02.reference_profile` | exp02 用 step / MAT 参照軌道生成 |
| `experiment.exp02.signals_from_logger_bin` | logger bin から tracking 信号と metrics を抽出 |
| `experiment.exp02.designpid` / `designpi` / `designpd` | 移植済み PID/PI/PD 極配置設計 |
| `experiment.exp02.stability_check` | measured / nominal loop の Nyquist と感度判定 |
| `experiment.exp04.srinv` | 安定逆系フィルタ |
| `experiment.exp04.filtfilt_clean` | 端点過渡を抑える零位相フィルタ |
| `experiment.exp04.design_learning_filters` / `learning_update` | ILC filter 設計と純粋な学習更新 |
| `experiment.exp04.precompute_virtual_motor_plan` | Test 専用の VM-only ILC campaign oracle |
| `experiment.waveform.periodic_chirp` | logarithmic 周期 chirp 生成 |
| `experiment.waveform.point_to_point_trajectory` | TrajectTools 非依存の任意軌道生成ツール |
| `experiment.waveform.step_reference` | exp02 用 step 参照軌道生成 |
| `experiment.controller.from_discrete_tf` | 離散 TF から ControllerConfig への変換 |
| `virtualMotor.PlantConfig` | VirtualMotorCore 用の物理パラメータ |
| `virtualMotor.writeParams` | VirtualMotorCore parameter write |
| `virtualMotor.predict_logger` / `compare_prediction` / `assert_prediction` | Test 専用の fixed-delay・量子化 oracle |
| `virtualMotor.discrete_velocity_frf` | Test 専用の semi-implicit Euler / runtime delay FRF oracle |
| `virtualMotor.restart_runtime` | Test/E2E 専用の lifecycle reset と raw zero 確認 |
| `twincat_ads.AdsSession` | AMS Net ID 単位の transport キャッシュ |
| `twincat_ads.AdsTransport` | TwinCAT ADS 実装 |
| `twincat_ads.SymbolBrowser` | シンボル列挙 / 契約検証 |

以下の廃止 API は現行実装から削除済みで、正本ではない。

* `experiment.RunConfig`
* `experiment.PositionCommandConfig`
* `experiment.send_position_command`
* `experiment.run_virtualmotor`
* `experiment.VirtualMotorService`

---

## 4. Config 所有

| 所有者 | 責務 |
|---|---|
| `config.EnvironmentConfig.current()` | 環境固定値 |
| `config.MatlabEnvironment` | startup / path cache 管理 |
| `experiment.ExperimentConfig` | 実行時設定。`defaults()` が `cfg.env` に環境 snapshot を持つ |
| `experiment.ControllerConfig` | ControllerCore パラメータ |
| `virtualMotor.PlantConfig` | VM パラメータ |

`virtualMotor.PlantConfig` の既定値は Panasonic MHMF011L1A2 相当の小慣性 2 慣性 preset である。Motor / Load とも inertia は `7.1e-6 kg m^2`、rated torque は `0.32 N m`、encoder resolution は 23 bit (`8388608`) とし、DriverAdapter 側の rated current は `1.6 A` を前提にする。非デフォルト VM を使う場合だけ、`virtualMotor.PlantConfig.from_struct(...)` で明示的に差し替える。

`experiment.ExperimentConfig` は canonical runtime field と `env` のみを保持する。`ams_net_id` / `seq_port` などの flat 環境値は受理せず、環境値は `cfg.env` からのみ取得する。未知 field、NaN/Inf、非有限 waveform、不正 timeout、廃止 config object は受理しない。`ControllerConfig` / `BiquadStage` / `PlantConfig` も未知 field と非有限値を拒否し、`PlantConfig` は負の慣性・制限値と無効 encoder resolution を拒否する。

---

## 5. PATH 初期化

初回セットアップは一度だけ `run('matlab/setup_matlab_environment.m')` を実行する。

* `prefdir/ExperimentHailMaryPathCache.mat` に `matlab_root` と exact `path_entries` を保存する
* `prefdir/startup.m` の managed block を更新し、次回以降の MATLAB 起動で cache を読む
* `matlab/+config/LocalEnvironmentConfig.m` に PC ごとの ADS / logger 設定を生成する
* 既存 local config がある場合は再探索しない。再探索は `config.MatlabEnvironment.setup("Reconfigure", true)` のみで行う
* cache が欠落または stale の場合は探索せず、setup の再実行を警告する
* 起動時に追加する path は `matlab/` と `matlab/experiment/` の 2 本だけとする

---

## 6. `EnvironmentConfig` の主要値

| プロパティ | 値 | 説明 |
|---|---|---|
| `ams_net_id` | `"192.168.10.3.1.1"` | XAR の AMS Net ID |
| `seq_port` | `853` | ExperimentSequencer |
| `control_port` | `852` | ModeManager |
| `module_port` | `351` | C++ TcCOM 群 |
| `task_rate_hz` | `8000` | `VirtualMotorTask` 周波数 |
| `controller_prefix` | `"ControllerCore_Obj1 (Module1)."` | Controller parameter prefix |
| `logger_target_file_path` | `"C:\\ExperimentData\\experiment_logger.bin"` | TwinCAT 側 logger 保存先 |
| `logger_host_file_path` | `"\\\\sunnyday\\ExperimentData\\experiment_logger.bin"` | MATLAB 側 logger 読み取り先 |
| `table_max_n` | `100000` | テーブル長上限 |
| `logger_release_timeout_s` | `5.0` | logger close 待ち既定値 |

`GVL_MODE.*` などの fixed symbol contract は `experiment.RuntimeSymbols` / `experiment.ModeManagerControl` が正本であり、environment config には置かない。

active contract は `351/852/853` のみを使う。`851` は discovery 用にローカルで明示指定する場合だけ扱う。

---

## 7. 実行フロー

### 7.1 `ExperimentRunner.run(conn, cfg, ...)`

1. `experiment.ExperimentConfig` を normalize / validate し、connection と `cfg.env` の AMS / port / logger / controller-prefix snapshot 一致を確認
2. Symbol contract を必要に応じて検証
3. `modeFlags=0` と `tableLen=0` を先に書き、途中例外用 cleanup を登録
4. `ModeManagerControl` で `resetReq/resetAckCounter` handshake と idle を確認
5. Controller / VirtualMotor parameter を書き込む
6. `GVL_SEQ` へ `ref/ff/dist/repeatCount` を書き、全 table 完了後に `tableLen` を一度だけ公開
7. internal または external heartbeat の一方だけを開始
8. `modeFlags` で servo enable -> experiment start
9. `GVL_MODE.modeState` (`INT16`) / `experimentActive` と heartbeat helper の生存を監視
10. `modeFlags=0` 後に `loggerFileReleased` / `loggerErrorCode` を確認
11. logger `.bin` を一度だけ読み、同じ payload から `out.logger_bin` / `out.raw` / `out.metrics` を返す

途中例外でも `onCleanup` により `modeFlags=0` と external heartbeat 停止を保証する。internal / external heartbeat の同時有効化は config error とする。external helper は `cfg.ads_assembly` を明示的に使い、ready、早期終了、cleanup を監視する。
`experiment.exp0n.run_and_collect` は `restart_virtual_motor_runtime=true` の Test/E2E だけで connection 作成前に VM-only TwinCAT System Service を Reset→Run にする。通常実験は restart せず、接続後の settle と DriverAdapter 相対位置 reset を使う。`out.startup_timing` と `out.run.host.startup_timing` は restart、接続、settle、contract、reset、parameter/table write、heartbeat、READY 到達までの時間を返す。

### 7.2 `ConnectionManager`

* `create(cfg)` は `seq`, `ctrl`, `module` をまとめて返す
* `create_plc_only(cfg)` は `seq`, `ctrl` だけを返す
* 接続先 AMS / port は `cfg.env` から取り、戻り値 `conn.env` に同じ snapshot を保持する
* `from_transports(...)` は既存 transport を runner 契約へ束ねる

### 7.3 VM parameter write

* `write_virtual_motor_params=false` では VM symbol の検査・書込みを行わない
* VirtualMotor 実験では `write_virtual_motor_params=true` と `virtual_motor_plant` を設定し、Runner が reset idle 後に `virtualMotor.writeParams(conn, vm_cfg)` を実行する
* prediction helper と `restart_virtual_motor_runtime=true` は Test/E2E だけで使い、学生実験・demo の開始フローには含めない
* 学生入口 exp01〜exp04 は上部の `use_virtual_motor=true` を標準とし、checked-in preset と runtime を同期する
* RealMotor では `use_virtual_motor=false` とし、VM symbol / parameter に触れない
* step demo / SI demo も実行前の直接 write ではなく Runner config で VM preset を指定する

---

## 8. 出力契約

### 8.1 正本出力

`ExperimentRunner.run(...)` の `out.raw` は snake_case を正本とする。

`out.logger_bin` は Runner が一度だけ読んだ logger bin payload で、`out.raw` は同じ payload から作られる。学生入口と demo はこの値を再利用し、実験後に最新ファイルを glob して選び直さない。

主フィールド:

* `seq`
* `ref_value`
* `ff_value`
* `dist_value`
* `control_input`
* `target_current`
* `position_act`

### 8.2 評価結果

`out.metrics` が唯一の評価出力であり、`out.eval` は存在しない。

* `metrics.sampling` は command/log の件数と sequence gap を返す
* `metrics.input_waveform`, `ff_waveform`, `dist_waveform` は replay 一致性を返す
* `metrics.torque_sum` は `control_input + dist_value == target_current` の整合性を返す
* `metrics.position_diag` は位置ログの利用可否と速度推定を返す

8 kHz task 内の正常な pipeline delay は `waveform_diag_max_shift_samples` (既定 1 sample) の範囲で整列して判定する。zero-shift 値と `best_shift_samples` は診断用に両方保持し、件数不一致や許容範囲外の遅延は合格扱いにしない。

`preload_eval` は snake_case raw schema と `cfg.env.task_rate_hz` を直接受け、廃止済み `log*` field や top-level `task_rate_hz` は扱わない。

---

## 9. 手動ツール

各手動ツールは `restoredefaultpath` / `genpath` を持たず、startup で復元された PATH を前提にする。
`matlab/tools/` は MATLAB path に追加せず、明示パスで実行する。

```matlab
run('matlab/tools/run_position_command_demo.m')
```

学生実験用の `matlab/experiment/exp0n_*.m` は Live Editor 用 `.m` を正本にする。
学生が調整する `Controller` / `Chirp` / 軌道条件はファイル上部に集約し、ローカル関数は置かない。
学生入口と実験 demo の logger 取得は `ExperimentRunner` が解放確認後に一度だけ読んだ `out.logger_bin` を正とする。glob による最新選択 (`experiment.io.read_latest_logger_bin`) は独立した logger 検査ツールに限る。
共通処理は `experiment.waveform` / `experiment.controller` / `experiment.analysis` / `experiment.plot` / `experiment.io` / `experiment.exp01` / `experiment.exp02` / `experiment.exp04` / `experiment.exp0n` に置く。
学生入口は `exp01_SysId.m` / `exp02_FeedBack.m` / `exp03_FeedForward.m` / `exp04_ILC.m` の 4 本である。互換入口 `exp02.m` / `exp03.m` / `exp04.m` は現行構成では持たない。

### 9.1 exp01〜exp04 のデータ契約

`exp01_SysId.m` は logarithmic chirp SI を rad 系 logger 信号で実行する。既定 chirp は `Tend=100`、`Tcycle=10`、`f0=0.5 Hz`、`f1=4000 Hz`、`A=0.25 A`、`trans=2` である。0.25 A は現行6500 rpm VirtualMotor速度契約を超えない一様chirp上限である。manual fit の初期値は VirtualMotor preset の電流入力換算から `Jn=(Jmotor+Jload)/(ratedTorque/ratedCurrent)=7.1e-5`、`Dn=(Dmotor+Dload)/(ratedTorque/ratedCurrent)=5.325e-4`、`Ndelay=4` とする。

`matlab/experiment/data/plant.mat` の契約は `Pd` / `Pd_motor` / `Pd_load` / `Pd_vel_load` / `Pd_vel_motor` / `Pdn` / `Jn` / `Dn` / `Ndelay` / `Ts` / `vm_plant` / `vm_mode` である。`Pd` は load 側 position FRD、`Pdn` は `c2d(1/(Jn*s+Dn)/s,Ts,"zoh")/z^Ndelay` の離散 nominal plant である。VM実験では provenance fields を現行presetと照合して、異なるplantのSI結果を使わない。

`matlab/resources/trajectory_8khz.mat` は標準軌道の tracked resource で、SHA-256 は `11C4E587D2E413707C09CA0875779269E1F6F7ECFD1CEC1C50030C18A62B5CB0` である。`ref1_struct` は deg 系の 720 deg / 1 s 往復軌道を保持し、`experiment.exp0n.load_trajectory` が field、件数、有限性、8 kHz 時間刻みを検証して rad 系へ変換する。`experiment.waveform.point_to_point_trajectory` は TrajectTools 非依存の任意軌道生成ツールとして残すが、現行 exp02〜exp04 の既定軌道ではない。

結果 MAT の変数集合は、`feedback_result.mat` が `t,r,y,e,u,Kd`、`feedforward_result.mat` が `t,r,y,e,u,f,Kd`、`ilc_result.mat` が `t,history,Kd,stability,learning_filters` である。各値は実験入口で rad 系へ変換した信号を正とする。

exp02 は `experiment.exp02.designpid(Dn/Jn,0,1/Jn,omega)` を `omega=15 rad/s` で設計し、`c2d(...,"tustin")` 後に Nyquist と `Smax=2` の感度上限を数値確認する。exp03 の FF は `Kfa=Jn`、`Kfv=Dn`、`Kfc=0` を既定にし、`f=Kfa*a+Kfv*v+Kfc*sign(v)` へ `Ndelay` の先読み補償を加える。

exp04 は Temp 参照実装と同じ `Linv=feedback(Pdn,Kd)`、`J=feedback(Pd,Kd)` と2次 low-pass Qを使い、`|Q|^2|1-alpha*J/Linv| < 1` を数値 gate と bode で確認する。更新則は `f_{j+1}=filtfilt_clean(Qnum,Qden,f_j+alpha*srinv(Linv,e_j,Npad),Npad)` で、200 sample transient splice を行う。既定は `Ntrial=10`、`alpha=0.6`、`q_cutoff_hz=120`、`maxInput=1.6 A` とする。120 Hzは200 Hz VMねじり共振より低く、10 Hz Qで生じた長い終端過渡を25 ms splice内へ局在させる。次 trial のFF超過は送信前エラーとする。実測 error norm増加は警告・診断として保存し、10 trialを続ける。`history.trialSummary` は各trialのerror norm、最大実入力、error増加、収束ピークを保持し、run固有フォルダへ `stability` / `learning_filters` と共に保存する。

| スクリプト | 位置づけ |
|---|---|
| `matlab/tools/run_position_command_demo.m` | Runner config で VM preset を適用する step response demo |
| `matlab/tools/run_si_demo.m` | Runner config で VM preset を適用し、`ffValue -> loadVelocity` の実測 FRF に `1/s` を掛けて position FRF を表示する SI demo。`remove_chirp_mean` でchirp平均除去を切替可能（既定true、falseでは100秒VM runの位置飽和を警告） |
| `matlab/tools/run_ads_transport_e2e.m` | IDLE 中の live ADS struct / array / slice / same-value write-readback |
| `matlab/tools/run_exp01_exp04_preflight.m` | exp01〜exp04 実行前の読み取り専用確認 |
| `matlab/tools/run_verify_xar.m` | active contract (`852/853/351`) の接続・symbol・読み出し確認 |
| `matlab/tools/run_verify_virtual_motor.m` | VirtualMotorCore parameter symbol の確認 |
| `matlab/tools/run_virtual_motor_prediction_e2e.m` | Test 専用。VM runtime を再起動して hidden state をゼロ化し、prediction と logger を全信号比較する |
| `matlab/tools/run_ads_discovery_demo.m` | discovery 補助。必要なら `851` をローカル指定で probe する |
| `matlab/tools/run_check_logger_bin.m` | logger bin の直接検査 |

---

## 10. テスト

テスト実行:

```matlab
run('matlab/tests/run_tests.m')
```

`matlab/tests/` の現行構成は、`matlab/tests/unit/` と `matlab/tests/contract/` 配下の test file を正本とする。

主なテストグループ:

| ファイル | 役割 |
|---|---|
| `tests/unit/TestExperimentConfig.m` / `TestConnectionManager.m` / `TestExperimentRunner.m` | 実験 runtime config、接続構築、実行フロー |
| `tests/unit/TestExp01SiConfig.m` / `TestExp02FeedbackExperimentConfig.m` / `TestExp03FeedforwardExperimentConfig.m` / `TestExp04IlcExperimentConfig.m` / `TestStudentExperimentHelpers.m` | 学生実験入口と共通 helper |
| `tests/unit/TestPointToPointTrajectory.m` / `TestFeedbackDesignHelpers.m` / `TestExp04IlcHelpers.m` / `TestExperimentDataLoaders.m` | 数値 helper、軌道・plant data 契約 |
| `tests/unit/TestAnalyzeSiFrf.m` / `TestReadLoggerBin.m` / `TestPreloadEval.m` | logger 読み取り、FRF、replay 評価 |
| `tests/unit/TestControllerConfig.m` / `TestBiquadStage.m` / `TestBuildPeriodicChirp.m` | controller / waveform helper |
| `tests/unit/TestExp01Exp04Preflight.m` / `TestRunPositionCommandDemoConfig.m` / `TestReadLatestLoggerBin.m` / `TestRunSiDemoConfig.m` / `TestManualToolsBootstrap.m` | 手動ツールの設定・bootstrap |
| `tests/unit/TestEnvironmentConfig.m` / `TestMatlabEnvironment.m` / `TestRuntimeSymbols.m` / `TestModeManagerControl.m` / `TestPlantConfig.m` / `TestSymbolTraversal.m` / `TestTsprojMapping.m` / `TestVirtualMotorSymbols.m` / `TestVirtualMotorWriteParams.m` | 環境、PATH、symbol contract |
| `tests/unit/TestMatlabUtils.m` / `TestWriteHelpers.m` | utility / write helper |
| `tests/contract/TestAdsSession.m` / `TestSymbolBrowserContract.m` / `TestTransportContract.m` | ADS session、symbol browser、transport 契約 |
