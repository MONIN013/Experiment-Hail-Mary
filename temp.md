---
marp: true
theme: slide
paginate: true
math: latex
footer: <span style="margin-left:12pt">KOLab AKUZAWA
---
<style>
section{font-family:'Noto Sans CJK JP'}
.timeline {
  margin-top: 0.4rem;
}
.timeline-item {
  display: grid;
  grid-template-columns: 5.2rem 1.2rem 1fr;
  gap: 0.6rem;
  align-items: start;
  margin: 0.45rem 0;
}
.timeline-year {
  text-align: right;
  font-weight: 700;
  color: #36536b;
  font-size: 0.9rem;
  line-height: 1.3;
}
.timeline-marker {
  position: relative;
  min-height: 2.2rem;
}
.timeline-marker::before {
  content: "";
  position: absolute;
  left: 50%;
  top: 0;
  bottom: 0;
  width: 2px;
  transform: translateX(-50%);
  background: #b8c6d1;
}
.timeline-marker::after {
  content: "";
  position: absolute;
  left: 50%;
  top: 0.45rem;
  width: 0.6rem;
  height: 0.6rem;
  transform: translateX(-50%);
  border-radius: 50%;
  background: #36536b;
}
.timeline-body {
  font-size: 0.8rem;
  line-height: 1.35;
}
.timeline-body strong {
  display: block;
  font-size: 0.9rem;
  margin-bottom: 0.08rem;
}
.timeline-body .detail {
  display: block;
  margin-top: 0.08rem;
  color: #4b5f70;
  font-size: 0.72rem;
}
.timeline-summary {
  margin-top: 0.5rem;
  padding-top: 0.35rem;
  border-top: 1px solid #cfd8df;
  font-size: 0.78rem;
  line-height: 1.35;
}
</style>

<!-- 
_paginate: skip 
_class: title 
-->

# 動径基底関数ニューラルネットワークと先行研究の再現
## 2026年03月09日<br>古関大西研究室　阿久沢駿介

___
# 目次

## 1. 卒論発表のまとめ
## 2. 計画と経緯
## 3. RBFNNについて
## 4. 先行研究の再現
## 5. 今後の計画

___
<!-- _header: 1. 卒論発表のまとめ -->
# 卒論発表の要約

<div class="columns" style="grid-template-columns: 2fr 1fr;">
<div>

![c w:640](figs/velocity_result.svg)

</div>
<div>

## やったこと
- 外乱を成分ごとに分解
- 各成分の補償電流をRBFNNで内挿
- 実験で補償効果を検証

</div>
</div>

___
<!-- _header: 1. 卒論発表のまとめ -->
# 展望：脈動の原因究明

## 問題
速度比例および向き依存外乱の補償電流に**大きな脈動**が発生

→ おそらく**推力定数の脈動**が原因

## アプローチ
1. JMAGなどの電磁界解析ソフトで推力定数の脈動を再現できるか検証
2. 現在直列で駆動しているコアを並列に駆動することで脈動を抑制できるか検証

___
<!-- _header: 1. 卒論発表のまとめ -->
# 現状の課題

## しかしながら、どちらも動かせなかった

- **JMAG**: JMAGの操作方法や解析の進め方がまだ十分に理解できていない状態 → 北村さんに依頼
- **コア並列駆動**: CSTCAが分らない かつ 実験環境（2019a / 2017）が古く、刷新が必要

→ 卒論発表時点で示した展望に取り組む前提条件が整っていない状態

___
<!-- _header: 2. 計画と経緯 -->
# 計画失敗：経緯

## 三月中旬の大発表を完全に失念
- 春休み期間は進捗を気にしなくていいと勘違い
- そのため、技術負債を完済しつつ、チュートリアルを読もうと計画

## 2/13 高校の先輩と相談
- 「チュートリアルを初めから」などと言っている場合ではなかったが
- 結局**発表の存在に気づくことなく現在に至る**

___
<!-- _header: 2. 計画と経緯 -->
# 春休み中にやってしまったこと

技術負債の完済と基礎力強化を狙った計画：

1. **RBFNNのコード整理** — 学習手法や基底関数の選択を可能にし、先行研究の再現を可能にする
2. **実験環境の刷新** — 2019a / 2017で止まっている環境をドキュメントとして整理
3. **JMAG講習会** — 北村さんに相談
4. **TwinCATチュートリアル** — C++を含め初めからやり直す
5. **BeckhoffのCSTCA** — BeckhoffのCSTCAで動かしてみる

___
<!-- _header: 2. 計画と経緯 -->
# 反省と現状

## 実際にできたこと
- **RBFNNについての調査と整理**
- **RBFNNコードの整理**（→ 先行研究の再現で報告）
- 実験環境の刷新
- JMAG講習会とちょっとした解析
- TwinCATチュートリアルの読了とサンプルコードの理解

## できていないこと
- BeckhoffのCSTCAの活用 (現状だとCSTの機能しか使っていない)

→ 大発表の存在に気づかないまま、上記計画の a. のみ部分的に進行

___
<!-- _header: 3. RBFNNについて -->
# Radial Basis Function Neural Network とは

基本構造：入力 → RBF基底 → 線形結合

入力 $x\in\mathbb{R}^d$ に対し、$M$ 個の基底関数を配置：

$$
\phi_j(x)=\exp\!\left(-\frac{\lVert x-c_j\rVert^2}{2\sigma_j^2}\right), \quad j=1,\dots,M
$$
$$
\hat{y}(x)=\sum_{j=1}^{M} w_j\,\phi_j(x)+b
$$

- $c_j$：中心（center）、$\sigma_j$：幅（width）、$w_j$：出力重み
- **「入力空間に中心を置き、近い中心だけが強く反応する局所特徴を作って、最後に線形で混ぜる」モデル**

___
<!-- _header: 3. RBFNNについて -->
# RBFNNの学習：二段階アプローチ

## 中心・幅を固定すれば「線形回帰」になる

$N$ 個の学習データから設計行列 $\Phi\in\mathbb{R}^{N\times M}$（$\Phi_{nj}=\phi_j(x_n)$）を構成：

$$
\min_{w,b}\ \lVert \Phi w + b\mathbf{1}-y\rVert_2^2+\lambda \lVert w\rVert_2^2
$$

→ **リッジ回帰**で重みを一括推定

## 実務上の定石
1. 中心 $c_j$：k-meansで $M$ 個選定
2. 幅 $\sigma$：最近傍距離の中央値等で初期化
3. 出力重み $w$：リッジ回帰
4. $M$・$\sigma$・$\lambda$：交差検証で最適化

___
<!-- _header: 3. RBFNNについて -->
# RBFNNの実務上の要点

<div class="columns">
<div>

## 強み
- **局所モデルの足し合わせ**で解釈しやすい
- 少量データ・滑らかな入出力に有利
- **逐次更新** が可能
- 出力層が線形で学習が高速・安定

</div>
<div>

## 弱み
- 高次元・大規模データでは基底数がボトルネック
- 中心・幅の設計が性能を支配
- 特徴抽出が得意ではない
  → 深層学習に比べ不利な場面が多い

</div>
</div>

___

<!-- _header: 3. RBFNNについて -->
# 学習アルゴリズムの歴史 (第一回大発表を補完)

<div class="timeline">
  <div class="timeline-item">
    <div class="timeline-year">1971</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong>Hardy</strong>multiquadric RBF により、散乱データ補間の流れを切り開く。<span class="detail">まだ学習手法より補間可能と述べるだけだが、距離に基づく基底展開の原型になった。</span></div>
  </div>
  <div class="timeline-item">
    <div class="timeline-year">1986</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong>Micchelli</strong>条件付き正定値性に基づき、RBF 近似理論を整理する。<span class="detail">散乱データ補間を理論面から支え、後の RBFNN の土台を与えたらしい。</span></div>
  </div>
  <div class="timeline-item">
    <div class="timeline-year">1988</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong style="color: red;">Broomhead &amp; Lowe</strong>RBFNN を導入し、二段階最小二乗の枠組みを示す。<span class="detail">中心と幅を先に決め、出力重みだけを線形に解く見方が定着した。</span></div>
  </div>
  <div class="timeline-item">
    <div class="timeline-year">1989</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong style="color: red;">Moody &amp; Darken</strong>locally-tuned units により、高速な学習法を提示する。<span class="detail">MLP より軽く、局所性を活かすネットワークとして RBFNN を印象づけた。</span></div>
  </div>
  <div class="timeline-item">
    <div class="timeline-year">1990</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong>Poggio &amp; Girosi</strong>近似理論と学習理論の接続を明確にする。<span class="detail">RBF を単なる補間法でなく、汎化を考える学習モデルとして整理した。</span></div>
  </div>

___

  <div class="timeline-item">
    <div class="timeline-year">1991</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong>Park &amp; Sandberg</strong>RBFNN の万能近似性を示し、理論的基盤を固める。<span class="detail">「十分な基底があれば任意関数を近似できる」ことが支持材料になった。</span></div>
  </div>
  <div class="timeline-item">
    <div class="timeline-year">1991</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong>Chen et al.</strong>OLS による基底選択で、スパースな構造学習を進める。<span class="detail">候補基底から寄与の大きいものを順に選び、基底数の肥大化を抑えた。</span></div>
  </div>
  <div class="timeline-item">
    <div class="timeline-year">1991</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong>Platt</strong>RAN を提案し、オンラインで基底を増やす流れを作る。<span class="detail">新規性や誤差に応じて基底を追加でき、逐次学習へ道を開いた。</span></div>
  </div>

<div class="timeline">
  <div class="timeline-item">
    <div class="timeline-year">1995</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong>Orr</strong>正則化前進選択により、過学習を抑えつつ基底を選ぶ。<span class="detail">ノイズ下でも汎化しやすいよう、構造選択に正則化を持ち込んだ。</span></div>
  </div>
  <div class="timeline-item">
    <div class="timeline-year">1995</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong>Girosi, Jones, Poggio</strong>正則化理論とネットワーク表現の対応を整理する。<span class="detail">「滑らかさ制約で汎化を制御する」という見方が強まり、カーネル法への接点もできた。</span></div>
  </div>

___
  <div class="timeline-item">
    <div class="timeline-year">2001</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong>Andrieu et al.</strong>ベイズ推定と RJ-MCMC で、基底数も確率変数として扱う。<span class="detail">重みだけでなくモデル次数まで推定対象にし、選択の不確かさも扱った。</span></div>
  </div>
  <div class="timeline-item">
    <div class="timeline-year">2003</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong>Lázaro et al.</strong>EM ベースの学習で、確率的な最適化を進める。<span class="detail">非線形パラメータを尤度ベースで更新する系統として整理できる。</span></div>
  </div>
  <div class="timeline-item">
    <div class="timeline-year">2000s</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong>Kernel methods (MATLABのドキュメントなど)</strong>ガウス RBF を RBF カーネルとして捉え、SVM・KRR・GP へ接続する。<span class="detail">中心を全データに置く極限で、RBFNN はカーネル展開とほぼ同じ姿になる。</span></div>
  </div>
  <div class="timeline-item">
    <div class="timeline-year">2007</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong>Rahimi &amp; Recht</strong>ランダム特徴で、大規模カーネル近似の方向を示す。<span class="detail">RBF を明示特徴に落とし、大規模データでも線形学習へ持ち込めるようにした。</span></div>
  </div>
  <div class="timeline-item">
    <div class="timeline-year">2021</div>
    <div class="timeline-marker"></div>
    <div class="timeline-body"><strong>Määttä et al.</strong>PyTorch 実装で、勾配ベース学習と剪定を統合する。<span class="detail">現代の GPU 実装に乗せ直し、圧縮と解釈性を両立する方向に戻ってきた。</span></div>
  </div>
</div>

___
<!-- _header: 4. 先行研究の再現 -->
# 再現の目的と手法

### 目的
- RBFNNのコードを整理し、**学習手法・基底関数の選択を可能**にする
- これにより先行研究（制御への応用等）の再現を容易にする

### 整理した項目
- 基底関数：ガウス基底
- 中心選定：k-means / ランダム選択 / 全データ点
- 出力重み推定：リッジ回帰（正則化あり/なし）
- ハイパーパラメータ：$M$（基底数）、$\sigma$（幅）、$\lambda$（正則化係数）の交差検証
___
<!-- _header: 4. 先行研究の再現 -->
# 再現結果

## 暫定的な所見
- コードの整理と基底関数・学習手法の選択機能の実装は完了
- 実行時間が16時間から数分に大幅短縮

## 課題
- 中心数 $M$ と幅 $\sigma$ の組み合わせによる性能差が大きい
- 先行研究のハイパーパラメータ設定の再現に苦労している

___
<!-- _header: 4. 先行研究の再現 -->
# 再現結果 (コギング近似の先行研究)
分散の制約を設けない場合では先行研究通り、TLBOが性能が良い結果が得られた。  
ただし実行時間については、個体毎の学習フェーズがあるため極端に長い。

<!-- TODO: 結果の図をここに挿入 -->
![c w:800](figs/Figure_1.png)



___
<!-- _header: 5. 今後の計画 -->
# 今後の計画

## 短期（3月中）
- RBFNNの先行研究再現を完了させる
- 修士の研究計画のドラフトを作成する

## 中期（4月〜5月）
- CopleyのCSTCAでの動作確認・コア並列駆動の検討と実験準備
- (9-6-3モータによる初期検討)
- 推力定数の脈動の電磁界解析による検証

___
# まとめ

#### 1. 卒論発表のまとめ
- 速度比例・位置依存・向き依存の外乱補償電流を算出し実験検証
- 展望として推力定数の脈動原因究明を挙げたが、前提条件が未整備

#### 2. 計画と経緯
- 大発表を失念し、春休みは技術負債の完済を計画。アカデミックな内容皆無
- 実際に進んだが、RBFNNの調査・コード整理のみ

#### 3. 今後の計画
- RBFNN再現完了 → 実験環境刷新 → JMAG / コア並列駆動の検討へ

___
# Appendix

___
<!-- _header: Appendix -->
# 本プロジェクトの概要

## 目的
- リニアモータ制御系の**実験を高速かつ安全に回せる基盤**を整備する
- 位置指令・フィードフォワード・外乱をテーブルとして与え、**制御器の挙動を再現よく評価**する
- 将来的に、SIL から実機系へ**同じ制御構造のまま移行**できるようにする

## ねらい
- 制御器変更や指令変更のたびに大きな Build が必要な運用を減らす
- MATLAB / TwinCAT / ロガを役割分担し、実験準備と再現性を改善する

___
<!-- _header: Appendix -->
# 本プロジェクトの全体構成

## 現在の基本構成
- **MATLAB**: 実験条件生成、ADS経由のテーブル・パラメータ注入、評価
- **ExperimentSequencer (PLC ST)**: `ref / ff / dist` のテーブル再生
- **ControllerCore (C++ TcCOM)**: 誤差計算、FB制御、FF付加
- **DriverAdapter (PLC ST)**: ドライバ差異吸収、単位変換、相対位置化
- **VirtualMotorCore (C++ TcCOM)**: SIL用の仮想モータ
- **ExperimentLogger (C++ TcCOM)**: 8 kHzでの高速ロギング

## 信号の流れ
位置指令・FF・外乱 → Sequencer → Controller / DriverAdapter → VirtualMotor または実機ドライバ → Logger / MATLAB

## 現在地
- 旧 TE1400 中心の構成から、**ADS注入 + TcCOM中心の次世代構成へ移行中**
- 修士ではこの基盤を使って、**RBFNN補償・脈動原因解析・実機検証**を進める想定

___
# 後期実験実験ファイルについて


___
<!-- _header: 参考文献 -->
# 参考文献

<div class="columns" style="grid-template-columns: 1fr 1fr; gap: 1rem; font-size:0.8rem; color:#4b5f70; line-height:1.18; margin-top:0.1rem;">
<div>

- Broomhead, D. S., & Lowe, D. (1988). Multivariable Functional Interpolation and Adaptive Networks. Complex Systems, 2(3), 321–355.
- Moody, J., & Darken, C. J. (1989). Fast Learning in Networks of Locally-Tuned Processing Units. Neural Computation, 1(2), 281–294.
- Poggio, T., & Girosi, F. (1990). Networks for Approximation and Learning. Proceedings of the IEEE, 78(9), 1481–1497.
- Park, J., & Sandberg, I. W. (1991). Universal Approximation Using Radial-Basis-Function Networks. Neural Computation, 3(2), 246–257.
- Chen, S., Cowan, C. F. N., & Grant, P. M. (1991). Orthogonal least squares learning algorithm for radial basis function networks. IEEE Transactions on Neural Networks, 2(2), 302–309.
- Platt, J. C. (1991). A Resource-Allocating Network for Function Interpolation. Neural Computation, 3(2), 213–225.
- Kadirkamanathan, V., & Niranjan, M. (1993). A Function Estimation Approach to Sequential Learning with Neural Networks. Neural Computation, 5(6), 954–975.
- Orr, M. J. L. (1995). Regularization in the Selection of Radial Basis Function Centres. Neural Computation, 7(3), 606–623.
- Girosi, F., Jones, M. J., & Poggio, T. (1995). Regularization Theory and Neural Networks Architectures. Neural Computation, 7(2), 219–269.
- Lu, Y., Sundararajan, N., & Saratchandran, P. (1997). A Sequential Learning Scheme for Function Approximation Using Minimal RBF Neural Networks. Neural Computation, 9(2), 461–478.
- Andrieu, C., de Freitas, N., & Doucet, A. (2001). Robust Full Bayesian Learning for Radial Basis Networks. Neural Computation, 13(10), 2359–2407.
- ázaro, M., Santamaría, I., & Pantaleón, C. (2003). A new EM-based training algorithm for RBF networks. Neural Networks, 16(1), 69–77.

</div>
<div>

- Schölkopf, B., Sung, K.-K., Burges, C. J. C., Girosi, F., Niyogi, P., Poggio, T., & Vapnik, V. (1996). Comparing Support Vector Machines with Gaussian Kernels to Radial Basis Function Classifiers. A.I. Memo No. 1599 / CBCL Paper No. 142, Massachusetts Institute of Technology.
- Schölkopf, B., Sung, K.-K., Burges, C. J. C., Girosi, F., Niyogi, P., Poggio, T., & Vapnik, V. (1997). Comparing Support Vector Machines with Gaussian Kernels to RBF Classifiers. IEEE Transactions on Signal Processing, 45(11), 2758–2765.
- Rahimi, A., & Recht, B. (2007). Random Features for Large-Scale Kernel Machines. In Advances in Neural Information Processing Systems 20 (pp. 1177–1184).
- Bishop, C. M. (1995). *Neural Networks for Pattern Recognition*. Oxford University Press.
- Bishop, C. M. (1996). Neural Networks: A Pattern Recognition Perspective. In Handbook of Neural Computation.
- scikit-learn documentation: KernelRidge / RBF kernel / rbf_kernel.
- MathWorks documentation（日本語）: RBFネットワーク関連（newrb 等）
- Artusi, A., & Wilkie, A. Color printer characterization using radial basis function networks. In Color Imaging: Device-Independent Color, Color Hardcopy, and Graphic Arts VI, Proceedings of SPIE, 4300, 70–80.
- Oyang, Y.-J., Hwang, S.-C., Ou, Y.-Y., Chen, C.-Y., & Chen, Z.-W. (2005). Data Classification with Radial Basis Function Networks Based on a Novel Kernel Density Estimation Algorithm. IEEE Transactions on Neural Networks, 16(1), 225–236.
- Fateh, M. M., Ahmadi, S. M., & Khorashadizadeh, S. (2014). Adaptive RBF network control for robot manipulators. Journal of AI and Data Mining, 2(2), 159–166.
- Rivas, V. M., Merelo, J. J., Castillo, P. A., Arenas, M. G., & Castellano, J. G. (2004). Evolving RBF neural networks for time-series forecasting with EvRBF. Information Sciences, 165(3–4), 207–220.
- 渡邉達男 (2008). 「RBFN法を用いた自然界の時系列予測についての一考察」『小山工業高等専門学校研究紀要』40, 91–94. DOI: 10.24610/oyama.40.0_91.


</div>
</div>
