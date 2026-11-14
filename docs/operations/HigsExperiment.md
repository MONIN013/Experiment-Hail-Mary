# HIGS の二慣性系実験と設計

> **位置づけ:** HIGS の実験準備、設計根拠、再現手順  
> **対象読者:** 実機の配線・ドライブ設定を把握する実験者、制御設計者  
> **更新条件:** HIGS、制御周期、PDO 換算、設計データ、停止処理を変更したとき  
> **関連文書:** [ExperimentProcedure](./ExperimentProcedure.md) / [TechnicalReference](../architecture/TechnicalReference.md) / [DriverAdapter](../modules/DriverAdapter.md)

## 1. 今回用意したものと、実機側に残る作業

図8.9のLPブロックとIブロックに、それぞれ独立したHIGSを実装した。`exp05_Higs` は同じ線形設計から `linear`・`integrator`・`lowpass`・`both` を生成する。制御計算は既存の C++ コアを使い、MATLAB は係数設定・実験実行・ログ回収を担当する。HIGS 用に別の実時間フレームワークは作っていない。

§4・§5と保存済みの図・`simulations/results` の `summary.json`・`tracking.png`・`validation.png` は、変更前の単一HIGS（Hの折点20 Hz）に対する結果であり、現在の二HIGS構成の性能を示さない。§9は旧16 kHzデータに基づくモデル上の比較で、実機の結論ではない。実機（16 kHz）での同定・設計・比較は§11、設計指針は§10に置いた。

**要点（2026-11-14、実機、16 kHz）:**

- 装置は摩擦が支配的である。静止摩擦は0.12 A超、クーロン摩擦は約0.1 Aで、慣性は \(\bar J\approx 0.9\times10^{-4}\,\mathrm{A\,s^2/rad}\) と小さい。誤差の大半は10〜40 Hzの付着・滑り遷移で生じる（図6）。
- 実測FRFと摩擦なしモデルの両方で \(\max|S|\le 2\) とした同一ゲートで、誤差最小の linear と、教科書の分離則に従う両HIGS（both）を再調整して比べた（A–B–B–A、摩擦FFあり）。往復誤差RMSは −37%（0.1 rad/0.1 s）、−39%（1 rad/0.1 s）、−15%（5回転/1 s）だった（図8）。
- ただし「同じ \(|S|\)」は記述関数（DF）上の値である。実機で閉ループ感度を測ると、linear は最大1.9で予測と合ったが、both は150〜280 Hz で2を超え、最大3.4だった（図9）。−37〜39%の一部は、安定余裕を削って得たものである。
- 低域では both の外乱抑圧が linear の約2倍だった（11 Hz で \(|S|\) 0.40→0.21）。積分を強くできた（折点 24→48 Hz）ことが主な理由と考えられるが、切り分けは済んでいない。交差周波数を最大化した設計どうしでは差は0〜11%にとどまった。
- 代償として、200〜400 Hz のねじれは2〜4倍になる。5回転/1 sでは誤差ピークが悪化し、さらに速い軌道（8 kHz設計を流用）では both が linear より悪かった。
- 16 kHz では ELM7211 を SM-Synchron で動かす。DC-Synchron では同期エラーで運転中に OP から落ちる（§11.1）。

添付の旧 `chirp_result.mat` からモデルを求め、そのモデルに対して実際の `ControllerAlgorithm.cpp` を実行した。初回候補は、線形比較器の目標ゲイン交差周波数を 8 Hz とする。通常の往復動作では誤差 RMS が約 5.1% 減ったが、整定区間や初期値応答には悪化もある。実機で確認すべき候補であり、最適な調整値や非線形安定性を保証する値ではない。

| 項目 | 状態 |
|---|---|
| HIGS、係数反映、既存 SOS との切替 | 実装済み。C++ host tests 通過 |
| 毎周期の位置・速度・相対ねじれ保護、停止ラッチ | 実装済み。C++ host tests 通過 |
| 旧データの単位調査、FRF、二慣性モデル、設計比較 | 再現コードと結果を保存済み |
| MATLAB の preview／linear／integrator／lowpass／both 入口 | 実装済み。実機比較は `exp05_Higs` の preview で制御器を作り、試行は `matlab/tools/higs_bench/` の `higs_bench_trial` で回した。`exp05_Higs` の実機一括実行（`plant.mat` を含む）は16 kHzで未実施 |
| Windows / TwinCAT SDK でのモジュール再ビルド | 16 kHz（62.5 µs）で全モジュールをビルドし、ターゲットへ有効化済み |
| 実 EtherCAT I/O | `ExperimentHailMary.tsproj` に EK1100＋ELM7211-0011×2（SM-Synchron）を定義。CoE で定格・分解能・符号を確認し、DriverAdapter の値を tsproj に保存済み（§11.1） |

`ExperimentHailMary.RealMotor.tsproj` は EtherCAT 構成を持たない雛形のままである。

主な入口は以下のとおり。

| ファイル | 用途 |
|---|---|
| [exp05_Higs.m](../../matlab/experiment/exp05_Higs.m) | preview と4モードの単一試行 |
| [ControllerAlgorithm.cpp](../../ControllerCore/ControllerAlgorithm.cpp) | 既存 SOS と離散時間 HIGS の実計算 |
| [higs_design.json](../../simulations/higs_design.json) | 8 kHz 用の設計値、軌道、試行上限 |
| [higs_hw_design.py](../../simulations/higs_hw_design.py)、[higs_hw_figures.py](../../simulations/higs_hw_figures.py) | 実機FRFからの設計（16 kHz）と §11 の図 |
| [simulations/hardware/](../../simulations/hardware/) | 実機の生ログ（`frf/` 多重正弦と FRF、`trials/` A–B–B–A と感度）と設計（`designs/`） |
| [matlab/tools/higs_bench/](../../matlab/tools/higs_bench/README.md) | 実機試行・同定・感度測定の MATLAB 関数 |
| [identify_chirp.py](../../simulations/identify_chirp.py) | 添付形式の旧 MAT から FRF とモデルを再生成 |
| [higs_two_inertia.py](../../simulations/higs_two_inertia.py) | 実 C++ コアによる閉ループ比較、調整値の検討 |
| [identified_plant.json](../../simulations/data/identified_plant.json) | データの出所、単位、同定値、適合誤差 |
| [summary.json](../../simulations/results/summary.json) | 全ケースの数値、条件、コアの SHA-256 |

## 2. 旧データから分かったこと

旧保存コード [chirp_openloop.m](https://github.com/MONIN013/Experiment-Hail-Mary/blob/6bb96d39135b98355a68ebc68de5167a1733b87d/matlab/experiment/proto/chirp_openloop.m) は、添付と同じ変数名に対して `input` を control input [A]、`motorpos/loadpos` を [deg] と記載している。旧外部 config と取得関数の本体は履歴にないため、現在の 8 kHz・rad のログ形式をこの MAT へ適用しなかった。

| 項目 | 添付から確認した値 |
|---|---:|
| サンプリング周期 | 62.5 µs、16 kHz |
| 長さ | 100 s、1,600,000 samples |
| 周期 | 10 s × 10 周期 |
| 入力 | 振幅 0.5 A、0.4→8000 Hz の線形 chirp と整合 |
| 入力の数式照合誤差、第1周期 | 最大約 2.91×10⁻¹¹ A |
| 角度の刻み | 全点が厳密に 360 / 2²⁰ deg の整数倍 |
| 解析に用いた周期 | 第3〜10周期 |
| データ SHA-256 | `d882ff79015b8759f70110aaee2aebf039f4aa261c25994ee895e46800d8b4e4` |

`input` は電流指令として解釈する。別の実電流チャンネルは保存されていないので、同定対象は電流指令から角度までの系であり、電流ループや記録時刻の影響を含む。

位置には周期ごとに約26〜57度の移動が残り、入力にも約0.6246 mAの周期平均がある。生の位置をそのまま周期 FFT に入れるとドリフトが漏れるため、元の連続したサンプル境界で後退差分速度を求め、周期ごとのクロススペクトルから H1 推定を行った。非 DC 成分は次式で位置へ戻している。

\[
D(e^{j\omega T_s})=\frac{1-e^{-j\omega T_s}}{T_s},\qquad
\hat P_{\theta i}=\frac{\hat P_{v i}}{D(e^{j\omega T_s})}.
\]

角度は解析時に deg から rad へ換算した。coherence は残した8周期の再現性を表す。再現する非線形ひずみまで除外できる指標ではない。

### 2.1 二慣性モデルと適合範囲

motor/load を同時に 5〜700 Hz で当てはめた。入力ゲインを含む係数は独立には決まらないので、以下は \(K_t=1\) とした電流換算の有効値である。例えば \(\bar J_m=J_m/K_t\) であり、表の数値をそのまま kg·m² と読まない。

\[
\begin{aligned}
\bar J_m\ddot\theta_m&=i-\bar B_m\dot\theta_m
 -\bar K(\theta_m-\theta_\ell)-\bar C(\dot\theta_m-\dot\theta_\ell),\\
\bar J_\ell\ddot\theta_\ell&=-\bar B_\ell\dot\theta_\ell
 +\bar K(\theta_m-\theta_\ell)+\bar C(\dot\theta_m-\dot\theta_\ell).
\end{aligned}
\]

| パラメータ | 有効値 |
|---|---:|
| \(\bar J_m\) | 5.5465×10⁻⁵ |
| \(\bar J_\ell\) | 4.6691×10⁻⁵ |
| \(\bar K\) | 98.7849 |
| \(\bar C\) | 1.4814×10⁻³ |
| \(\bar B_m\) | 約 5.55×10⁻¹⁰、非負制約の下限付近 |
| \(\bar B_\ell\) | 1.03974×10⁻² |
| 減衰共振周波数 | 313.35 Hz |
| 共振の減衰比 | 0.04542 |
| motor/load 比から別に求めた反共振固有周波数 | 231.14 Hz |
| 共通の有効遅延 | 0.2400 ms、元の ZOH・記録時刻・未モデル化特性を含む |

現行 VirtualMotor の約200 Hzのプリセットと、この測定は一致しない。低周波の位相も4状態の受動モデルだけでは十分に合わず、10 Hz付近では負荷側モデルが実測より約17度進む。5〜700 Hzの複素相対誤差 RMS は motor 22.5%、load 17.6%。第3〜6周期で同定して第7〜10周期へ照合した場合は、それぞれ23.9%、19.5%だった。

![旧測定の周波数応答とモデル](../../simulations/data/identification.png)

そのため、ゲインはモデルだけで決めず、測定 FRF と各周期の応答にも直接照合した。16 kHz の FRF を8 kHzへ換算する際の ZOH 比はオフライン設計用の近似として扱い、元の `source_Ts` は保持した。電流ループや logger の対応時刻が同じとは確認できていないので、これを現行8 kHzの `plant.mat` の代わりにはしない。

## 3. 第8章から採用した構成

書籍第8章の図8.9に合わせ、次の流れで計算する。

```text
x = LP[e]; u = P[x] + I[x]; u_fb = Post[u]; output = u_fb + ff
```

線形設計は `C* = kp * Clp * lead * (1 + wi/s)` とする。LPブロックに100 Hz Butterworth LPF、P枝に `kp*lead`、Iブロックの目標に `wi/s` を割り当て、Iの後段にも `kp*lead` を置く。既定のPostは空である。

LP・Iの各ブロックは `W → element → W^-1 V` とする。既定の `W=1` に対して、線形Hは `kh*wc/(s+wc)`、`Vlp=Clp/Hlp`、`Vi=wi/(kh_i*wc_i)*(s+wc_i)/s` である。

HIGSを無効にしたブロックでも線形Hを通す。両ブロックが線形なら、分解前のPI・lead・LPFカスケードと同じ伝達特性になる。線形部分はMATLABの共通Tustin関数で離散化し、Hも通常のSOS係数として送る。

係数配列は `[lpPre; Hlp; lpPost; P; iPre; Hi; iPost; Post]` の順である。6区間の段数はHの2行を含まず、総段数は6区間の和+2（最大10）。既定では6区間が `[0,1,1,0,1,0]`、Hの2行を含めて計5行を使う。HIGSを有効にしたブロックは、対応するHの1行を非線形素子へ置き換える。

### 3.1 実装した離散時間則

実装には第8章の連続時間図をそのまま Euler 化したものを使わず、§2.4 の式(2.43)〜(2.44)の trimodal HIGS を用いた。現在入力を \(z_k\)、前回出力を \(h_{k-1}\) とすると、候補値は

\[
\hat h_k=h_{k-1}+\omega_hT_s z_k
\]

であり、次の順序で出力を決める。

1. 候補が \([\min(0,k_hz_k),\max(0,k_hz_k)]\) 内なら \(h_k=\hat h_k\)。
2. 範囲外で \(z_kz_{k-1}\ge0\) なら \(h_k=k_hz_k\)。
3. それ以外は \(h_k=0\)。

符号変化があっても、最初の sector 判定を優先する。実装は乗算のオーバーフローを避けて上下限で判定し、\(k_h>0\)、\(0<\omega_hT_s\le k_h\) を設定時に検査する。reset では前回入力・出力を0にする。SOS と HIGS の設定は同じ `SosApplyRevision` で一括反映し、不正設定は旧設定と内部状態を保ったまま拒否する。

連続時間の代表近似に合わせて

\[
\omega_c=\frac{\omega_h}{k_h}\sqrt{1+\frac{16}{\pi^2}}
\]

とした。線形部分は Tustin、HIGS は上記の後退差分型の則を使う。単一正弦波に対する位相改善の目安は設計に使えるが、複数周波数を含む実験を記述関数だけで評価しない。

### 3.2 初回候補

| 設定 | 値 |
|---|---:|
| 制御周期 | 125 µs、8 kHz |
| 線形比較器の目標ゲイン交差 | 8 Hz、旧測定 FRF のゲインに合わせる |
| \(K_p\) | 0.18660704 A/rad |
| PI の折点 | 2 Hz |
| lead の零点／極 | 2.6667 / 24 Hz |
| 2次 LPF | 100 Hz、Butterworth |
| LP / I のH折点 | 100 / 2 Hz |
| \(k_h\) | 1 |
| LP / I の \(\omega_h T_s\) | 約0.0485115 / 0.000970230 |
| LP / I の前置SOS | どちらも0段 |
| LP / I の後置SOS | 1 / 1段（Iのleadを含む） |
| 前置フィルタ \(W\) | なし |

8 Hz は線形比較器の調整目標であり、HIGS に一意の LTI ゲイン交差周波数を割り当てた値ではない。線形比較器を8/10/15/20 Hzへ調整したときの感度比較は `summary.json` の `bandwidth_comparison` に残している。

## 4. シミュレーションの結果と解釈

既存 `ControllerAlgorithm.cpp` を一時共有ライブラリへコンパイルし、Python から呼んだ。C++ と別の HIGS 近似式を閉ループへ入れた結果ではない。プラントは4状態モデルを ZOH で離散化し、電流上限、電流指令の量子化、角度量子化、遅延を含めた。

標準条件は0.1 radの往復、移動0.1 s、折返し前の停止0.2 s、前後の待機各0.4 s。7次 smoothstep を使い、始終端の速度・加速度・jerk を0にした。計1.2 s、9601 samplesである。ZOHとは別に2 samplesの遅延を置いた。これは旧記録から現在の実機遅延を確定した値ではなく、初回比較のモデル条件である。電流量子1.6 mAと角度23 bitは現行 DriverAdapter の既定値を仮定し、旧データと同じ20 bit相当も別ケースで試した。実機の変換値を確認済みという意味ではない。

### 4.1 線形の余裕と、選んだ不確かさ

| 評価 | 値 |
|---|---:|
| 名目モデルでの線形最大感度 | 1.3597 |
| 名目モデルの閉ループ固有値の最大絶対値 | 0.998971 |
| 旧測定 H1 に対する最大感度、ZOH近似補正後 | 1.4113 |
| 旧測定の8周期中の最大感度 | 1.4662 |
| 各周期へ追加0.75 msの遅延を与えた最大感度 | 1.5350 |
| 選んだ96条件のモデルでの最大感度 | 1.8454、設定上限2以内 |

96条件は \(\bar J_m,\bar J_\ell,\bar K\) を各±20%、\(\bar C\) と接地粘性を各0.5/1.5倍、追加遅延を1/4/8 samplesとした組合せである。接地粘性の \(\bar B_m,\bar B_\ell\) には同じ倍率を掛けた。\(\bar B_m\) はもともとほぼ0なので、広い範囲の motor 側粘性を調べたことにはならない。

線形系は感度の値だけでなく、SOS・プラント・遅延の閉ループ状態行列の固有値を確認した。96条件と、異なる同定帯域の3モデル、semi-implicit Euler の場合にも、この線形安定性を確認している。これらは選んだ条件での確認であり、HIGS 閉ループの大域的安定性証明ではない。

### 4.2 誤差と電流

以下は実機結果ではなく、同定モデル上の結果である。正の「改善率」は誤差 RMS の減少を表す。

| 条件 | 線形 RMS [mrad] | HIGS RMS [mrad] | 改善率 |
|---|---:|---:|---:|
| 標準往復 | 12.226 | 11.597 | 5.15% |
| 0.05 sの速い移動 | 14.533 | 13.965 | 3.91% |
| 0.2 sの遅い移動 | 9.010 | 8.753 | 2.85% |
| 1 mradの微小指令 | 0.512 | 0.518 | −1.09% |
| 0.2 radの往復 | 24.300 | 23.079 | 5.02% |
| 複数正弦波の位置指令 | 10.003 | 9.627 | 3.76% |
| 3 Hz＋313 Hzの電流指令加算 | 9.464 | 8.951 | 5.42% |
| 一定電流指令加算の on/off | 2.506 | 2.519 | −0.52% |
| 初期位置0.005 radからの復帰 | 0.251 | 0.325 | −29.69% |

標準往復について、全区間の RMS は減った一方、最後の0.2 sの RMS は5.798→6.039 mrad、最大プラント入力電流は20.8→24.0 mA、250〜380 Hzの相対ねじれ RMS は3.023→3.511 µradに増えた。全区間の RMS だけを目的にすると、整定誤差や共振帯域の振動を見落とす。

![同定モデル上の追従比較](../../simulations/results/tracking.png)

選んだ96条件では、同じ標準軌道の RMS が4.36〜8.45%減少した。その他の19条件と合わせた115組の比較では、両制御器とも試行上限内で、電流指令のクリップはなかった。全ケースの最大要求電流は64.99 mA、最大角速度4.010 rad/s、最大位置0.2222 rad、最大相対ねじれ0.0005211 radだった。

電流加算ケースは、制御器出力へ加算した後で上限制限・量子化・遅延へ通している。負荷側へ直接加わる機械的外乱トルクを試験した結果ではない。

![単一正弦波と条件別の比較](../../simulations/results/validation.png)

単一正弦波の試験では、量子化なし・振幅0.01 radで、基本波の誤差／指令振幅比の最大値は線形1.357、HIGS1.153だった。HIGSの全成分 RMS 比も併記した。この有限の振幅・周波数で得た比を、非線形系の \(H_\infty\) ノルムや任意入力に対する保証とは呼ばない。

## 5. 調整から得られた知見

**HIGS の折点を下げるだけでは良くならない。** 対応する \(H\) の折点を1 Hzへ下げると、前置フィルタなしでも要求電流が274.6 mAとなり、80 mA制限で299 samplesがクリップした。前置20 Hzフィルタを加えた場合は669.4 mA、1047 samplesだった。この条件は採用していない。post 段に通常の積分器を残しており、飽和を前提とする anti-windup の設計は行っていない。

**前置フィルタ \(W\) は、HIGS の前後で単純には相殺しない。** 第8章の \(W\to\mathrm{HIGS}\to W^{-1}V\) は、非線形素子へ入る周波数成分を調整する構成である。初回候補の20 Hzに前置20 Hzを追加すると、標準軌道の RMS は11.597→11.564 mradとわずかに減る一方、共振帯域の電流 RMS は0.1308→0.1977 mAへ約51%増えた。このデータでは、まず \(W\) なしで比較する方が因果を読み取りやすい。

**微小指令では電流分解能と摩擦の確認が先になる。** 1 mradでは改善しなかった。1.6 mAの電流指令量子化を含めており、連続値だけのシミュレーションから改善を期待できない。さらに旧0.5 A chirpで得たモデルから、微小電流時の stiction を特定できていない。

**追従と初期値応答を分けて評価する。** 目標軌道の RMS は改善しても、初期変位からの復帰は悪化した。実験では同じ停止状態から始め、全区間 RMS、移動中の最大誤差、整定区間 RMS、電流、ねじれの各値を比較する。A–B–B–Aなどの順に linear/HIGS を繰り返せば、温度や摩擦変動による偏りも確認しやすい。

**線形の感度検査と非線形安定性を混同しない。** 実装した sector 条件は HIGS 単体の性質であり、閉ループ全体の保証には別の議論が必要である。書籍§2.4や離散時間 HIGS の論文にある周波数条件・LMIを用いる場合も、切り出した線形部が満たすべき安定性などの仮定を確認する。今回の PI と位置プラントへ定理をそのまま適用したという扱いはしていない。

## 6. オフラインでの再現

以下はLinux/WSL向けの再現コマンドで、Python 3.12、g++ を用意し、リポジトリ直下で実行する。検証時は Python 3.12.14、NumPy 2.3.5、SciPy 1.17.0、Matplotlib 3.10.8、g++ 14.2.0を使った。TwinCATの実験実行とSDKビルドはWindows側で行う。

```sh
python3 -m pip install -r simulations/requirements.txt
# 元のMATを指定した場合だけ同定データを再生成する。
python3 simulations/identify_chirp.py --input /path/to/chirp_result.mat
# 同梱した同定結果からの比較は、元のMATがなくても実行できる。
OPENBLAS_NUM_THREADS=1 python3 simulations/higs_two_inertia.py --write-design
```

共有ライブラリは一時ディレクトリへ作る。設計JSONは、選択した比較ケースの運動・電流・線形安定性・感度の検査がすべて通った後で更新する。不合格の調整値を実験用JSONへ残さない。`data` と `results` は派生結果で、元の MAT は変更しない。

C++ の数値コアは次でも検査できる。

```sh
g++ -std=c++17 -Wall -Wextra -Werror -O2 -IControllerCore \
  ControllerCore/ControllerAlgorithm.cpp ControllerCore/tests/ControllerAlgorithmTests.cpp \
  -o /tmp/controller_tests
/tmp/controller_tests

g++ -std=c++17 -Wall -Wextra -Werror -O2 -IDriverAdapter -ICommonLib \
  DriverAdapter/DriverAdapterAlgorithm.cpp CommonLib/TcNumeric.cpp CommonLib/TcUnits.cpp \
  DriverAdapter/tests/DriverAdapterAlgorithmTests.cpp -o /tmp/driver_tests
/tmp/driver_tests
```

C++ホスト検査には、両HIGSの独立性、4モード、6区間の順序、線形等価性、reset、無効設定の拒否、非有限入力を含む。DriverAdapter は既存の100万scan比較に加え、各保護、同一scanのゼロ出力、通常reset後のラッチ保持、明示解除条件を検査する。これらは TwinCAT SDK ビルドや実機の停止時間の測定を代替しない。

## 7. 実機へ反映する手順

### 7.1 再ビルドと実 I/O

Windows / TwinCAT SDK 環境で ControllerCore と DriverAdapter を `Release / TwinCAT RT (x64)` で再ビルドし、XAEへ新しい TMC を反映する。リポジトリにある古い配備用 TMX は今回の追加パラメータ・Outputsを含まないため、そのまま使わない。実機構成へ適用後、新しい HIGS / Safety シンボルの readback を確認する。

実 PDO に対応づける11信号は以下である。型や単位が異なる場合は、ドライブ側の scaling か DriverAdapter の変換を合わせる。

| 向き | DriverAdapter の信号 | 現行の前提 |
|---|---|---|
| motor → runtime | `motorRaw.positionActualValue` | DINT、位置 count |
| motor → runtime | `motorRaw.velocityActualValue` | DINT、count/s |
| motor → runtime | `motorRaw.torqueActualValue` | INT、定格電流の per mille |
| motor → runtime | `motorRaw.statusWord` | UINT、StatusWord |
| load → runtime | `loadRaw.positionActualValue` | DINT、位置 count |
| load → runtime | `loadRaw.velocityActualValue` | DINT、count/s |
| load → runtime | `loadRaw.torqueActualValue` | INT、定格電流の per mille |
| load → runtime | `loadRaw.statusWord` | UINT、StatusWord |
| runtime → motor | `motorControlWordOut` | UINT、ControlWord |
| runtime → load | `loadControlWordOut` | UINT、ControlWord |
| runtime → motor | `targetTorque` | INT、定格電流の per mille 指令 |

表のraw入力は `Inputs.*`、出力は `Outputs.*` にある。load の targetTorque はこの契約に含まれない。一方、PLCは両ドライブの OPERATION_ENABLED を待つため、load 側は実験に合う動作モードとゼロトルク条件に設定する必要がある。意図しない位置保持・速度保持が働けば、今回の二慣性モデルとは異なる対象になる。

モータ側も targetTorque を受け付ける動作モードが必要で、現在の PLC は mode of operation 自体を書いていない。ドライブ型式が不明なため、mode number や SDO を推測して指定してはいない。

### 7.2 周期と換算値

両 tsproj の高速タスクは125 µsである。実際に activate した周期が8 kHzであることを確認する。旧MATの16 kHzに合わせて、現在の係数をそのまま使うことはできない。

現在の tsproj の値は両軸 `encoderResolution=1048576`、`ratedCurrentA` は motor 2.71・load 1.0（§11.1、2026-11-14にCoEで確認）。ここでの分解能は、ドライブ内の gearing/scaling を含めて、機械軸1回転で PDO が何count変わるかである。旧データは20 bit相当の刻みを持つが、現 PDO の設定を確定する情報にはならない。仮に PDO が1048576 count/revのまま23 bitの設定を使うと、角度・速度を1/8に換算し、位置・速度の保護が物理量に対して8倍緩くなる。

電流も `raw × ratedCurrentA / 1000` の前提を確認する。両軸の位置・速度の向きと、モータ電流の正方向を合わせる。`exp05_Higs` はこれらを読み取って結果へ保存するが、自動変更はしない。

DriverAdapterはPDOの鮮度やWcStateを入力として持たないため、古いフィードバックが残る通信障害は今回の位置・速度保護だけでは検出できない。実EtherCATとドライブのwatchdogによる出力停止を設定する。ControlWord=0はソフトウェア上のdisable要求であり、非常停止/STOや実停止時間を検証済みという意味ではない。

### 7.3 現行条件での再同定

PDO・符号・換算・停止動作を確認した後、現在の8 kHz環境で `experiment.scenario.exp01` / `experiment.workflow.run_exp01` を使い、別の結果ディレクトリへ `plant.mat` を作る。既存の `exp01_SysId.m` の0.25 Aや100秒はVM用の既定値なので、実機へそのまま適用しない。実機の電流上限・可動範囲に合う短い入力から、波形とログを確認して測定長を決める。今回の試行上限を再同定にも使う場合は、あらかじめXAEでDriverAdapterのSafetyLimitsと電流上限を設定し、有効にしてから開始する。

`exp01` の `Jn` / `Dn` / `sample_delay` は指定値から nominal model を作る。初期値としては同定JSONの \(\bar J_m+\bar J_\ell\approx1.02156\times10^{-4}\)、\(\bar B_m+\bar B_\ell\approx0.0103974\)、遅延2sampleを参照できるが、低域のモデル誤差と新しい測定結果を確認して採用する。旧16 kHzのFRFの `Ts` だけを書き換えて、この手順を省略しない。

`exp05_Higs` はADS接続前に、現在の周期に一致するSISOの `Pd/Pdn`、1〜500 Hz以上を含む正周波数データ、有限値、nominal線形閉ループの安定性、測定点での線形最大感度2以下を要求する。位置への離散積分で生じるDC特異点だけは除外する。データが今の装置に対応することや測定Nyquistの巻き数までは自動証明しないため、生成したファイルの出所も確認する。

### 7.4 preview と比較試行

MATLABの初回セットアップ後、previewはADS接続なしで動く。

```matlab
run('matlab/setup_matlab_environment.m')
p = exp05_Higs("preview");
```

物理設定と再同定の完了後、使用する `plant.mat` を明示して1試行ずつ実行する。

```matlab
plant_path = 'C:/experiment/current_8khz/plant.mat';
result_dir = 'C:/experiment/higs_comparison';
a = exp05_Higs("linear", "target_label", "bench-A", ...
    "plant_path", plant_path, "result_dir", result_dir);
b = exp05_Higs("both", "target_label", "bench-A", ...
    "plant_path", plant_path, "result_dir", result_dir);
```

`target_label` は記録用の名前で、接続先やVM/実機を切り替えない。接続は既存の `cfg.env` に従う。設定snapshotと `io_backend_verified=false` を結果へ保存する。実行前に同じ静止状態へ戻し、各試行のログを見てから次へ進む。

既定の試行上限は電流80 mA、両軸の相対位置0.25 rad、速度10 rad/s、相対ねじれ0.01 rad。これらはこの設計の試行条件であり、実機の定格・可動範囲から確認した値ではない。実機により厳しい上限が既に設定されていれば、`exp05_Higs` はそれを緩めず、書き込み前に拒否する。

実行中の位置・速度・ねじれ逸脱は、DriverAdapterがその計算周期で電流と両ControlWordを0にし、停止をラッチする。ホストのADSポーリングだけに停止を任せていない。終了時はmodeFlags=0、通常reset、IDLE確認、元の上限の復旧とreadback、接続closeの順に処理する。

試行ごとに `result_dir/exp05/<UTC日時+一意suffix>/` を作り、`result.mat`、`runner.mat`、失敗時の `failure.mat` を分ける。取得したrawデータを保存してから受入判定するため、比較を繰り返しても過去の結果を上書きしない。結果には電流指令・実測電流、誤差、入力換算値、制御器、設定、保護状態が含まれる。`accepted` はログ契約・完了状態・電流条件等の受入結果であり、HIGSが線形より良いことを意味しない。

`Outputs.higsLpInput/higsLpOutput/higsLpMode` と `Outputs.higsIInput/higsIOutput/higsIMode` はADS/Scopeとschema 3のbinary logで観測できる。またログの時刻列はsample番号と周期から作ったもので、実ジッタの測定値ではない。

### 7.5 保護停止後

通常resetやMATLABのcleanupでは安全ラッチを解除しない。code 1は位置、2は速度、3は相対ねじれ、4は保護設定・換算値の不正を示す。`failure.mat`で安全状態の読み取りに失敗した場合は `safety_observation_valid=false` とし、「tripなし」と断定しない。

原因を確認した後、電流出力がdisabledで、motor/load両方の入力ControlWordがoperation enableを要求していない状態で、XAEから `SafetyResetRevision` を新しい値へ更新する。危険状態で送ったrevisionは消費され、停止後に自動解除されることはない。新たな更新が必要である。相対ねじれ保護はreset時の位置からの変化を見るため、初期状態にあった軸の予圧・ねじれは測っていない。

## 8. 検証の範囲と参考資料

二HIGSへの変更ではC++数値コア試験、独立の離散則との比較、元の線形カスケードとの数値照合、TMC/tsprojの型幅とoffset照合を行った。MATLAB unit testsはR2025aで実行した（ADS接続なし）。ControllerCoreとExperimentLoggerのTwinCATモジュールをビルドし、ターゲットへ有効化してシンボルを確認した。実PDOの検証とモータの運転は未実施である（§11）。`higs_two_inertia.py` と `audit_*.py` は二HIGS化に合わせて編集したが再実行しておらず、`summary.json`・`tracking.png`・`validation.png` は編集前の単一HIGSの結果である。

- S. van den Eijnden, M. Heertjes, M. Heemels, H. Nijmeijer, *Hybrid Integrator-Gain Systems: Analysis, Design and Applications*, Springer, 2026. [DOI](https://doi.org/10.1007/978-3-032-18101-5)。第8章は印刷185〜214頁。今回のLPF整形は印刷195頁/PDF201頁、図8.7・式(8.9)〜(8.11)。離散実装は§2.4、印刷36〜38頁/PDF48〜50頁。
- B. Sharif, D. Alferink, M. Heertjes, H. Nijmeijer, M. Heemels, “Analysis of sampled-data hybrid integrator-gain systems: A discrete-time approach,” *Automatica*, 167, 111765, 2024. [DOI](https://doi.org/10.1016/j.automatica.2024.111765) / [著者所属機関の公開情報](https://research.tue.nl/en/publications/analysis-of-sampled-data-hybrid-integrator-gain-systems-a-discret/)。離散時間モデルと、仮定を満たす場合の安定性解析の出典。
- 旧取得形式の単位根拠は§2のcommit固定リンク、数値の出所と計算条件は同梱の `identified_plant.json` と `summary.json`。原データと書籍PDFはリポジトリへコピーしていない。

## 9. 同一ロバスト性での比較（2026-11-14、モデル上の結果）

### 9.1 方法

[higs_fig89_robustness.py](../../simulations/higs_fig89_robustness.py) で、図8.9の4モード（linear、積分ブロックのみHIGS、LPブロックのみHIGS、both）の交差周波数 \(f_c\) を、同じ感度制約 \(\max|S|\le 2\) の下で最大化した。

- 開ループは \(L=k_p C_{\mathrm{DF}}\,G_8\,e^{-j\omega T_s}\) とした。\(G_8\) は旧16 kHz測定FRFを8 kHzのホールドへ換算したもので、これに計算遅れ1 sampleを掛けた。帯域は1〜3990 Hzで、巻き数による安定判定を併用した。
- HIGS は記述関数（DF）で置き換えた。DF は、実装と同じ離散則（\(T_s=125\,\mu\)s）へ正弦波を入れたときの基本波から数値で求めた。振幅に依存しないことを確認した（差 1e−16）。低域 \(1\angle0^\circ\)、高域 \(1.619\,\omega_h/\omega\angle-38.1^\circ\) の漸近値が解析式と一致する。一方、離散のリセットが1 sample遅れるため、78〜99 Hz以上では解析式との差が2%を超え、500 Hz以下で最大13%になる。以降はすべて数値DFを使った。
- 2つのHIGSを含む縦続全体のDFは、各DFの積と最大32%異なった。採用した設計は、縦続全体の数値DFでも制約を満たすことを確認した。
- 設計変数は \(f_c\)、PI折点比 \(r_i\)、lead比、LPF折点、各HIGSの \(\omega_c\) である。\(W=1\) とし、後段フィルタは空にした。
- 時間応答の評価は、同定二慣性モデル、2 samples遅延、実装と同じ非線形則、80 mAのクランプで行った。FF と量子化は入れていない。
- 線形目標 \(C^*\) はそのままにしてHIGSだけを入れた「matched」と、モードごとに再調整した「retuned」を分けた。

再現手順は次のとおり。`simulations/requirements.txt` の venv が必要で、所要時間は合計約55分。1段目でG0の最適値を `results/fig89_robustness.json` に書き、2段目はそれを初期値に使う。

```text
python simulations/higs_fig89_robustness.py
python simulations/higs_fig89_robustness.py --gate-sweep
python simulations/higs_fig89_robustness.py --followup all
```

3段目（約17分）は、旧設計の形でのゲート上限と、誤差を目的にした再調整を計算する。

ゲートは次の順に厳しくした。

| ゲート | 内容 |
|---|---|
| G0 | 名目の測定FRFのみ |
| G1 | G0＋測定8周期の最悪値（名目遅延） |
| G2 | G1＋同定モデルの \(J_m,J_\ell,K\) ±10% |
| G3 | G1＋±20% |
| G4 | G3＋遅延 1/2/4 samples |
| G5 | 既存の96条件ゲート（±20%、遅延1/4/8 samples、最悪周期＋6 samples） |

### 9.2 結果

最大交差周波数 [Hz] は次のとおり（結果は [fig89_gate_sweep.json](../../simulations/results/fig89_gate_sweep.json)）。

| ゲート | linear | I | LP | both | both/linear |
|---|---:|---:|---:|---:|---:|
| G0 | 46.2 | 54.6 | 62.4 | 74.0 | +60% |
| G1〜G3 | 37.1 | 43.8 | 59.8 | 63.3 | +71% |
| G4 | 37.1 | 43.8 | 59.8 | 61.5 | +66% |
| G5 | 25.7 | 33.7 | 45.3 | 46.2 | +80% |

![ゲート別の最大交差周波数](../../simulations/results/fig89_gate_sweep.png)

G0に要素を1つずつ足したときの \(f_c\) の低下（linear / both）は次のとおり。

| 追加した要素 | linear | both |
|---|---:|---:|
| 最悪周期＋6 samples | −33% | −38% |
| 測定の最悪周期（名目遅延） | −20% | −14% |
| 名目モデルに遅延 1/4/8 samples | −8% | −17% |
| \(J_m,J_\ell,K\) ±20% | 0% | 0% |
| \(C\)・粘性 ×0.5/1.5 | 0% | 0% |

旧設計の形（LPF 100 Hz、lead比3、PI \(f_c/4\)）のまま、G5の下で交差周波数を最大化した結果は次のとおり。8 Hz設計は \(\max|S|=1.845\) で通過し、10 Hz設計は2.033で不通過だった（`summary.json` と同じ値）。

| 自由にした変数 | G5での最大 \(f_c\) [Hz] |
|---|---:|
| \(k_p\) のみ（形は8 Hz設計の絶対値のまま） | 9.5 |
| 設計 \(f_c\) と \(k_p\) の倍率（比は固定） | 11.8 |
| ＋LPF折点 | 19.5（上限300 Hz） |
| ＋lead比 | 14.5（上限5） |
| ＋PI比 | 13.0 |
| ＋LPF折点とlead比 | 25.5 |
| ＋3つすべて | 25.6 |

時間応答は、交差周波数を最大化した設計（max-fc）と、往復誤差RMSを最小化した設計（error-opt）の両方で求めた。制約はどちらも同じゲートである。

| 設計 | \(f_c\) [Hz] | 往復誤差RMS [mrad] | 整定RMS [µrad] | 負荷ステップIAE [mrad·s] | ピーク電流 [mA] | ねじれ200〜400 Hz [µrad] |
|---|---:|---:|---:|---:|---:|---:|
| 既存8 Hz linear | 8 | 12.17 | 9275 | 2.29 | 20 | 0.02 |
| 既存8 Hz both（LP 100 Hz、I 2 Hz） | 8 | 11.13 | 6378 | 2.80 | 19 | 0.22 |
| G5 linear max-fc | 25.7 | 1.69 | 638 | 0.046 | 28.5 | 0.001 |
| G5 linear error-opt | 25.5 | 1.68 | 576 | 0.043 | 28.6 | 0.001 |
| G5 both max-fc | 46.2 | 0.61 | 509 | 0.060 | 64.8 | 59 |
| G5 both error-opt | 43.9 | 0.49 | 166 | 0.020 | 35.8 | 26 |
| G1 linear error-opt | 37.1 | 0.76 | 48 | 0.017 | 27.4 | 0.001 |
| G1 both error-opt | 60.0 | 0.23 | 51 | 0.010 | 41.0 | 37 |

電流量子1.6 mAと角度20 bitの量子化を入れると、G5 error-optのRMSは linear 1.68、both 0.49 mradで、ほぼ変わらなかった。負荷ステップIAEは linear 0.073、both 0.048 mrad·sに増え、linearのねじれは1.9 µradになった。クリップはなかった。

G5の設計値は次のとおり（\(k_h=1\)、`exp05_Higs` の tuning に対応。全設計は [fig89_followup.json](../../simulations/results/fig89_followup.json) の `parameter_table`）。

| 設計 | kp [A/rad] | integral_hz | lead_zero / pole_hz | lowpass_hz | higs_lp_corner_hz | higs_i_corner_hz |
|---|---:|---:|---:|---:|---:|---:|
| linear max-fc | 1.1358 | 15.419 | 10.357 / 258.91 | 299.7 | − | − |
| linear error-opt | 1.3884 | 13.322 | 12.937 / 312.39 | 300 | − | − |
| both max-fc | 1.9803 | 51.004 | 21.017 / 278.51 | 300 | 68.124 | 4.376 |
| both error-opt | 2.5396 | 36.865 | 24.581 / 230.86 | 300 | 58.187 | 12.694 |

G0で、最良の線形 \(C^*\) にHIGSだけを入れたmatchedと、再調整したretunedを比べた。

| モード | matched RMS [mrad] | retuned RMS [mrad] | matched \(\max|S|\) |
|---|---:|---:|---:|
| I | 0.995 | 0.826 | 2.07 |
| LP | 1.105 | 0.350 | 1.50 |
| both | 0.965 | 0.273 | 1.58 |

同じ条件のretuned linearは1.04 mradだった。matchedはlinearとほぼ同じで、改善はretunedにだけ現れた。matchedの \(C^*\) はG0のlinear最適値（\(f_c\) 43.0 Hz、kp 2.1846、PI 12.49 Hz、lead 12.54/200.6 Hz、LPF 300 Hz）である。HIGSの折点は各モードのretuned値を借りた（I: 3.512 Hz、LP: 41.787 Hz、both: LP 107.070 Hz・I 8.594 Hz）。

上表の linear error-opt と both error-opt は、`exp05_Higs("preview", "design_path", ...)` で受理された（感度ゲートは measured `plant.mat` が必要なため未実行）。MATLAB が生成した SOS と HIGS の omegaTs を、変更していない `ControllerAlgorithm.cpp` に通して同定モデルで閉ループを回した。結果は RMS 1.6754 / 0.4895 mrad、ピーク 28.6 / 35.8 mA で、Python の値と一致した。

同じ2設計を、96条件のゲートモデル（±20%、\(C\)・粘性×0.5/1.5、遅延1/4/8）で、非線形則のまま時間応答で確認した。条件は往復と負荷側5 mA相当のステップである。

| 設計 | 最悪往復RMS [mrad] | 最悪ピーク電流 [mA] | 負荷ステップ最悪ピーク誤差 [mrad] | 発散・リミットサイクル | 80 mAクリップ |
|---|---:|---:|---:|---|---|
| linear error-opt | 2.52 | 42.7 | 1.93 | なし | 0/96 |
| both error-opt | 0.93 | 86.9 | 1.35 | なし | 1/96（3 samples） |

bothのクリップは \(J_m,J_\ell\)＋20%、\(K\)−20%、遅延1 sampleで、移動中の3 samplesだけだった。ピーク電流の中央値は47.7 mAで、60 mAを超える条件が6/96あり、電流上限までの余裕は小さい。電流量子化を入れると、HIGS は量子化の振れで切替を続け、末尾誤差は減衰しない。それでも末尾 RMS は both 23 µrad（中央値）、linear 117 µrad で、both の方が小さかった。

### 9.3 限界

- FRFは旧16 kHz・0.5 Aのchirpで、8 kHzへのホールド換算は近似である。現在の装置、8 kHz、現在の遅延に対応するFRFではない。
- 余裕はDF（第1高調波）による近似で、閉ループの非線形安定性を保証しない。
- 探索のばらつきは \(f_c\) で ±3〜4% ある。G1〜G4がほぼ同じ値になっていることと、利得の割合は、その範囲で不確かである。
- linear は lead比5、LPF 300 Hz の探索上限に当たっていることが多い。そのため、+60〜80%は上側寄りの見積もりである。
- max-fcのbothはピーク電流が65〜78 mAで、80 mAの試行上限に近い。error-optのbothは36〜41 mAだった。
- G1・G5の最適値の多くはLPF 300 Hzの探索上限に当たっており、内点の最適値ではない。

## 10. 設計指針

実機（§11）と教科書（van den Eijnden et al., 第2・7・8章）の照合から、次の順で設計・比較する。§9 以前の旧指針（96条件ゲート、8 kHz）はこれで置き換える。

1. **換算・符号・同期を先に確定する。** CoE で定格電流（0x6075）とエンコーダ設定（0x2010:12）を読み、短い電流パルスで位置・電流の符号を確かめる。ログ速度は真値の1/3.906なので、速度の保護値はこの比で換算する。16 kHz では ELM7211 を SM-Synchron にする。
2. **摩擦が支配的な装置では、FB の比較の前に摩擦FFを入れる。** FFなしでは、低ゲインの線形設計は付着から抜け出せない。FF（\(0.10\tanh(\dot r/0.05)+10^{-4}\ddot r\) A）は、8 kHz の旧設計で両設計の誤差を約30%減らした。
3. **ゲートは実測FRFと摩擦なしモデルの両方に課す。** 70〜150 Hz の実測FRFには、振幅に依存する摩擦の位相進みが入る。実測だけで \(|S|\le2\) とした誤差最小設計は、摩擦なしモデルでは交差付近で \(|S|=60〜246\) となり、滑っている間は安定限界に近い。
4. **比較は同一ゲートで各モードを再調整して行い、線形を探索上限に当てない。** 8 kHz で線形を lead比5・LPF 600 Hz に制限した比較では −33〜47% と出たが、上限を外し、同じゲートを課すと交差最大の設計どうしで0〜11%、誤差最小どうしで15〜39%になった。「構造だけ変えた効果（matched）」と「再設計の効果（retuned）」を分けて報告する。
5. **HIGS の折点は教科書の分離則に従う。** \(\omega_{h,lp}\) は交差周波数の1.0〜2.5倍、\(\omega_{h,i}\) は0.3〜0.7倍とする（表8.2）。これを外れた交差最大の both は、モデル上でピーク電流205 mA、ねじれ128 µradと鳴いた。分離則内の both_book は10 mA、12 µradだった。LP-HIGS が誤差帯域（< 20 Hz）でほぼゲインモードにいるのは、入力が折点より低いための正常な動作である。
6. **目的は交差周波数ではなく誤差に置く。** 効果は「DF上同じ \(|S|\) で積分を強くできること」から出ていると考えられる（積分折点 24→48 Hz）。交差最大の設計どうしでは差がほとんど出ない。
7. **DF上の余裕を実機の閉ループで確かめる。** 外乱入力にマルチサインを入れ、等速回転中に `current_cmd / dist_value` を測ると \(S\) が得られる。both は DF 上 \(\max|S|=1.99\) だったが、実測は最大3.4だった。HIGS 設計の採否は実測の \(|S|\) で決める。
8. **代償を別に監視する。** 200〜400 Hz のねじれ（2〜4倍）、ピーク電流、誤差ピーク、速い軌道での悪化を、全区間RMSとは別に判定する。
9. **DF設計の限界を明記する。** 記述関数は第1高調波の近似で、2つ以上のHIGSを含む系の安定条件は教科書でも未解決（Remark 8.3・8.5）。教科書が積分側に入れる前置フィルタ \(W_i\)（式8.14）と、DF不確かさ \(\Delta\)・\(\lambda\) の制約（式8.13）は未実装である。

## 11. 実機実験（2026-11-14、16 kHz）

データは `simulations/hardware/`（`frf/`：SM-Synchron の多重正弦ログと FRF、`trials/`：A–B–B–A の誤差最小設計と感度測定の生ログ、`designs/`：`higs_hw_design.py` の出力）、図は `simulations/higs_hw_figures.py` で再生成する（`docs/operations/figures/higs16k/`）。実機試行は `matlab/tools/higs_bench/` の関数で行う（`higs_bench_limits` で上限を書き、`higs_bench_trial` で再試行付きの1試行、`higs_bench_multisine` で同定、`higs_bench_sensitivity` で閉ループ感度）。`exp05_Higs` の実機一括実行は、事前ゲートが HIGS 設計の線形対応物（DF上の余裕を含まない）で判定するため both 設計を拒否し、FF 入力も持たないので、比較には使っていない。

保存していない生データ：§11.1 の DC-Synchron の FRF とログ、§11.3 の設計に使った DC 同期時の FRF、§11.4 の参考比較（交差最大、8 kHz 設計の再離散化）、8 kHz の実機ログは、コミット `1fc7843` の `simulations/data/hardware/` と `simulations/data/hardware16k/` にある（`git show 1fc7843:<path>`）。`designs/*.json` の `provenance` に残る `simulations/data/hardware16k/frf_ms030.mat` などのパスはこの旧配置を指す。

![図1 実測FRF（0.30 A・0.15 A）と摩擦なし設計モデル](./figures/higs16k/fig1_frf.png)

![図2 線形ブロック C* と HIGS の記述関数 D*（教科書 図8.8 相当）](./figures/higs16k/fig2_df.png)

![図3 開ループ L(jω)](./figures/higs16k/fig3_loop.png)

![図4 感度 |S| とナイキスト線図（|S| = 2 の円）](./figures/higs16k/fig4_sensitivity.png)

![図5 1 rad / 0.1 s の時間応答（実機）](./figures/higs16k/fig5_time.png)

![図6 誤差の累積RMS（教科書 図8.19 相当）](./figures/higs16k/fig6_cumrms.png)

![図7 HIGS のモード列（教科書 図8.18 相当）](./figures/higs16k/fig7_modes.png)

![図8 A–B–B–A の全試行](./figures/higs16k/fig8_summary.png)

### 11.1 装置、換算、同期

| 項目 | 値 | 根拠 |
|---|---|---|
| モータ | Beckhoff AM8111-0FH0 ×2（motor・load）、EDM35 エンコーダ | 0x2059、0x2058 |
| 定格電流 / ピーク | 2.71 A / 8.6 A、トルク定数 0.07 Nm/A、4000 rpm | 0x2059:08、製品資料 |
| `ratedCurrentA` | motor 2.71、load 1.0（0x6075） | targetTorque は 0x6075 の‰ |
| `encoderResolution` | 1048576（0x2010:12 = 20 bit、6091 = 1:1） | 位置の換算 |
| 符号 | motor +1、load −1（位置・速度） | +電流で両軸が＋へ動くことをパルスで確認 |
| 速度の換算 | ログ速度 × 3.906 = 真の速度 | 位置の微分との比較 |
| 保護値 | 電流2.71 A、位置40 rad、速度107（ログ値、真値419 rad/s）、ねじれ0.05 rad | 定格と軌道 |
| 周期 | 62.5 µs、ELM7211 は SM-Synchron | 下記 |

DC-Synchron（ESI既定：SYNC0 62.5 µs、SYNC1 = Sync Unit Cycle）は 62.5 µs で使えなかった。シフト0では SAFEOP→OP が AL `0x0032`（DC PLL sync error）で拒否される。スレーブの SYNC0 シフト20 µs、またはマスターの UserShiftTime 20 µs で OP にはなるが、通電中に数〜十数秒ごとに AL `0x002C`（SYNC0 or SYNC1 failed）で SAFEOP に落ち、ドライブは `0x8105 PD-Watchdog` を記録した。PLC は MATLAB に知らせずに IDLE へ戻るため、試行は「開始しない」タイムアウトに見えた。SM-Synchron では 14 s の試行 8/8 が完走した。ロガーは再生サンプルと同じ数・同じ先頭で記録するよう修正済み（077be91）。

### 11.2 同定

ランダム奇数マルチサイン（5〜5000 Hz、周期1 s、0.30 A と 0.15 A、開ループ）で、指令電流から位置までの FRF を測った（図1）。

- 100 Hz 付近の全慣性 \(\bar J\approx0.9\times10^{-4}\)、400 Hz 以上のモータ側 \(\bar J_m\approx4\times10^{-5}\) A·s²/rad。回転子慣性 0.029 kgcm² ÷ 0.07 Nm/A と一致する。
- モータ側の反共振 200〜250 Hz、共振 300〜350 Hz。有効遅延は約3.2 samples（0.2 ms、電流ループを含む）。
- 70 Hz 未満は摩擦の付着域で、振幅に依存する（0.15 A の方が硬く、位相が進む）。設計では 70 Hz 未満を摩擦なしモデルで置き換えた。
- 非線形ひずみ（非励振の奇数線／励振線）は 5〜20 Hz で約25%、100〜200 Hz で約7%。
- 電流パルスでは、0.08 A 以下でほぼ動かず、0.16 A で滑った。

### 11.3 設計

ゲート：0.30 A と 0.15 A の実測FRF（70〜3000 Hz、下側は摩擦なしモデル）と摩擦なしモデルの両方で \(\max|S|\le 2\)、摩擦なしモデルの時間応答でピーク指令 \(\le\) 0.25 A。線形は lead比1.5〜12、LPF 60〜3000 Hz、HIGS は分離則（§10-5）の範囲で探索し、往復誤差RMS（摩擦なしモデル）を最小にした（`higs_hw_design.py --gate measured --model-s`）。

| 設計 | 交差 | kp [A/rad] | 積分 | lead | LPF | HIGS 折点 LP / I | \(\omega_h/f_c\) |
|---|---:|---:|---:|---|---:|---|---|
| linear | 69.7 Hz（SM同期で測り直したFRFでは約83 Hz） | 4.80 | 24.4 Hz | 19.9 / 222 Hz | 3000 Hz | — | — |
| both（both_book） | 84.3 Hz（同 約86 Hz） | 5.60 | 48.0 Hz | 29.9 / 576 Hz | 330 Hz | 183.6 / 72.6 Hz | 1.35 / 0.53 |

図2は各ブロックの線形 \(C^*\) と HIGS の DF \(D^*=N V C^*\)（教科書の図8.8に相当）、図3は開ループ、図4は感度とナイキスト線図である。設計に使ったFRFは DC 同期時の測定で、SM 同期で測り直したFRFでも \(\max|S|\) の差は2〜3%だった。

### 11.4 結果

A–B–B–A（linear, both, both, linear）、摩擦FFあり、16 kHz、SM-Synchron。12 試行すべて中断なく完了した。

| 軌道 | 誤差RMS linear | 誤差RMS both | 変化 | 誤差ピーク linear → both | 電流ピーク | ねじれ 200〜400 Hz |
|---|---|---|---:|---|---|---|
| 0.1 rad / 0.1 s | 0.86, 0.95 mrad | 0.58, 0.57 mrad | −37% | 4.9〜5.6 → 3.0〜3.1 mrad | 0.13〜0.15 → 0.15〜0.16 A | 15〜19 → 30〜46 µrad |
| 1 rad / 0.1 s | 1.55, 1.49 mrad | 0.92, 0.93 mrad | −39% | 9.1〜9.5 → 5.9〜6.1 mrad | 0.26〜0.27 → 0.28〜0.29 A | 25〜38 → 106〜118 µrad |
| 5回転 / 1 s | 2.41, 2.45 mrad | 2.08, 2.04 mrad | −15% | 10.4〜11.9 → 12.2〜13.4 mrad | 0.58 → 0.66〜0.71 A | 98〜115 → 298〜318 µrad |

図5は 1 rad の時間応答、図6は誤差の累積RMS（教科書の図8.19に相当）、図7は HIGS のモード列（図8.18に相当）、図8は全試行のまとめである。

参考として、ほかの比較の結果を示す。
- 交差最大の設計どうし（linear 94 Hz、both_book 96 Hz、DC-Synchron の間に測定）では、−3%、−11%、−5% だった。
- 8 kHz の誤差最小設計（線形を lead比5・LPF 600 Hz に制限、ゲートは実測FRFのみ）を16 kHz で離散化し直して使うと、5回転/0.7 s と 0.5 s で both が linear より +15〜20% 悪かった。電流は 2.5 A まで出て、ねじれは 1.3〜1.5 mrad だった。

### 11.5 解釈と限界

- 誤差の大部分は 10〜40 Hz の付着・滑り遷移である（図6）。both はこの帯域を広く下げる。同じ \(|S|\) で積分折点を2倍にできたことが主因と考えられる。教科書の「低域外乱抑圧の改善」と同じ仕組みである。
- 速い軌道では、加速・減速に伴う大きな誤差で HIGS が非積分モードに入る時間が増え、ねじれと誤差ピークが増える。原因の切り分け（\(W_i\) の有無、DF不確かさ）は未実施である。
- 各条件は A–B–B–A の1組で、同一設計の2試行の誤差RMSの差は最大10%（linear 0.86 vs 0.95 mrad）、ねじれでは最大50%だった。設計の探索は乱数1系列で、最適性は保証しない。
- 記述関数に基づく設計で、閉ループの非線形安定性は保証しない。

### 11.6 実機で測った閉ループ感度

2 rad/s の等速回転（摩擦FFあり）に、外乱 `dist_value` として 0.05 A のランダム位相マルチサイン（5〜1000 Hz の奇数線、周期1 s）を加え、6周期測った。`current_cmd` は外乱加算後のプラント入力なので、励振線で `current_cmd / dist_value` を平均すると \(S\) になる（図9）。

| 設計 | 実測 \(\max|S|\)（5〜1000 Hz） | 11 Hz | 41 Hz | 151 Hz | 201 Hz |
|---|---|---:|---:|---:|---:|
| linear | 1.88（151 Hz） | 0.40 | 1.48 | 1.88 | 1.70 |
| both | 3.37（191 Hz） | 0.21 | 0.86 | 1.95 | 2.06 |

linear は DF 予測とほぼ一致した。both は 150〜280 Hz で予測より高く、点のばらつきも大きい。HIGS の切替による高調波と、教科書が指摘する DF 不確かさ（入力成分比への依存）が考えられる。30 Hz 未満は外乱が小さく、摩擦の影響も受けるため、予測との比較には使わない。

![図9 実機の閉ループ感度とDF予測](./figures/higs16k/fig9_measured_sensitivity.png)
- 速度換算の 3.906 倍の由来（ドライブ側の速度単位）は確認していない。保護値はこの比で設定した。
