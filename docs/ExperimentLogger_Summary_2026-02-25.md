# ExperimentLogger 実装サマリー & モジュール連携課題 (2026-02-25)

> **参照:**
> [ArchitectureSpec.md](ArchitectureSpec.md) §6,
> [ProjectArchitecture.md](ProjectArchitecture.md),
> [DocsImplementationDiff_2026-02-24.md](DocsImplementationDiff_2026-02-24.md)

---

## 1. 概要

`ExperimentLogger` は C++ TcCOM モジュールとして実装されたファイルロギング専用コンポーネントである。
8kHz × 100 秒 = 800,000 サンプルのシステム同定用データをバイナリファイルとしてローカルディスクに記録する。
ArchitectureSpec 上は **Phase 3** で導入予定だが、C++ 実装自体は既に完了している。

---

## 2. 現在の実装状態

### 2.1 ファイル構成

| ファイル | 役割 |
|---------|------|
| `Module1.h` / `Module1.cpp` | メインロジック（データ収集・バッファリング・非同期ファイル I/O） |
| `ExperimentLoggerServices.h` | データ型定義（`ST_LogStatus`, `Module1Inputs`, `Module1Outputs`, `Module1LogControl`） |
| `ExperimentLoggerInterfaces.h` | インターフェースヘッダ |
| `ExperimentLoggerDriver.h/.cpp` | TcCOM ドライバエントリ |
| `ExperimentLoggerClassFactory.h/.cpp` | クラスファクトリ |
| `ExperimentLogger.tmc` | TwinCAT Module Class 定義 |

### 2.2 I/O 定義

#### 入力 (Data Area Input, 10 チャネル × LREAL)

| # | ポート名 | 型 | 想定ソース | CreateSymbol |
|---|---------|------|----------|-------------|
| 1 | `torque_cmd` | LREAL | DriverAdapter (`target_torque`) | ✔ |
| 2 | `ref_value` | LREAL | ExperimentSequencer (`GVL_SEQ.ref_value`) | ✔ |
| 3 | `ff_value` | LREAL | ExperimentSequencer (`GVL_SEQ.ff_value`) | — |
| 4 | `control_input` | LREAL | ControllerCore | — |
| 5 | `error` | LREAL | ControllerCore | — |
| 6 | `motor_position` | LREAL | Phase 4: DriverAdapter / Phase 1–3: ゼロ埋め | — |
| 7 | `motor_velocity` | LREAL | Phase 4: DriverAdapter / Phase 1–3: ゼロ埋め | — |
| 8 | `motor_torque_act` | LREAL | Phase 4: DriverAdapter / Phase 1–3: ゼロ埋め | — |
| 9 | `load_position` | LREAL | VirtualMotorCore (`position_out`) | — |
| 10 | `load_velocity` | LREAL | VirtualMotorCore (`velocity_out`) | — |

#### 出力 (Data Area Output)

| ポート名 | 型 | 説明 |
|---------|------|------|
| `LogStatus.records_written` | UDINT | 書き込み済みレコード数 |
| `LogStatus.file_size_kb` | UDINT | ファイルサイズ (KB) |
| `LogStatus.error_code` | UDINT | エラーコード (0 = 正常) |

#### パラメータ (ADS 経由で制御)

| パラメータ | 型 | 説明 |
|-----------|------|------|
| `LogControl.file_path` | STRING(255) | 出力先ファイルパス（デフォルト: `C:\ExperimentData\experiment_logger.bin`） |
| `LogControl.logging` | BOOL | `TRUE` でロギング開始、`FALSE` で停止 |

### 2.3 LogRecord 構造体 (96 bytes 固定長)

```cpp
#pragma pack(push, 1)
struct LogRecord
{
    ULONG     seq;              // シーケンス番号
    ULONG     reserved_pad0;    // パディング
    ULONGLONG t_ns;             // タイムスタンプ [ns]
    double    motor_position;   // Motor 側位置 [rad]
    double    motor_velocity;   // Motor 側速度 [rad/s]
    double    motor_torque_act; // Motor 実トルク [Nm]
    double    load_position;    // Load 側位置 [rad]
    double    load_velocity;    // Load 側速度 [rad/s]
    double    torque_cmd;       // 指令トルク [Nm]
    double    error;            // 位置誤差 [rad]
    double    ref_value;        // 位置指令 [rad]
    double    ff_value;         // FF 値 [Nm]
    double    control_input;    // 制御出力 [Nm]
};
#pragma pack(pop)
static_assert(sizeof(LogRecord) == 96, "LogRecord must be 96 bytes");
```

### 2.4 内部バッファ・書き込みアーキテクチャ

| 項目 | 値 |
|------|-----|
| バッファサイズ | 8,000 レコード ≈ 768 KB |
| flush 契機 | バッファ満杯時に一括 flush |
| ファイル I/O | `ITcFileAccessAsync` による非同期 I/O |
| タイムスタンプ | `seq × 1,000,000 ns`（1 ms ステップ前提） |

### 2.5 非同期ファイル FSM

```
Idle ──[logging 立ち上がり]──► OpenWait ──[完了]──► Active
                                                      │
                                [バッファ満杯] ◄──────┘
                                      │
                                      ▼
                                  WriteWait ──[完了]──► Active
                                                      │
                                [logging 立ち下がり] ◄─┘
                                      │
                                      ▼
                                  CloseWait ──[完了]──► Idle
                                  
                     ※ 任意状態 ──[エラー]──► Error
```

各状態は `EFileFsmState` で管理され、`CycleUpdate()` 内で毎サイクルポーリングにより遷移する。

### 2.6 エラーコード一覧

| コード | 定数名 | 意味 |
|--------|--------|------|
| `0xE0000001` | `kErrInvalidPath` | ファイルパス不正 |
| `0xE0000002` | `kErrInvalidFileHandle` | ファイルハンドル不正 |
| `0xE0000003` | `kErrWriteFault` | 書き込みエラー |
| `0xE0000004` | `kErrInsufficientBuffer` | バッファ不足 |
| `0xE0000005` | `kErrOpenFailed` | ファイルオープン失敗 |
| `0xE0000006` | `kErrCloseFailed` | ファイルクローズ失敗 |
| `0xE0000007` | `kErrAsyncCreateFailed` | 非同期 I/O オブジェクト生成失敗 |
| `0xE0000008` | `kErrAsyncPendingFailed` | 非同期操作の完了確認失敗 |
| `0xE0000009` | `kErrAsyncWriteShort` | 書き込みバイト数不一致 |

---

## 3. TcCOM 状態遷移

| 遷移 | 処理 |
|------|------|
| PREOP → SAFEOP | ランタイム状態リセット、出力初期化 |
| SAFEOP → OP | サイクリックタスクへの登録 (`AddModuleToCaller`) |
| OP → SAFEOP | サイクリックタスクからの除去、ログファイルクローズ、FSM リセット |
| SAFEOP → PREOP | ログファイルクローズ、ランタイムリセット |

---

## 4. モジュール連携と課題

### 4.1 連携全体像（docs 想定）

```
ControllerCore ─── control_input ──────────► ExperimentLogger.Inputs.control_input
               ─── error ─────────────────► ExperimentLogger.Inputs.error

ExperimentSequencer ─── ref_value ─────────► ExperimentLogger.Inputs.ref_value
                    ─── ff_value ──────────► ExperimentLogger.Inputs.ff_value

DriverAdapter ─── target_torque ───────────► ExperimentLogger.Inputs.torque_cmd

VirtualMotorCore ─── position_out ─────────► ExperimentLogger.Inputs.load_position
                 ─── velocity_out ─────────► ExperimentLogger.Inputs.load_velocity

(Phase 4: DriverAdapter → motor_position, motor_velocity, motor_torque_act)
```

### 4.2 課題一覧

#### 課題 P1: tsproj マッピングの完全欠落（深刻度: 高）

**状況:** ExperimentLogger の C++ プロジェクト参照は tsproj に存在するが、**インスタンス (`ExperimentLogger_Obj1`) が未作成**であり、 **`<Mappings>` にExperimentLogger への接続が一切存在しない**。

**必要な作業:**
1. TwinCAT XAE GUI で ExperimentLogger の TcCOM インスタンスを作成
2. VirtualMotorTask (1 ms) へのタスク割り当て
3. 10 本の入力すべてについてマッピングを定義

---

#### 課題 P2: `motor_torque_act` のソース不在（深刻度: 中）

**状況:** ExperimentLogger は `motor_torque_act` を入力として定義しているが、Phase 1–3 の SIL 環境ではこの値を提供するモジュールが存在しない。VirtualMotorCore はトルク実測値を出力ポートとして公開しておらず、DriverAdapter も SIL モードでは Motor 側トルクを出力しない。

**docs の方針:** Phase 1–3 ではゼロ埋め、Phase 4 で EtherCAT PDO 経由の実値を使用。

**対応選択肢:**
- (a) VirtualMotorCore にトルク出力 (`torque_out`) を追加して SIL でも意味のある値を記録
- (b) Phase 1–3 ではゼロ埋めを許容し、Phase 4 統合まで放置
- (c) ExperimentLogger 側で Motor 系入力にオプショナルフラグを追加

---

#### 課題 P3: `load_position` / `load_velocity` のソースマッピングが曖昧（深刻度: 中）

**状況:** docs では VirtualMotorCore の `position_out` → `load_position`、`velocity_out` → `load_velocity` とマッピングする想定。しかし VirtualMotorCore は**1慣性近似**であり、出力は Motor 側の応答を近似したものである。Load 側として扱うかどうかの設計意図が names 上は曖昧。

**docs の方針:** VirtualMotorCore の出力を「Load 側応答の 1 慣性近似」として `load_position` / `load_velocity` にマッピングする。

**現状:** マッピング未実施。tsproj 上の接続が必要。

---

#### 課題 P4: PLC ↔ C++ TcCOM のクロスリンク接続（深刻度: 低～中）

**状況:** `torque_cmd`, `ref_value`, `ff_value` の 3 入力のソースはそれぞれ PLC モジュール（DriverAdapter, ExperimentSequencer）の `%Q*` 変数である。C++ TcCOM の Data Area Input への接続は PLC 出力 → C++ 入力という**異なる実装方式間のクロスリンク**になるため、tsproj の Mapping GUI での設定が必要。

**注意点:** PLC 側 GVL 変数が `AT %Q*` で宣言されていることが前提。既存の `GVL_SEQ`, `GVL_DRV` では対応する出力変数が `AT %Q*` で宣言済み。

---

#### 課題 P5: ControllerCore の `error` 出力が tsproj で見えていない可能性（深刻度: 中）

**状況:** [DocsImplementationDiff_2026-02-24.md](DocsImplementationDiff_2026-02-24.md) §3.1 にて指摘済み。ControllerCore の TMC/コードには `error` 出力が存在するが、tsproj の ControllerCore インスタンス定義で `Outputs` の `ByteSize=8`（= `control_input` の 8 bytes のみ）となっており、`error` 出力が取り込まれていない可能性がある。

**必要な作業:**
1. TwinCAT XAE で ControllerCore の TMC を再読み込み
2. `Outputs` に `error` (LREAL, 8 bytes) が含まれることを確認（ByteSize=16 になるはず）
3. 確認後に ExperimentLogger へのマッピングを実施

---

#### 課題 P6: タイムスタンプの前提が 1 ms 固定（深刻度: 低）

**状況:** `kTimestampStepNs = 1,000,000 ns` がハードコードされている。Phase 4 (125 µs = 8 kHz) に移行した場合、タイムスタンプが実際のサンプリング間隔と一致しなくなる。

**対応:** Phase 4 移行時に `kTimestampStepNs` をタスク周期から動的取得するか、パラメータ化する必要がある。

---

#### 課題 P7: `motor_position` / `motor_velocity` のソースが SIL で不在（深刻度: 低）

**状況:** `motor_position`, `motor_velocity` は Phase 4 の EtherCAT PDO で Motor 側エンコーダから取得する設計。Phase 1–3 の SIL では VirtualMotorCore が 1 慣性近似のため Motor/Load を区別できず、対応するソースが存在しない。

**docs の方針:** Phase 1–3 ではゼロ埋め。

---

#### 課題 P8: ExperimentLogger の `logging` 制御と ModeManager の連携が未定義（深刻度: 低～中）

**状況:** `LogControl.logging` は ADS パラメータとして外部から制御する設計だが、ModeManager の `experiment_active` / `experiment_state` との連動ロジックが未定義。MATLAB オーケストレータが ADS 経由で `logging` を手動制御する想定だが、実験開始・終了との自動同期は実装されていない。

**考慮事項:**
- MATLAB 側で `experiment_active → TRUE` と `logging → TRUE` を同時に書き込む運用で対応可能
- ただし ADS 通信遅延によるタイミングずれのリスクがある
- 自動連動させる場合は ModeManager → ExperimentLogger の接続追加が必要

---

#### 課題 P9: ExperimentSequencer 側の暫定 SIL ログとの二重管理（深刻度: 低）

**状況:** `ExperimentSequencer` 内の `PRG_ExperimentSequencer` に暫定 SIL ログ（`GVL_SEQ_LOG` リングバッファ、200,000 サンプル）が存在する。ExperimentLogger 統合後は暫定ログの撤去が必要だが、移行スケジュールが未確定。

**docs の方針:** Phase 1 統合完了後に暫定ログを撤去し、ExperimentLogger に一本化。

---

## 5. 統合に向けたアクション（優先順）

| # | アクション | 前提条件 | ブロッカー |
|---|-----------|---------|-----------|
| 1 | ControllerCore の TMC 再読み込みで `error` 出力を tsproj に反映 | — | 課題 P5 |
| 2 | ExperimentLogger の TcCOM インスタンスを tsproj で作成 | — | 課題 P1/P7 |
| 3 | VirtualMotorTask へのタスクバインド設定 | #2 | — |
| 4 | 10 入力のマッピング定義（GUI 作業） | #1, #2, #3 | 課題 P2–P5 |
| 5 | `motor_torque_act` のソース方針決定 | — | 課題 P2 |
| 6 | MATLAB 側で `LogControl.logging` の ADS 制御を実装 | #4 | 課題 P8 |
| 7 | Phase 4 移行時の `kTimestampStepNs` 動的化 | — | 課題 P6 |
| 8 | 暫定 SIL ログ (`GVL_SEQ_LOG`) の撤去計画策定 | #4, #6 | 課題 P9 |

---

## 6. 参考: MATLAB 側での読み出し想定

```matlab
fid = fopen('C:\ExperimentData\experiment_logger.bin', 'rb');
raw = fread(fid, [12, Inf], 'double');  % ※ 先頭 16 bytes (seq + pad + t_ns) の扱いに注意
fclose(fid);
```

> 実際には先頭 16 bytes が `uint32 + uint32 + uint64` のため、MATLAB 側で `fread` のフォーマット指定を工夫するか、専用の読み出し関数を準備する必要がある。
