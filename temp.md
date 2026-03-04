Plan: ADS_E_PENDING 誤識別バグ修正
問題の根本原因:
TwinCAT 非同期 IO では、操作が進行中のとき FileOpen()/Check() は ADS_E_PENDING を返す。この値は failure ビット（bit 31）が立った HRESULT であり、TC1300 サンプルが FAILED_AND_NOT_PENDING() ヘルパーを使う理由もここにある。
現実装は hr == S_PENDING (S_PENDING = 0x1、success コード) で比較するため、ADS_E_PENDING を受け取ったとき FAILED(hr) が TRUE になり、pending を genuine failure と誤識別する。これが errorCode = 0x98110708 の正体。

シーケンス:

preArmReq 立ち上がり → StartAsyncOpen() → FileOpen → ADS リクエスト送出（ファイル物理生成 = 0 bytes）→ ADS_E_PENDING を返す
hr == S_PENDING が FALSE、FAILED(ADS_E_PENDING) が TRUE → エラーとして記録、m_sessionFailed = true
preArmReq は level HIGH のまま（立ち上がりエッジなし）→ ResetRuntimeState() 未呼び出し → stuck
Steps

Module1.cpp の無名名前空間に FAILED_AND_NOT_PENDING ヘルパーを追加する（TC1300 S20 の TcFsmFile.h と同パターン）

Module1.cpp:1025 を修正:

hr == S_PENDING → Pending 判定を
SUCCEEDED(hr) → Completed、FAILED_AND_NOT_PENDING(hr) → Failed、それ以外（ADS_E_PENDING）→ Pending に変更
Module1.cpp:906 を修正:

hr == S_PENDING → OPEN_WAIT 判定を
FAILED_AND_NOT_PENDING(hr) → error、FAILED(hr) → OPEN_WAIT（ADS_E_PENDING）に変更
Module1.cpp:952 を修正:

同様に S_PENDING → FAILED_AND_NOT_PENDING + FAILED(hr) パターンへ変更
Module1.cpp:998 を修正:

同様に修正
Module1.cpp:222 を TC1300 に合わせて修正:

TransitionFileAccessAsyncToState(TCOM_STATE_SAFEOP) を削除（TC1300 は SetObjStateOS でファイルアクセスオブジェクトを SAFEOP に戻さない）
AbortSession(true) は維持するが、m_sessionFailed が OP再遷移後にも残る点の注意コメントを追加
Module1.cpp:241 を TC1300 に合わせて修正:

ReleaseFileAccessAsyncObject(true) の代わりに、SAFEOP→PREOP 明示遷移をスキップし m_spFileAccessAsync = NULL 相当のシンプルな解放へ変更
OpenIssues.md の Issue #1 を更新して修正内容 (ADS_E_PENDING) を記録

Verification

TwinCAT XAE で Activate Configuration → modeFlags.bit0 = 1 書き込み → LogStatus.errorCode = 0、loggerReady = TRUE を確認
modeFlags.bit1 = 1（ExperimentStart）→ 実験実行 → run_position_command_demo.m 完走後 experiment_logger.bin のサイズ確認（> 0）
recordsWritten > 0、fileSizeKb > 0 を MATLAB ADS で読み取り
3 回連続 PASS
Decisions

S_PENDING を ADS_E_PENDING として扱う: TC1300 の FAILED_AND_NOT_PENDING ヘルパーパターンに完全準拠し、SDK 定義値に対して比較する
SetObjStateOS の明示 SAFEOP 遷移削除: TC1300 は RemoveModuleFromCaller() のみ、余分な状態遷移が OP→SAFEOP→OP サイクル時に副作用を持つ可能性を排除する




Plan: ADS_E_PENDING 誤識別バグ修正（改訂版）
TC1300 S20/S20a との差分を照合した結果、既存ドラフトに 2 点の追加修正と 1 点の調整が必要です。

確認済み TC1300 S20 の実際のパターン
場所	TC1300 S20 実コード	ローカル現状	既存プランの扱い
SetObjStateOS	RemoveModuleFromCaller() のみ	同 + AbortSession + TransitionFileAccessAsyncToState(SAFEOP)	✅ SAFEOP遷移削除を含む
SetObjStateSP	空 (return hr; のみ)	ReleaseFileAccessAsyncObject(true) + ResetRuntimeState()	⚠️ 曖昧（後述）
SetObjStateSO 失敗ロールバック	RemoveModuleFromCaller() のみ	同 + TransitionFileAccessAsyncToState(SAFEOP)	❌ プランに未記載
Pending 判定	FAILED_AND_NOT_PENDING / ADS_E_PENDING 比較	hr == S_PENDING (= 0x1 ≠ 0x98110708)	✅ 既存プランで対処済み
Steps

Module1.cpp の無名名前空間に FAILED_AND_NOT_PENDING ヘルパーを追加
inline BOOL FAILED_AND_NOT_PENDING(HRESULT hr) { return FAILED(hr) && (hr != ADS_E_PENDING); }

StartAsyncOpen (Module1.cpp L910)、StartAsyncWrite (Module1.cpp:956)、StartAsyncClose (Module1.cpp:1004) の各 hr == S_PENDING を
→ FAILED_AND_NOT_PENDING(hr) でエラー判定 + FAILED(hr) (= ADS_E_PENDING) で WAIT遷移 に変更

PollAsyncOp (Module1.cpp L1044) の hr == S_PENDING を
→ FAILED_AND_NOT_PENDING(hr) でエラー判定 + FAILED(hr) で Pending返却 に変更

SetObjStateOS (Module1.cpp L224) から
TransitionFileAccessAsyncToState(TCOM_STATE_SAFEOP) を削除 — TC1300 S20 は RemoveModuleFromCaller() のみ

SetObjStateSO (Module1.cpp L199) の AddModuleToCaller 失敗ロールバックから
TransitionFileAccessAsyncToState(TCOM_STATE_SAFEOP) を削除 — TC1300 S20 は RemoveModuleFromCaller() のみ
（これは既存プランに未記載の追加修正）

SetObjStateSP (Module1.cpp L254) を調整:
ReleaseFileAccessAsyncObject(true) (→ SAFEOP + PREOP 明示遷移) を m_spFileAccessAsync = NULL 相当のシンプルな解放に変更し、ResetRuntimeState() は維持する。
理由: TC1300 S20 は空、S20a は m_spFileAccessAsync = NULL のみ。明示的 PREOP遷移は FileAccessAsync オブジェクトが OP 状態のまま SP に入るケースで失敗リスクを持つ。ResetRuntimeState() はセッション変数リセットのため必要で維持。

OpenIssues.md の Issue #1 を更新して修正内容を記録

Verification

modeFlags.bit0 = 1 → LogStatus.errorCode = 0、loggerReady = TRUE を確認
modeFlags.bit1 = 1 → run_position_command_demo.m 完走 → recordsWritten > 0、fileSizeKb > 0 を ADS で確認
OP→SAFEOP→OP サイクルを 2 回繰り返してリーク・スタックなしを確認

Decisions

Step 5 追加: SetObjStateSO のロールバック TransitionFileAccessAsyncToState(SAFEOP) も TC1300 に合わせて削除。OP状態の FileAccessAsync を明示的に SAFEOP に戻すと、次の SO 遷移で二重遷移になるリスクがある。
SetObjStateSP の選択: 完全な空（S20）ではなく m_spFileAccessAsync = NULL + ResetRuntimeState()（S20a 寄り）を採用。繰り返し PREOP↔SAFEOP サイクルで TcCreateInstance が二重作成しないよう、SP でポインタをクリアする必要があるため。
AbortSession in SetObjStateOS は維持: TC1300 にはないが、OP→SAFEOP 時に開いているファイルを閉じるロジックは本プロジェクト固有の要件（ロガーなので必要）。ただし TransitionFileAccessAsync は削除。