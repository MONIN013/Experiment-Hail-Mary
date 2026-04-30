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
`matlab/+config/LocalSystemConfig.m` は setup が生成する PC ごとの設定で、Git 管理しない。
再探索が必要な場合だけ以下を実行する。

```matlab
config.MatlabEnvironment.setup("Reconfigure", true)
```

---

## 現行 API

| API | 役割 |
|---|---|
| `config.SystemConfig.current()` | ローカル設定を反映した環境固定値 |
| `experiment.ConnectionManager` | `AdsSession` ベースの接続構築 |
| `experiment.ExperimentRunner` | 実験実行と logger 回収 |
| `experiment.ExperimentConfig` | 実験実行の主 runtime config |
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

## ルートスクリプト

学生実験の入口は `matlab/experiment/exp0n_*.m` の Live Editor 用 `.m` ファイルである。
学生が調整する値は各ファイル上部の「学生が調整するパラメータ」に集約し、ローカル関数は置かない。

| スクリプト | 用途 |
|---|---|
| `run_position_command_demo.m` | 現行デモ |
| `run_verify_xar.m` | active contract の検証 |
| `run_ads_discovery_demo.m` | discovery 補助 |
| `run_check_logger_bin.m` | logger bin の直接検査 |
| `run_si_demo.m` | SI デモ |

---

## テスト

```matlab
run('matlab/tests/run_tests.m')
```

主要テスト:

* `tests/unit/TestExperimentConfig.m`
* `tests/unit/TestConnectionManager.m`
* `tests/unit/TestExperimentRunner.m`
* `tests/unit/TestPreloadEval.m`
* `tests/unit/TestRunPositionCommandDemoConfig.m`
* `tests/unit/TestSystemConfig.m`
* `tests/contract/TestAdsSession.m`
* `tests/contract/TestTransportContract.m`
