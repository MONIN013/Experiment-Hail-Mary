# 命名規則ガイド — ExperimentHailMary

> **目的:** プロジェクト全体で変数・関数・型名の命名を統一し、可読性と保守性を高める。  
> **制定日:** 2026-02-25 ／ **最終更新:** 2026-02-26  
> **適用範囲:** C++ TcCOM モジュール / PLC Structured Text / MATLAB コード  
> **関連文書:** [ArchitectureSpec.md](ArchitectureSpec.md) §4 (シンボル一覧) ｜ [TechnicalReference.md](TechnicalReference.md) §8 (ADS シンボル) ｜ [OpenIssues.md](OpenIssues.md)

---

## 0. 基本原則

| 優先度 | ルール |
|--------|--------|
| 1 | **一貫性 > 個人の好み** — 既にこのガイドで決まったルールに従う |
| 2 | **camelCase / PascalCase を優先** — snake_case は原則使わない |
| 3 | **TwinCAT フレームワークとの整合** — 自動生成コードの規則に合わせる |
| 4 | **略語は 2文字まで ALL_CAPS、3文字以上は PascalCase** — `IO`, `VM` は OK、`Pid` (`PID` ではなく) |

### 略語の扱い

| 文字数 | 規則 | 例 |
|--------|------|----|
| 1–2文字 | ALL_CAPS | `IO`, `VM`, `FF` |
| 3文字以上 | PascalCase | `Pid`, `Ads`, `Ref` |
| 物理量記号 | 元の大文字/小文字を尊重 | `Kt`, `M`, `D`, `tau` |

---

## 1. C++ TcCOM モジュール

対象: `ControllerCore`, `ExperimentLogger`, `VirtualMotorCore`

### 1.1 型名

| 種別 | 規則 | 例 |
|------|------|----|
| クラス | `C` + PascalCase | `CModule1` |
| 構造体 (TMC) | `ST_` + PascalCase | `ST_Notch`, `ST_PhaseLead`, `ST_LogStatus` |
| 構造体 (手書き) | PascalCase | `LogRecord`, `AxisRuntimeState` |
| enum class | `E` + PascalCase | `EDriveState`, `EFileFsmState` |
| I/O 構造体 | `Module1Inputs` / `Module1Outputs` | (TwinCAT 規約に従う) |

### 1.2 変数名

| 種別 | 規則 | 例 |
|------|------|----|
| メンバ変数 | `m_` + PascalCase | `m_PidS1`, `m_BufferCount`, `m_IsLoggingActive` |
| スマートポインタ | `m_sp` + PascalCase | `m_spCyclicCaller`, `m_spSrv` |
| ローカル変数 | camelCase | `resetEdge`, `loggingCmd`, `risingEdge` |
| 関数パラメータ | camelCase | `refValue`, `axisIndex`, `flushRemaining` |
| 定数 (`constexpr` / `const`) | `k` + PascalCase | `kBufferRecords`, `kDefaultLogPath` |
| エラーコード定数 | `kErr` + PascalCase | `kErrInvalidPath`, `kErrWriteFault` |

### 1.3 関数名

| 種別 | 規則 | 例 |
|------|------|----|
| メンバ関数 (public) | PascalCase | `CycleUpdate()`, `SetObjStatePS()` |
| メンバ関数 (private) | PascalCase | `StepController()`, `ApplyBiquad()` |
| ヘルパー (クラス外) | PascalCase | `ClampSymmetric()` |

> **注意:** リセット系関数は `ResetRuntimeState()` に統一する（単数形）。

### 1.4 enum class 値

| 規則 | 例 |
|------|----|
| ALL_CAPS + アンダースコア区切り | `SWITCH_ON_DISABLED`, `OPERATION_ENABLED`, `FAULT` |
|  | `IDLE`, `OPEN_WAIT`, `ACTIVE`, `WRITE_WAIT`, `ERROR` |

### 1.5 構造体フィールド (TMC 定義)

| 規則 | 例 |
|------|----|
| camelCase | `notchB0`, `notchB1`, `notchA1` |
| Pid 系 | `pidB0`, `pidB1`, `pidA1` (~~`PID_b0`~~ は廃止) |
| 物理量 | `tauLimit`, `velLimit`, `taskDtNs` (~~`M`~~, ~~`D`~~ → `mass`, `damping`) |

> **移行メモ:** 物理量 1文字記号 (`M`, `D`) はコメントで物理的意味を補記し、
> フィールド名は説明的な camelCase (`mass`, `damping`, `ratedTorque`) に移行する。
> TMC 変更は I/O マッピング再設定を伴うため Phase 単位で計画的に行う。

### 1.6 マクロ / #define

| 規則 | 例 |
|------|----|
| ALL_CAPS + アンダースコア区切り | `SRVNAME_CONTROLLERCORE` |

---

## 2. PLC Structured Text

対象: `StateMachineControl`, `ExperimentSequencer`, `DriverAdapter`

### 2.1 型名

| 種別 | 規則 | 例 |
|------|------|----|
| ファンクションブロック | `FB_` + PascalCase | `FB_StateMachineControl` |
| プログラム | `PRG_` + PascalCase | `PRG_ExperimentSequencer` |
| ファンクション | `F_` + PascalCase | `F_DecodeDriveState` |
| 列挙型 (DUT) | `E_` + PascalCase | `E_DriveState` |
| 構造体 (DUT) | `ST_` + PascalCase | `ST_LogEntry` |

### 2.2 変数名

| 種別 | 規則 | 例 |
|------|------|----|
| ローカル変数 | camelCase | `servoEnableReq`, `resetEdge`, `doneLatched` |
| GVL名 | `GVL_` + ALL_CAPS 短縮名 | `GVL_MODE`, `GVL_SEQ`, `GVL_DRV` |
| GVL 内変数 | camelCase | `refValue`, `ffValue`, `modeFlags`, `experimentActive` |
| 入力パラメータ (`VAR_INPUT`) | camelCase | `statusWord`, `enable`, `controlWord` |
| 出力パラメータ (`VAR_OUTPUT`) | camelCase | `driveState`, `isReady` |
| FB インスタンス | `fb` + PascalCase | `fbStateMachine`, `fbDecoder` |
| 定数 (`VAR CONSTANT`) | ALL_CAPS + アンダースコア | `CW_FAULT_RESET`, `STATE_IDLE`, `N_REF_MAX` |
| 列挙値 | ALL_CAPS + アンダースコア | `SWITCH_ON_DISABLED`, `OPERATION_ENABLED` |

### 2.3 ハンガリアン記法について

**廃止する。** ST は型付き言語であり、IDE のツールチップで型が確認できるため不要。

| ❌ 旧 (廃止) | ✅ 新 |
|--------------|-------|
| `bEnable` | `enable` |
| `bFaultResetPulsed` | `faultResetPulsed` |
| `uiStatusWord` | `statusWord` |
| `eDriveState` | `driveState` |
| `nIndex` | `index` |

### 2.4 定数的ローカル変数

`VAR CONSTANT` で宣言できるものは `VAR CONSTANT` に移し、ALL_CAPS とする。  
`VAR CONSTANT` にできない（実行時に計算する値）場合は camelCase のままにし、ALL_CAPS にしない。

| ❌ 旧 | ✅ 新 |
|-------|-------|
| `VM_TASK_DT_NS : UDINT := 1000000;` (VAR) | `VM_TASK_DT_NS : UDINT := 1000000;` (VAR CONSTANT) |

---

## 3. MATLAB

対象: `matlab/+experiment/`, `matlab/+twincat_ads/`, `matlab/tests/`

### 3.1 型名

| 種別 | 規則 | 例 |
|------|------|----|
| クラス | PascalCase | `RunConfig`, `AdsTransport` |
| インターフェース | `I` + PascalCase | `IAdsTransport` |
| パッケージ | camelCase (フォルダ名 `+xxx`) | `+experiment`, `+twincatAds` |

> **移行メモ:** パッケージ名 `+twincat_ads` → `+twincatAds` は import 先が多いため、
> 次のメジャーリファクタ時にまとめて行う。当面は既存名を維持して良い。

### 3.2 変数名

| 種別 | 規則 | 例 |
|------|------|----|
| プロパティ | camelCase | `amsNetId`, `amsPort`, `refProfile`, `taskDtNs` |
| ローカル変数 | camelCase | `refCmd`, `ffCmd`, `logSeq`, `tableLen` |
| 定数的変数 | `k` + PascalCase (推奨) または ALL_CAPS | `kMaxRetries`, `MAX_TIMEOUT` |

### 3.3 関数・メソッド名

| 種別 | 規則 | 例 |
|------|------|----|
| パブリックメソッド | camelCase | `connect`, `disconnect`, `readScalar`, `writeArray` |
| プライベートメソッド | camelCase | `writeVmParams`, `pulseReset`, `waitUntilDone` |
| スタンドアロン関数 | camelCase | `preloadEval`, `runVirtualmotor` |
| スタティックメソッド | camelCase | `fromVarargin`, `fromStruct`, `fromDefaults` |
| テスト関数 | `test` + PascalCase | `testReadScalar`, `testRunConfig` |

### 3.4 スクリプトファイル名

| 規則 | 例 |
|------|----|
| camelCase | `runPreloadAndPlot.m`, `runAdsDiscoveryDemo.m` |

> **移行メモ:** 既存の `run_preload_and_plot.m` 等は次回編集時に rename する。

---

## 4. 言語横断の共通シンボル名

C++ ↔ PLC ↔ MATLAB 間でマッピングされるシンボル名は以下で統一する：

| 意味 | C++ (TMC フィールド) | PLC (GVL 変数) | MATLAB (プロパティ) |
|------|---------------------|----------------|-------------------|
| 指令値 | `refValue` | `refValue` | `refValue` |
| FF入力 | `ffValue` | `ffValue` | `ffValue` |
| 外乱値 | `distValue` | `distValue` | `distValue` |
| 位置実測 | `positionAct` | `positionAct` | `positionAct` |
| リセット要求 | `resetReq` | `resetReq` | `resetReq` |
| 目標トルク | `targetTorque` | `targetTorque` | `targetTorque` |
| ステータスワード | `statusWord` | `statusWord` | `statusWord` |
| コントロールワード | `controlWord` | `controlWord` | `controlWord` |

---

## 5. 移行方針

| 優先度 | 対象 | 方針 | 状況 |
|--------|------|------|------|
| **即時** | 新規コード | このガイドに従う | ✅ 運用中 |
| **高** | C++ enum 値の統一 | `EFileFsmState` の値を ALL_CAPS に変更 | ✅ 完了 |
| **高** | C++ リセット関数名統一 | 全モジュール `ResetRuntimeState()` に統一 | ✅ 完了 |
| **高** | PLC ハンガリアン記法の除去 | 次回編集時に camelCase に置換 | ✅ 完了 — 全 POU/GVL で camelCase 化済み (2026-02-26 確認) |
| **中** | PLC GVL 変数名 snake→camel | Phase 単位でまとめて変更 (TMC マッピング変更を伴う) | ✅ 完了 |
| **中** | C++ 構造体フィールド統一 | TMC 再定義と合わせて Phase 単位で実施 | 🔄 一部残存 — [OpenIssues.md](OpenIssues.md) L2, L3 参照 |
| **低** | MATLAB 全体の camelCase 化 | 次のメジャーリファクタ時にまとめて実施 | 未着手 |
| **低** | MATLAB パッケージ名変更 | import 影響が大きいため最後に実施 | 未着手 |

---

## 6. チェックリスト（レビュー用）

新規コード・PR レビュー時に確認するポイント：

- [ ] snake_case を使っていないか（MATLAB 既存コードの保守修正を除く）
- [ ] ハンガリアン記法を使っていないか（PLC）
- [ ] `m_` 以降が PascalCase になっているか（C++）
- [ ] enum class の値が ALL_CAPS か（C++）
- [ ] 定数が `k` + PascalCase (C++) または ALL_CAPS (PLC) か
- [ ] 言語横断シンボル名が §4 の表と一致しているか
- [ ] 略語が §0 のルールに従っているか（3文字以上 → PascalCase）
