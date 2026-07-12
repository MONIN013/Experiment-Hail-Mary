# MATLAB Layer

MATLAB 層の現行正本は `experiment.ExperimentConfig + experiment.ConnectionManager + experiment.ExperimentRunner` である。`config` は環境構築時に触る設定と bootstrap 用に限定し、実験実行はこの組み合わせだけを前提にする。

関連文書:

* [MatlabSpec](../docs/architecture/MatlabSpec.md)
* [SystemArchitecture](../docs/architecture/SystemArchitecture.md)
* [TechnicalReference](../docs/architecture/TechnicalReference.md)

---

## セットアップ

一度だけ以下を実行し、`prefdir/startup.m`、path cache、ローカル環境設定を更新する。

```matlab
run('matlab/setup_matlab_environment.m')
```

起動時に追加される path は `matlab/` と `matlab/experiment/` の 2 本だけで、`genpath` は使わない。
`matlab/+config/LocalEnvironmentConfig.m` は setup が生成する PC ごとの設定で、Git 管理しない。
`-batch` / headless 実行では既存 local config を再設定する質問を出さず、そのまま保持する。
再探索が必要な場合だけ以下を実行する。

```matlab
config.MatlabEnvironment.setup("Reconfigure", true)
```

---

## 現行 API

| API | 役割 |
|---|---|
| `config.EnvironmentConfig.current()` | ローカル設定を反映した環境固定値 |
| `experiment.ConnectionManager` | `AdsSession` ベースの接続構築 |
| `experiment.ExperimentRunner` | 実験実行と logger 回収 |
| `experiment.ExperimentConfig` | 実験実行の主 runtime config (`cfg.env` に環境 snapshot を内包) |
| `experiment.ControllerConfig` | ControllerCore パラメータ |
| `experiment.exp0n.run_and_collect` | 学生実験入口の接続、実行、logger bin 回収 |
| `experiment.exp0n.load_plant_data` / `load_trajectory` | plant と tracked 8 kHz 軌道の strict loader |
| `experiment.exp0n.assert_run_contract` | 学生実験の受入判定 |
| `experiment.exp01.nominal_overlay_plant` | nominal VirtualMotor plant の取得 |
| `experiment.exp02.reference_profile` | exp02 用 step / MAT 参照軌道生成 |
| `experiment.exp02.signals_from_logger_bin` | logger bin から tracking 信号と metrics を抽出 |
| `experiment.exp02.designpid` / `designpi` / `designpd` | 移植済み PID/PI/PD 極配置設計 |
| `experiment.exp02.stability_check` | Nyquist と感度上限の共通判定 |
| `experiment.exp04.srinv` | 安定逆系フィルタ |
| `experiment.exp04.filtfilt_clean` | 端点過渡を抑える零位相フィルタ |
| `experiment.exp04.design_learning_filters` / `learning_update` | ILC filter 設計と純粋な学習更新 |
| `experiment.exp04.precompute_virtual_motor_plan` | Test 専用の VM-only ILC campaign oracle |
| `experiment.waveform.periodic_chirp` | logarithmic 周期 chirp 生成 |
| `experiment.waveform.point_to_point_trajectory` | TrajectTools 非依存の任意軌道生成ツール |
| `experiment.waveform.step_reference` | exp02 用 step 参照軌道生成 |
| `experiment.controller.from_discrete_tf` | 離散 TF から ControllerConfig への変換 |
| `config.MatlabEnvironment` | startup / path cache / local config 管理 |
| `virtualMotor.PlantConfig` | VirtualMotorCore パラメータ |
| `virtualMotor.writeParams` | VirtualMotorCore parameter write |
| `virtualMotor.predict_logger` / `compare_prediction` | Test 専用の 8 kHz logger 予測 / 照合 oracle |
| `virtualMotor.restart_runtime` | Test/E2E 専用の VM lifecycle reset と hidden state zero 化 |
| `twincat_ads.AdsSession` | transport キャッシュ |
| `twincat_ads.AdsTransport` | ADS 実装 |
| `twincat_ads.SymbolBrowser` | symbol discovery / validation |

削除済みの API:

* `RunConfig`
* `PositionCommandConfig`
* `send_position_command`
* `run_virtualmotor`
* `VirtualMotorService`

---

## 接続面

active contract は以下の 3 ポートを使う。

| Port | 用途 |
|---|---|
| `351` | ControllerCore / DriverAdapter / VirtualMotorCore / ExperimentLogger |
| `852` | ModeManager |
| `853` | ExperimentSequencer |

`851` は active contract ではない。discovery 補助で必要な場合だけスクリプト内のローカル定数として明示指定する。

---

## 典型的な実行

```matlab
cfg = experiment.ExperimentConfig.defaults();
cfg.controller = experiment.ControllerConfig.p_only(5);
cfg.ref_profile = [zeros(16000, 1); 0.25 * ones(16000, 1)];
cfg.ff_profile = zeros(size(cfg.ref_profile));
cfg.dist_profile = zeros(size(cfg.ref_profile));

conn = experiment.ConnectionManager.create(cfg);
cleanup = onCleanup(@() conn.session.close());
out = experiment.ExperimentRunner.run(conn, cfg);
```

VirtualMotor parameter は Runner が reset/idle 確認後に書く。非デフォルト VM を使う場合は config に plant を設定する。

```matlab
vm_cfg = virtualMotor.PlantConfig.from_struct(struct(...));
cfg.write_virtual_motor_params = true;
cfg.restart_virtual_motor_runtime = false; % 通常実験は settle + 相対位置 reset を使う
cfg.virtual_motor_plant = vm_cfg;
out = experiment.exp0n.run_and_collect(cfg);
```

`restart_virtual_motor_runtime=true` は予測初期状態を raw zero にそろえる Test/E2E だけで明示する。通常の学生実験と demo は `false` のまま、VM settle、position saturation 拒否、DriverAdapter の相対位置 reset を使う。RealMotor では設定しない。

出力の正本:

* `out.raw`
* `out.logger_bin`
* `out.metrics`
* `out.host`
* `out.logger`
* `out.config`

`out.eval` は存在しない。

---

## 手動ツール

学生実験の入口は `matlab/experiment/exp0n_*.m` の Live Editor 用 `.m` ファイルである。
学生が調整する値は各ファイル上部の「学生が調整するパラメータ」に集約し、ローカル関数は置かない。
実行と logger 回収は `experiment.exp0n.run_and_collect` に一本化し、Runner が解放確認した logger file を読む。
旧 demo と重複 Simulink model は移植内容を現行 API と仕様書へ統合したうえで削除済みであり、Git 履歴を archive とする。
demo / 検証 / 調査用の手動実行スクリプトは `matlab/tools/` に置き、MATLAB path には追加しない。
実行時は明示パスで呼び出す。

```matlab
run('matlab/tools/run_position_command_demo.m')
```

exp01〜exp04 はリポジトリ直下を MATLAB の Current Folder にして実行する。

```matlab
cd('<repository-root>')
run('matlab/setup_matlab_environment.m') % 初回または環境再設定時
run('matlab/tools/run_exp01_exp04_preflight.m')
run('matlab/experiment/exp01_SysId.m')
run('matlab/experiment/exp02_FeedBack.m')
run('matlab/experiment/exp03_FeedForward.m')
run('matlab/experiment/exp04_ILC.m')
```

`run_exp01_exp04_preflight.m` は ADS 接続、active contract symbol、MATLAB toolbox、`plant.mat`、tracked 軌道を読み取り専用で確認する。各入口上部の `use_virtual_motor=true` では VM symbol も検査し、`false` では検査・parameter write を行わない。
学生入口は internal heartbeat を無効化し、`cfg.ads_assembly` を使う external heartbeat だけを有効化する。同一実行で internal/external を同時に有効化することはできない。
`exp01_SysId.m` は logarithmic chirp SI を行い、`matlab/experiment/data/plant.mat` に `Pd` / `Pd_motor` / `Pd_load` / `Pd_vel_load` / `Pd_vel_motor` / `Pdn` / `Jn` / `Dn` / `Ndelay` / `Ts` / `vm_plant` / `vm_mode` を保存する。VM実験のexp02〜04はこの provenance が現行 200 Hz preset と一致しない `plant.mat` を拒否する。
`matlab/resources/trajectory_8khz.mat` は標準軌道の tracked resource で、SHA-256 は `11C4E587D2E413707C09CA0875779269E1F6F7ECFD1CEC1C50030C18A62B5CB0` である。`load_trajectory` が field・件数・有限性・8 kHz 刻みを検証し、deg 系を rad 系へ一元変換する。
`exp02_FeedBack.m` は `designpid(Dn/Jn,0,1/Jn,omega)`、`omega=15 rad/s`、`Smax=2` を既定にして、Nyquist と感度上限を数値確認してから `feedback_result.mat` に `t,r,y,e,u,Kd` を保存する。
`exp03_FeedForward.m` は同じ 720 deg / 1 s 往復軌道を使い、FF gain が空なら `Kfa=Jn`、`Kfv=Dn`、`Kfc=0` として `f=Kfa*a+Kfv*v+Kfc*sign(v)` と `Ndelay` 先読み補償を行う。保存変数は `t,r,y,e,u,f,Kd` である。
`exp04_ILC.m` は Temp 参照実装と同じ `Linv=feedback(Pdn,Kd)`、`J=feedback(Pd,Kd)`、`srinv`、零位相 `Q^2`、200 sample splice を使い、`|Q|^2|1-alpha*J/Linv| < 1` を実験前に確認する。既定は `Ntrial=10`、`alpha=0.6`、`q_cutoff_hz=120`、`maxInput=1.6 A` である。120 Hz Q は既定VMの200 Hzねじり共振より低く、かつ25 ms splice内で終端過渡が十分減衰する帯域として選ぶ。次 trial のFF超過は送信前エラーとし、error norm増加は警告・診断を残して10 trialを続ける。trial は `data/exp04_runs/<timestamp>/` へ追記し、過去結果を削除しない。保存変数は `t,history,Kd,stability,learning_filters` で、`history.trialSummary` にtrial別診断を保持する。
VirtualMotor の予測・照合は `matlab/tests/` と Test 専用 `run_virtual_motor_prediction_e2e.m` だけで行う。学生実験と demo は予測を開始前に計算せず、実測 logger、run contract、安定性、入力上限、実測 error norm を判定に使う。

| スクリプト | 用途 |
|---|---|
| `matlab/tools/run_position_command_demo.m` | 現行デモ |
| `matlab/tools/run_ads_transport_e2e.m` | IDLE 中の ADS struct / array / slice / 同値 write-readback E2E |
| `matlab/tools/run_verify_xar.m` | active contract の検証 |
| `matlab/tools/run_verify_virtual_motor.m` | VirtualMotorCore parameter symbol の確認 |
| `matlab/tools/run_virtual_motor_prediction_e2e.m` | Test 専用。VM runtime を再起動し、8 kHz prediction と logger を全信号比較 |
| `matlab/tools/run_ads_discovery_demo.m` | discovery 補助 |
| `matlab/tools/run_check_logger_bin.m` | logger bin の直接検査 |
| `matlab/tools/run_exp01_exp04_preflight.m` | exp01〜exp04 実行前の読み取り専用確認 |
| `matlab/tools/run_si_demo.m` | SI デモ |

position demo は `Kp=0.02` の VM step を使う。SI demo は `remove_chirp_mean=true` を既定とし、自由剛体モードの DC drift を避けるため `A=0.25 A` の周期 chirp から cycle mean を除去して `ffValue -> loadVelocity` の測定 FRF を求める。生のchirpを使う場合はスクリプト上部で `remove_chirp_mean=false` にできるが、既定の100秒VirtualMotor runでは32-bit位置出力が飽和し得るため警告する。表示時は正周波数について `1/(j*2*pi*f)` を掛け、`ffValue -> loadPosition` の FRF と coherence を描画する。予測 FRF との照合は Test に限定する。長時間runは外部heartbeatを使う。

---

## テスト

```matlab
run('matlab/tests/run_tests.m')
```

`matlab/tests/` の現行構成は、`matlab/tests/unit/` と `matlab/tests/contract/` 配下の test file が正本である。

主要テスト:

* runtime config / 接続 / 実行: `TestExperimentConfig.m`, `TestConnectionManager.m`, `TestExperimentRunner.m`
* 学生実験入口: `TestExp01SiConfig.m`, `TestExp02FeedbackExperimentConfig.m`, `TestExp03FeedforwardExperimentConfig.m`, `TestExp04IlcExperimentConfig.m`, `TestStudentExperimentHelpers.m`
* 数値 helper / data contract: `TestPointToPointTrajectory.m`, `TestFeedbackDesignHelpers.m`, `TestExp04IlcHelpers.m`, `TestExperimentDataLoaders.m`
* logger / 解析: `TestAnalyzeSiFrf.m`, `TestReadLoggerBin.m`, `TestPreloadEval.m`
* controller / waveform: `TestControllerConfig.m`, `TestBiquadStage.m`, `TestBuildPeriodicChirp.m`
* tools / bootstrap: `TestExp01Exp04Preflight.m`, `TestRunPositionCommandDemoConfig.m`, `TestReadLatestLoggerBin.m`, `TestRunSiDemoConfig.m`, `TestManualToolsBootstrap.m`
* 環境 / symbol: `TestEnvironmentConfig.m`, `TestMatlabEnvironment.m`, `TestRuntimeSymbols.m`, `TestModeManagerControl.m`, `TestPlantConfig.m`, `TestSymbolTraversal.m`, `TestTsprojMapping.m`, `TestVirtualMotorSymbols.m`, `TestVirtualMotorWriteParams.m`
* utility / write helper: `TestMatlabUtils.m`, `TestWriteHelpers.m`
* contract: `TestAdsSession.m`, `TestSymbolBrowserContract.m`, `TestTransportContract.m`
