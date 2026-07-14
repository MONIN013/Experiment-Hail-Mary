# MATLAB Layer

MATLAB 層の現行正本は `experiment.ExperimentConfig + experiment.ConnectionManager + experiment.ExperimentRunner` である。`config` は環境構築時に触る設定と bootstrap 用に限定し、実験実行はこの組み合わせだけを前提にする。

関連文書:

* [MatlabSpec](../docs/architecture/MatlabSpec.md)
* [SystemArchitecture](../docs/architecture/SystemArchitecture.md)
* [TechnicalReference](../docs/architecture/TechnicalReference.md)

---

## セットアップ

一度だけ以下を実行し、`userpath/startup.m`、`prefdir` の path cache、ローカル環境設定を更新する。

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
| `experiment.ControllerConfig` | 最大10段の SOS controller (`N x 6`, `[b0 b1 b2 a0 a1 a2]`) |
| `experiment.exp0n.run_and_collect` | 学生実験入口の接続、実行、logger bin 回収 |
| `experiment.exp0n.load_plant_data` / `load_trajectory` | plant と tracked 8 kHz 軌道の strict loader |
| `experiment.exp0n.assert_run_contract` | 学生実験の受入判定 |
| `experiment.scenario.exp01`〜`exp04` | 副作用なしの実験条件・設計構築 |
| `experiment.workflow.run_exp01`〜`run_exp04` | 実測、信号抽出、metrics、artifact 保存 |
| `experiment.exp02.reference_profile` | exp02 用 step / MAT 参照軌道生成 |
| `experiment.exp02.signals_from_logger_bin` | logger bin から tracking 信号と metrics を抽出 |
| `experiment.exp02.designpid` / `designpi` / `designpd` | 移植済み PID/PI/PD 極配置設計 |
| `experiment.exp02.stability_check` | Nyquist と感度上限の共通判定 |
| `experiment.exp04.srinv` | 安定逆系フィルタ |
| `experiment.exp04.filtfilt_clean` | 端点過渡を抑える零位相フィルタ |
| `experiment.exp04.design_learning_filters` / `learning_update` | ILC filter 設計と純粋な学習更新 |
| `testoracle.simulate_ilc_campaign` / `predict_ilc_campaign` | Test 専用の VM-only ILC campaign simulation / strict oracle |
| `experiment.waveform.periodic_chirp` | logarithmic 周期 chirp 生成 |
| `experiment.waveform.point_to_point_trajectory` | TrajectTools 非依存の任意軌道生成ツール |
| `experiment.waveform.step_reference` | exp02 用 step 参照軌道生成 |
| `experiment.controller.from_discrete_tf` | 実数・離散・SISO TF を最大10段の SOS ControllerConfig へ変換 |
| `config.MatlabEnvironment` | startup / path cache / local config 管理 |
| `virtualMotor.PlantConfig` | VirtualMotorCore パラメータ |
| `virtualMotor.configure` / `readParams` | IDLE 安全確認付きの VM parameter 設定 / readback |
| `virtualMotor.writeParams` | VM tool 内部で使う低レベル parameter write |
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

任意次数の離散 controller は SOS へ2次分解して設定する。`a0` は自動で1へ正規化され、10段を超える controller は拒否される。`from_discrete_tf` は元の sample time を保持し、実行時に `1 / cfg.env.task_rate_hz` と一致しない controller は拒否される。空の SOS bank は identity feedback、ゼロ controller は `experiment.ControllerConfig.p_only(0)` の1段として表す。raw の動的 SOS を直接構築する場合は `sample_time_s` も明示する。

```matlab
Kd = c2d(K, 1 / cfg.env.task_rate_hz, "tustin");
cfg.controller = experiment.controller.from_discrete_tf(Kd);
```

VirtualMotor parameter は通常 Runner から独立している。VM mapping を activate した後、必要な場合だけ専用 tool で設定する。

```matlab
run('matlab/tools/run_configure_virtual_motor.m')
```

`virtualMotor.configure` は `modeFlags=0`、`modeState=IDLE`、`experimentActive=false`、`tableLen=0` と VM settle / position saturation を書込み前に確認し、全 parameter を readback 照合する。`virtualMotor.restart_runtime` は予測初期状態を raw zero にそろえる Test/E2E 専用であり、通常の学生実験・demo・RealMotor では呼ばない。

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
旧 demo と重複実装は移植内容を現行 API と仕様書へ統合したうえで削除済みであり、Git 履歴を archive とする。
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

`run_exp01_exp04_preflight.m` は mapping 種別に依存せず、ADS 接続、共通 active contract symbol、MATLAB toolbox、`plant.mat`、tracked 軌道を読み取り専用で確認する。
学生入口は internal heartbeat を無効化し、`cfg.ads_assembly` を使う external heartbeat だけを有効化する。同一実行で internal/external を同時に有効化することはできない。
`exp01_SysId.m` は cycle平均0・最大絶対値0.25 Aへ正規化した logarithmic chirp SI を行う。loggerの `ff_value` から実測速度を直接同定し、semi-implicit Eulerと一致する `Ts*z/(z-1)` で位置FRDを構成して、`matlab/experiment/data/plant.mat` に `Pd` / `Pd_motor` / `Pd_load` / `Pd_vel_load` / `Pd_vel_motor` / `Pdn` / `Jn` / `Dn` / `Ndelay` / `Ts` を保存する。VM/実機の target metadata は保存せず、Mapping変更後も exp01→exp04 の標準順序を操作者が守る。
`matlab/resources/trajectory_8khz.mat` は標準軌道の tracked resource で、SHA-256 は `11C4E587D2E413707C09CA0875779269E1F6F7ECFD1CEC1C50030C18A62B5CB0` である。`load_trajectory` が field・件数・有限性・8 kHz 刻みを検証し、deg 系を rad 系へ一元変換する。
`exp02_FeedBack.m` は `designpid(Dn/Jn,0,1/Jn,omega)`、`omega=15 rad/s`、`Smax=2` を既定にして、Nyquist と感度上限を数値確認してから `feedback_result.mat` に `t,r,y,e,u,Kd` を保存する。
`exp03_FeedForward.m` は同じ 720 deg / 1 s 往復軌道を使い、FF gain が空なら `Kfa=Jn`、`Kfv=Dn`、`Kfc=0` として `f=Kfa*a+Kfv*v+Kfc*sign(v)` と `Ndelay` 先読み補償を行う。保存変数は `t,r,y,e,u,f,Kd` である。
`exp04_ILC.m` は Temp 参照実装と同じ `Linv=feedback(Pdn,Kd)`、`J=feedback(Pd,Kd)`、`srinv`、零位相 `Q^2`、200 sample splice を使い、`|Q|^2|1-alpha*J/Linv| < 1` を実験前に確認する。既定は `Ntrial=10`、`alpha=0.6`、`q_cutoff_hz=120`、`maxInput=1.6 A` である。720 deg往復の後ろへ6秒のゼロreference整定tailを付ける。学習更新は元の往復軌道だけを対象とし、整定tailのFFは全trialで厳密に0へ固定して、各trial終端を速度量子値0・motor/load位置差2 count以内に戻す。各trialの実測直後、学習更新前に位置、誤差、logger上で整列したFF/FB入力の同一dashboardを更新する。次trialのFF超過または実測error norm増加では、完了済み数値history、`trialSummary`、停止理由を `ilc_result.mat` へcheckpointしてから例外化する。trial別画像は保存しない。trial runner MAT、再parse確認済みの `trialXX_logger.bin`、最終結果は `data/exp04_runs/<timestamp>/` へ追記し、過去結果を削除しない。
VirtualMotor の予測・照合は `matlab/tests/` と Test 専用 `run_virtual_motor_prediction_e2e.m` だけで行う。学生実験と demo は予測を開始前に計算せず、実測 logger、run contract、安定性、入力上限、実測 error norm を判定に使う。

| スクリプト | 用途 |
|---|---|
| `matlab/tools/run_position_command_demo.m` | 現行デモ |
| `matlab/tools/run_ads_transport_e2e.m` | IDLE 中の ADS struct / array / slice / 同値 write-readback E2E |
| `matlab/tools/run_verify_xar.m` | active contract の検証 |
| `matlab/tools/run_verify_virtual_motor.m` | VirtualMotorCore parameter symbol の確認 |
| `matlab/tools/run_configure_virtual_motor.m` | IDLE 中の VM parameter 設定と全field readback |
| `matlab/tools/run_virtual_motor_prediction_e2e.m` | Test 専用。VM runtime を再起動し、driver量子の30 countに一致する `±0.048 A` 入力で8 kHz prediction と logger を全信号比較 |
| `matlab/tools/run_controller_benchmark.m` | 同一軌道・同一条件で7方式のSISO controllerを実測し、各run直後に確定loggerを方式別binへ退避・再parse確認する |
| `matlab/tools/run_full_vm_manifest_e2e.m` | Test 専用。事前凍結manifestに対する全入口・4層照合 |
| `matlab/tools/refresh_live_script.m` | rich `.m` Live Scriptを構造保護しながら実行・保存 |
| `matlab/tools/update_matlab_project.m` | Project APIによる登録・分類・ProjectPath同期 |
| `matlab/tools/run_ads_discovery_demo.m` | discovery 補助 |
| `matlab/tools/run_check_logger_bin.m` | logger bin の直接検査 |
| `matlab/tools/run_exp01_exp04_preflight.m` | exp01〜exp04 実行前の読み取り専用確認 |
| `matlab/tools/run_si_demo.m` | SI デモ |

position demo は電流入力換算nominal plantから設計した20 rad/s filtered PIDで `0.75 rad` のstepを使う。SI demo は `remove_chirp_mean=true` を既定とし、`A=0.25 A` の周期 chirp から cycle mean を除去した後、DriverAdapterの `1.6 mA/count` へ量子化して1周期のcount総和を厳密に0へ補正する。これにより自由剛体モードへ量子化DC biasを持ち込まず、`ffValue -> loadVelocity` の測定 FRFを求める。Testのdrift gateは終端位置や終端速度ではなく、過渡2周期後の同位相cycle間位置差の最大値を使う。両demoは選択中のMappingをそのまま使い、VM parameterを暗黙に変更しない。表示時はsemi-implicit Eulerの恒等式に対応する厳密離散積分器 `Ts/(1-z^-1)` を正周波数で評価し、`ffValue -> loadPosition` の FRF と coherence を描画する。予測 FRF との照合は Test に限定する。長時間runは外部heartbeatを使う。

4本の学生入口はrich `.m` Live Scriptのinline output、appendix、metadataを保持する。入口自身は調整値と名前付きtable/図の提示だけを担い、純粋な条件構築は `experiment.scenario`、実測とartifact保存は `experiment.workflow` が担う。各artifact tableの `completedAtUtc` はfresh実行のprovenanceである。埋込結果の更新には `refresh_live_script.m` を使い、output参照、appendix定義、ID/JSON、PNG payload、section構造を更新前後に検証する。

R2025bのheadless `executeAndSave` が不安定な場合だけ、原本とtargetのbackupを確認し、4本をそれぞれ別のDesktop MATLAB session/processで1本ずつ `Run All` → `Save` する。同じ入口を自動実行後に再実行してはならない。保存直後に `experiment.liveeditor.inspect` / `assert_valid` を実行し、4本合計18画像、output/appendix全単射、ID/JSON、PNG magic、metadata/sectionを確認する。fresh `completedAtUtc` と実行前後のfile SHA/output JSON digestを証拠とし、mtimeだけでは合格にしない。fallback対象entryは自動campaign上で未完了のまま止め、Desktop実行・検証後にledgerへ反映する。

Test専用E2Eは実行前に、(1)量子化・固定delay・SOS・電流制限・semi-implicit Eulerを含む厳密VM予測、(2)独立な離散 `lsim/freqresp`、(3)実験目的から予見される成果、(4)artifact schema/shape/単位/digestをmanifestへ凍結する。通常の学生入口、demo、controller benchmarkには予測、VM再起動、parameter再設定を持ち込まない。

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
* controller / waveform: `TestControllerConfig.m`, `TestWriteControllerParams.m`, `TestBuildPeriodicChirp.m`
* tools / bootstrap: `TestExp01Exp04Preflight.m`, `TestRunPositionCommandDemoConfig.m`, `TestReadLatestLoggerBin.m`, `TestRunSiDemoConfig.m`, `TestManualToolsBootstrap.m`
* 環境 / symbol: `TestEnvironmentConfig.m`, `TestMatlabEnvironment.m`, `TestRuntimeSymbols.m`, `TestModeManagerControl.m`, `TestPlantConfig.m`, `TestSymbolTraversal.m`, `TestTsprojMapping.m`, `TestVirtualMotorSymbols.m`, `TestVirtualMotorWriteParams.m`
* utility / write helper: `TestMatlabUtils.m`, `TestWriteHelpers.m`
* contract: `TestAdsSession.m`, `TestSymbolBrowserContract.m`, `TestTransportContract.m`
