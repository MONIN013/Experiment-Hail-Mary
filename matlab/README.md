# MATLAB コード構造 再設計

## 実装進捗（Phase 1）

| 区分 | 内容 |
|---|---|
| Done | `+twincat_ads` / `+experiment` への移行、命名規則（`snake_case`）への統一、テスト移行（`TestSymbolBrowserContract` / `TestSymbolTraversal`）、`tests/run_tests.m` 追加、旧 `+ehm` / `eval` / `scripts` 削除 |
| In Progress | なし |
| Next | 実機結果を継続監視するための自動レポート化（環境依存） |

## 実装進捗（Phase 2: 実機スモーク, 2026-02-19）

| 区分 | 内容 |
|---|---|
| Done | `run_ads_discovery_demo.m` 実行: Port `851` / `351` とも `Status=ok`、シンボル列挙成功 |
| Done | `run_preload_and_plot.m` 実行: サマリー `Result OK (6/6 checks passed)` |
| Done | 実行中に判明した不具合を修正: `SymbolBrowser.list_ports` が上位引数（`top_level_only` 等）を受理できるよう `inputParser.KeepUnmatched=true` を適用 |
| In Progress | なし |
| Next | スモーク結果を定期実行できる運用手順の整備（必要なら別ドキュメント化） |

## 破壊的変更（2026-02-20）

- 公開メソッド名を `snake_case` へ統一（互換ラッパーなし）
- 代表例: `RunConfig.from_varargin`, `VirtualMotorSymbols.from_defaults`, `IAdsTransport.read_scalar`, `SymbolBrowser.discover_ports_and_symbols`
- 旧 `camelCase` 名を呼び出すコードはすべて更新が必要

## 現状の問題点

| 問題 | 具体例 |
|---|---|
| 意味不明な命名 | `+ehm` が何を意味するか不明 |
| 冗長なネスト | `+ehm/+adapters/+twincat/` — 2ファイルのために3階層 |
| 1ファイル1パッケージ | `+config/`, `+contracts/`, `+services/`, `+apps/` 各1ファイルのみ |
| 汎用/固有の混在 | `TwinCATSymbolCatalog` に汎用ポート走査と `resolveVirtualMotorSymbols` が同居 |
| 無意味なディレクトリ分割 | `eval/`(2ファイル)、`runners/`(空)、`scripts/`(3ファイル) |
| adsAssembly のボイラープレート | DLLパス自動検出をスクリプト側で毎回記述 |
| 不要な抽象 | `ISymbolCatalog`（メソッド名がプロジェクト固有）、`IVirtualMotorGateway`（実装1つ） |

## 新ディレクトリ構成

```
matlab/
├── +twincat_ads/                    ← 汎用 ADS 通信ライブラリ
│   ├── IAdsTransport.m              ← 抽象トランスポートインターフェース
│   ├── AdsTransport.m               ← 具象TwinCAT ADS トランスポート
│   ├── SymbolBrowser.m              ← シンボル走査・検証（静的メソッド群）
│   └── +internal/                   ← 内部実装（公開API外）
│       └── SymbolTraversal.m        ← BFS走査・.NETヘルパー関数群
│
├── +experiment/                     ← プロジェクト固有コード
│   ├── RunConfig.m                  ← 実験パラメータ設定
│   ├── VirtualMotorSymbols.m        ← PLCシンボル名コントラクト
│   ├── VirtualMotorService.m        ← 実験オーケストレーター
│   ├── run_virtualmotor.m           ← コンポジションルート関数
│   ├── preload_eval.m               ← 結果定量評価
│   └── simulate_position.m          ← 1DOFモデルシミュレーション
│
├── run_preload_and_plot.m           ← エントリスクリプト（直下配置）
├── run_ads_discovery_demo.m         ← ディスカバリーデモスクリプト
│
├── results/                         ← 出力結果（生成物）
│   └── ads_validation/
│
├── tests/                           ← テストコード
│   ├── fixtures/
│   │   ├── MockAdsTransport.m
│   │   ├── MockDotNetCollection.m
│   │   └── MockDotNetSymbol.m
│   ├── contract/
│   │   ├── TestSymbolBrowserContract.m
│   │   └── TestTransportContract.m
│   └── unit/
│       ├── TestRunConfig.m
│       ├── TestSymbolTraversal.m
│       ├── TestVirtualMotorService.m
│       └── TestVirtualMotorSymbols.m
│
└── README.md
```

## 設計方針

### 依存方向

```
+experiment/  ──depends on──▶  +twincat_ads/
```

`+twincat_ads/` は `+experiment/` に一切依存しない。逆方向の依存は禁止。

### `+twincat_ads/` — 汎用 ADS 通信ライブラリ

任意の TwinCAT ADS プロジェクトで再利用可能な汎用レイヤー。プロジェクト固有のシンボル名・ロジックを含まない。

#### 公開 API

| クラス / メソッド | 説明 |
|---|---|
| `IAdsTransport` | 抽象インターフェース: `connect`, `disconnect`, `read_scalar`, `write_scalar`, `read_array`, `write_array` |
| `AdsTransport` | `IAdsTransport` の TwinCAT 具象実装。.NET Interop (`TwinCAT.Ads.TcAdsClient`) 経由 |
| `AdsTransport.net_types()` | .NET型マッピング辞書（`bool`, `double`, `single`, `u32`, `u64`） |
| `SymbolBrowser.discover_ports_and_symbols(amsNetId, ports, ...)` | ポート走査＋シンボル一覧取得 |
| `SymbolBrowser.list_ports(amsNetId, ports, ...)` | ポート接続確認 |
| `SymbolBrowser.list_symbols_for_port(amsNetId, port, ...)` | 指定ポートのシンボルツリー走査 |
| `SymbolBrowser.validate_symbols(transport, probeList)` | 任意のシンボル存在検証。`probeList` は `{symbol, netType; ...}` セル配列 |

#### adsAssembly 解決順序

`AdsTransport` コンストラクタで以下の順に解決:

1. `"ads_assembly"` 引数が明示指定されていればそれを使用
2. 既知パス `C:\Program Files (x86)\Beckhoff\TwinCAT\Functions\TE14xx-ToolsForMatlabAndSimulink\TE140x\NET\TwinCAT.Ads.dll` が存在すれば使用
3. GAC 登録名 `"TwinCAT.Ads"` で試行

#### 内部パッケージ `+internal/`

`+twincat_ads/+internal/` 内のクラスは公開 API ではない。外部コードからの直接参照は禁止。

| クラス | 説明 |
|---|---|
| `SymbolTraversal` | BFS走査、.NETシンボルオブジェクトのプロパティ抽出、テーブル生成等のヘルパー関数群（全static） |

### `+experiment/` — プロジェクト固有コード

仮想モーター実験に特化したオーケストレーション・評価コード。

| ファイル | 説明 |
|---|---|
| `RunConfig` | 実験パラメータのバリューオブジェクト（`ams_net_id`, モデルパラメータ, ADS設定等） |
| `VirtualMotorSymbols` | PLCシンボル名コントラクト。`from_defaults()` (PLC側) / `from_prefix(prefix)` (C++モジュール側) |
| `VirtualMotorService` | 実験オーケストレーター: シンボル解決→パラメータ書き込み→実行→ログ読み取り→評価→保存 |
| `run_virtualmotor` | コンポジションルート: `RunConfig` → `AdsTransport` ×2 → `VirtualMotorService` を組み立てて実行 |
| `preload_eval` | 実験結果の定量評価（入力波形一致、サンプリング品質、RMSE、相関係数、合否判定） |
| `simulate_position` | 前進オイラー法 1DOF 回転モデル: $\tau = \text{clamp}(K_t \cdot I,\; \tau_\text{limit})$, $v_{k+1} = v_k + \frac{T_s}{M}(\tau - D \cdot v_k)$, $x_{k+1} = x_k + T_s \cdot v_{k+1}$ |

### エントリスクリプト — `matlab/` 直下

| ファイル | 説明 |
|---|---|
| `run_preload_and_plot.m` | 正弦波電流プロファイル生成 → `experiment.run_virtualmotor` 実行 → 3段プロット＋サマリー表示 |
| `run_ads_discovery_demo.m` | ADS接続テスト用デモ。`twincat_ads.SymbolBrowser.discover_ports_and_symbols` を呼び、ポート接続状態とシンボル一覧をコンソール表示 |

## 命名規則

| 対象 | 規則 | 例 |
|---|---|---|
| パッケージ名 | `snake_case` | `+twincat_ads`, `+experiment`, `+internal` |
| クラス名 | `PascalCase` | `AdsTransport`, `RunConfig`, `SymbolBrowser` |
| 関数名 | `snake_case` | `run_virtualmotor`, `preload_eval`, `simulate_position` |
| プロパティ名 | `snake_case` | `ams_net_id`, `task_rate_hz` |
| エラーID | `<pkg>:<category>:<name>` | `twincat_ads:transport:connectFailed`, `experiment:config:invalid` |

## 廃止対象

| 対象 | 理由 |
|---|---|
| `+ehm/` パッケージ全体 | 意味不明な命名、冗長なネスト |
| `+ehm/+interfaces/ISymbolCatalog` | メソッド名がプロジェクト固有（`resolveVirtualMotorSymbols`） |
| `+ehm/+interfaces/IVirtualMotorGateway` | 実装が1つしかなく、抽象化の価値がない |
| `eval/` ディレクトリ | 関数は `+experiment/` に統合 |
| `runners/` ディレクトリ | 空ディレクトリ |
| `scripts/` ディレクトリ | スクリプトは `matlab/` 直下に移動 |
| `MockSymbolCatalog` フィクスチャ | `ISymbolCatalog` 廃止に伴い不要 |

## 移行マッピング

| 旧パス | 新パス |
|---|---|
| `+ehm/+interfaces/IAdsTransport.m` | `+twincat_ads/IAdsTransport.m` |
| `+ehm/+adapters/+twincat/TwinCATAdsTransport.m` | `+twincat_ads/AdsTransport.m` |
| `+ehm/+adapters/+twincat/TwinCATSymbolCatalog.m` (汎用部分) | `+twincat_ads/SymbolBrowser.m` + `+twincat_ads/+internal/SymbolTraversal.m` |
| `+ehm/+adapters/+twincat/TwinCATSymbolCatalog.m` (VM固有部分) | `+experiment/VirtualMotorService.m` に吸収 |
| `+ehm/+config/RunConfig.m` | `+experiment/RunConfig.m` |
| `+ehm/+contracts/VirtualMotorSymbols.m` | `+experiment/VirtualMotorSymbols.m` |
| `+ehm/+services/VirtualMotorService.m` | `+experiment/VirtualMotorService.m` |
| `+ehm/+apps/run_virtualmotor.m` | `+experiment/run_virtualmotor.m` |
| `eval/preload_eval.m` | `+experiment/preload_eval.m` |
| `eval/simulate_position_from_current.m` | `+experiment/simulate_position.m` |
| `scripts/run_preload_and_plot.m` | `run_preload_and_plot.m` (matlab/直下) |
| `scripts/run_ads_discovery_demo.m` | `run_ads_discovery_demo.m` (matlab/直下) |

## テスト

```matlab
% matlab/ をカレントディレクトリにして実行
run('tests/run_tests.m')
```

| カテゴリ | ファイル | 検証内容 |
|---|---|---|
| **fixtures** | `MockAdsTransport` | `twincat_ads.IAdsTransport` のモック（`containers.Map` で値保持、操作ログ記録） |
| **contract** | `TestSymbolBrowserContract` | シンボル検証: 欠損シンボルでエラー、全存在でパス |
| **contract** | `TestTransportContract` | モックトランスポートのラウンドトリップ（スカラー・配列） |
| **unit** | `TestRunConfig` | 必須フィールドバリデーション、デフォルト値 |
| **unit** | `TestSymbolTraversal` | BFS走査ロジック: 名前フォールバック、フィルタ、重複除去、配列展開抑止 |
| **unit** | `TestVirtualMotorService` | プロファイルフロー操作順序、タイムアウト警告、ログ欠損時の空配列 |
| **unit** | `TestVirtualMotorSymbols` | `from_prefix` / `from_defaults` が正しいシンボル名を生成するか |

## ADS 通信フロー

```
MATLAB  ──.NET Interop──▶  TwinCAT.Ads.TcAdsClient
  │                           │
  ├─ Connect(amsNetId, port)  │  Port 851 = PLC Runtime (GVL_VM.*)
  ├─ Connect(amsNetId, port)  │  Port 351 = C++ Module  (VirtualMotorParameter.*)
  │                           │
  ├─ CreateVariableHandle()   │  シンボル名 → ハンドル
  ├─ ReadAny(handle, type)    │  スカラー/配列読み
  ├─ WriteAny(handle, value)  │  スカラー/配列書き
  ├─ DeleteVariableHandle()   │  ハンドル解放 (onCleanup)
  │                           │
  └─ SymbolLoaderFactory.Create()  シンボルディスカバリー用
      └─ loader.Symbols            BFS走査
```
