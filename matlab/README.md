# MATLAB Layer

MATLAB 層の現行正本は `experiment.ExperimentConfig + experiment.ConnectionManager + experiment.ExperimentRunner` である。`config` は環境構築時に触る設定と bootstrap 用に限定する。legacy bridge は削除済みで、実験実行はこの組み合わせだけを前提にする。

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
| `config.MatlabEnvironment` | startup / path cache / local config 管理 |
| `virtualMotor.PlantConfig` | VirtualMotorCore パラメータ |
| `virtualMotor.writeParams` | VirtualMotorCore parameter write |
| `twincat_ads.AdsSession` | transport キャッシュ |
| `twincat_ads.AdsTransport` | ADS 実装 |
| `twincat_ads.SymbolBrowser` | symbol discovery / validation |

削除済みの legacy API:

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

非デフォルト VM を使う場合だけ、実験実行の直前に 1 行追加する。

```matlab
vm_cfg = virtualMotor.PlantConfig.from_struct(struct(...));
virtualMotor.writeParams(conn, vm_cfg);
out = experiment.ExperimentRunner.run(conn, cfg);
```

出力の正本:

* `out.raw`
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
`matlab/experiment/proto/` は旧 demo 由来の実行不能な参照資料であり、詳細は `matlab/experiment/proto/README.md` を参照する。
demo / 検証 / 調査用の手動実行スクリプトは `matlab/tools/` に置き、MATLAB path には追加しない。
実行時は明示パスで呼び出す。

```matlab
run('matlab/tools/run_position_command_demo.m')
```

| スクリプト | 用途 |
|---|---|
| `matlab/tools/run_position_command_demo.m` | 現行デモ |
| `matlab/tools/run_verify_xar.m` | active contract の検証 |
| `matlab/tools/run_verify_virtual_motor.m` | VirtualMotorCore parameter symbol の確認 |
| `matlab/tools/run_ads_discovery_demo.m` | discovery 補助 |
| `matlab/tools/run_check_logger_bin.m` | logger bin の直接検査 |
| `matlab/tools/run_si_demo.m` | SI デモ |

---

## テスト

```matlab
run('matlab/tests/run_tests.m')
```

`matlab/tests/` の現行構成は unit 28 本、contract 3 本である。全一覧は `matlab/tests/` を参照する。

主要テスト:

* runtime config / 接続 / 実行: `TestExperimentConfig.m`, `TestConnectionManager.m`, `TestExperimentRunner.m`
* 学生実験入口: `TestExp01SiConfig.m`, `TestExp02FeedbackExperimentConfig.m`, `TestStudentExperimentHelpers.m`
* logger / 解析: `TestAnalyzeSiFrf.m`, `TestReadLoggerBin.m`, `TestPreloadEval.m`
* controller / waveform: `TestControllerConfig.m`, `TestBiquadStage.m`, `TestBuildPeriodicChirp.m`
* tools / bootstrap: `TestRunPositionCommandDemoConfig.m`, `TestRunSiDemoConfig.m`, `TestManualToolsBootstrap.m`
* 環境 / symbol: `TestEnvironmentConfig.m`, `TestMatlabEnvironment.m`, `TestRuntimeSymbols.m`, `TestVirtualMotorSymbols.m`
* contract: `TestAdsSession.m`, `TestSymbolBrowserContract.m`, `TestTransportContract.m`
