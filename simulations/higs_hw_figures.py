#!/usr/bin/env python3
"""Figures of the 16 kHz HIGS hardware study (book-conform designs) -> docs/operations/figures/higs16k/*.png (300 dpi) and fig4_diagram.ipe.

Python only (numpy, scipy, matplotlib, numba); reads files, touches no hardware.
  designs : simulations/hardware/designs/book_design.json (adopted linear and both design, tuning and parameters)
  FRF     : simulations/hardware/frf/frf_ms060.mat (primary, sliding), frf_ms030.mat; the design members are these Hl spliced with the
            frictionless model below the splice frequency (higs_book_design.build_setup), the loop is L = kp * C(DF) * P
  trials  : simulations/hardware/trials_book/<case>_<k>_<mode>.mat (A-B-B-A: k = 1, 4 linear, 2, 3 both; field `error` = reference - load)
            and sens_<mode>.mat / sens_<mode>_dist.mat (closed-loop sensitivity, same analysis as higs_bench_sensitivity.m)
Lab figure style: Times New Roman, 8 pt, 86 mm (one column) or 178 mm (two columns), no colour: black = linear (or the model), grey = HIGS
(or measured data); the only text inside a graph is the axis labels and the legend. `main()` regenerates every figure from the files above,
including the block diagram (Ipe source -> PDF -> PNG). The report (make_figures.py there) sets OUT_DIR and EXTS and calls the same functions.
"""
from __future__ import annotations
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import scipy.io as sio
from matplotlib import font_manager

sys.path.insert(0, str(Path(__file__).resolve().parent))
import higs_book_design as B            # noqa: E402
import higs_fig89_robustness as R       # noqa: E402

ROOT = B.ROOT
HW = ROOT / "simulations/hardware"
TRIALS = HW / "trials_book"
BOOK_JSON = HW / "designs/book_design.json"
TS = 6.25e-5
FS = 1 / TS
OUT_DIR = ROOT / "docs/operations/figures/higs16k"
EXTS = ("png", "ipe")           # fig4 also writes its Ipe source with "ipe", the PDF with "pdf"
DPI = 300
SQ = R.SQ
IPE_BIN = Path("C:/ipe/bin")
TEX_BIN = Path("C:/texlive/2025/bin/windows")

MM = 1 / 25.4
ONE, TWO = 86 * MM, 178 * MM                      # figure widths [in]
D, M, L = "#222222", "#7a7a7a", "#d0d0d0"      # black, grey, light grey: no colour
COLOR = {"linear": D, "both": M}
LABEL = {"linear": "Linear", "both": "HIGS"}
RUNS = {"linear": (1, 4), "both": (2, 3)}
CASES = {"a01m010": "0.1 rad / 0.1 s", "a10m010": "1 rad / 0.1 s", "r5m100": "5 rev / 1 s", "r5m050": "5 rev / 0.5 s",
         "a002m005": "0.02 rad / 5 ms"}
TICKS = {c: d.replace(" / ", "\n") for c, d in CASES.items()}
MOVE_START_S = 0.4            # first move of the reference starts here in every record
ENC_COUNT_RAD = 2 * np.pi / 2**20
WIN_MS = (-10.0, 120.0)       # time window of the time-domain figures [ms from move start]
FMAX_PLOT = 3000.0
FRF_MAX_PLOT = 1000.0         # the measured FRF is noise-dominated above this (|H| < -90 dB)


def set_style():
    for name in ("times.ttf", "timesi.ttf", "timesbd.ttf", "timesbi.ttf"):
        font_manager.fontManager.addfont("C:/Windows/Fonts/" + name)
    plt.rcdefaults()
    plt.rcParams.update({"font.family": "serif", "font.serif": ["Times New Roman"], "mathtext.fontset": "stix",
                         "font.size": 8, "axes.labelsize": 8, "legend.fontsize": 7, "xtick.labelsize": 7, "ytick.labelsize": 7,
                         "axes.linewidth": .6, "xtick.major.width": .6, "ytick.major.width": .6, "xtick.minor.visible": False, "ytick.minor.visible": False, "lines.linewidth": .8, "axes.spines.top": False, "axes.spines.right": False,
                         "pdf.fonttype": 42, "legend.frameon": False, "savefig.dpi": DPI})


set_style()


def db(x):
    return 20 * np.log10(np.abs(x))


def save(fig, name):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for ext in (e for e in EXTS if e in ("png", "pdf")):
        fig.savefig(OUT_DIR / f"{name}.{ext}", bbox_inches="tight", pad_inches=.02)
    plt.close(fig)
    print("saved", name)
    return name


def tidy(axs):
    for ax in np.atleast_1d(axs):
        ax.locator_params(nbins=4)
    return axs


def single(h_mm, w=ONE):
    fig, ax = plt.subplots(figsize=(w, h_mm * MM))
    tidy(ax)
    return fig, ax


def stack(n, h_mm, ratios=None, w=ONE):
    fig, axs = plt.subplots(n, 1, figsize=(w, h_mm * MM), sharex=True, gridspec_kw=dict(height_ratios=ratios or [1] * n))
    tidy(axs)
    return fig, axs


def bode(h_mm=72, w=ONE):
    return stack(2, h_mm, [1.1, 1], w)


def logx(ax, lo, hi):
    ax.set_xscale("log")
    ax.set_xlim(lo, hi)
    ax.minorticks_off()


def legend_above(ax, ncol):
    ax.legend(loc="lower right", bbox_to_anchor=(1.0, 1.0), ncol=ncol, handlelength=1.5, columnspacing=1.2, borderaxespad=.2)


def scatter_style(color=M, ms=1.8):
    return dict(ls="none", marker="o", ms=ms, mfc=color, mec=color, mew=0)


# ------------------------------------------------------------------ context
class Context:
    def __init__(self):
        self.gate, self.info = B.build_setup(log=lambda *a: None)
        self.bd = json.loads(BOOK_JSON.read_text())
        self.des = {m: self.bd["designs"][self.bd["adopted"][m]] for m in ("linear", "both")}
        self.splice = self.bd["setup"]["splice_hz"]
        self.Ds = self.info["Ds"]
        self.tab = self.gate.tab                             # numeric DF table of the design search (higs_book_design.DFTab)
        self.df = lambda wc_hz, f: R.df_analytic(2 * np.pi * np.asarray(f, float), 2 * np.pi * wc_hz / SQ)   # smooth continuous DF
        for m in self.des:                                   # the stored design reproduces the stored kp
            assert abs(self.gate.kp_for_unity(self.des[m]["design"]) / self.des[m]["kp"] - 1) < 1e-6

    def loop(self, mode, member=0, grid="M"):
        """kp * C(DF) * P on the frictionless two-inertia model grid ('M', default; smooth) or on the spliced measured member `member`
        (grid 'S'; 0 = ms060, 1 = ms030). The DF is the analytic continuous one (differs from the numeric table of the design search by < 0.3 dB)."""
        g = self.gate.S if grid == "S" else self.gate.M
        d, kp = self.des[mode]["design"], self.des[mode]["kp"]
        cs = B.ctrl_parts(g, d, self.df)[0]
        return g.f, kp * cs * g.P[member]

    def corners(self, mode="both"):
        return B.corners(self.des[mode]["design"])


# ------------------------------------------------------------------ trial data
def trial(case, k, mode):
    return sio.loadmat(TRIALS / f"{case}_{k}_{mode}.mat", squeeze_me=True, struct_as_record=False)["raw"]


def rms_mrad(x):
    return 1e3 * float(np.sqrt(np.mean(np.asarray(x, float) ** 2)))


def measured_sensitivity(mode):
    """S = mean over periods 2.. of FFT(current_cmd) / FFT(dist_value) on the excited lines (higs_bench_sensitivity.m, analyze)."""
    raw = sio.loadmat(TRIALS / f"sens_{mode}.mat", squeeze_me=True, struct_as_record=False)["raw"]
    dist = sio.loadmat(TRIALS / f"sens_{mode}_dist.mat", squeeze_me=True)
    P, k = int(dist["P"]), dist["k"].astype(int)
    n = len(raw.current_cmd) // P
    cmd, d = (np.fft.fft(np.asarray(x, float)[:n * P].reshape(n, P), axis=1)[1:, k] for x in (raw.current_cmd, raw.dist_value))
    return k * (1 / (P * TS)), cmd.mean(axis=0) / d.mean(axis=0)


def psd(x):
    """One-sided power spectral density of the record [unit^2 / Hz] (energy form: sum = mean square)."""
    n = len(x)
    X = np.fft.rfft(np.asarray(x, float))
    p = 2 * np.abs(X) ** 2 * TS / n
    p[0] /= 2
    if n % 2 == 0:
        p[-1] /= 2
    return np.fft.rfftfreq(n, TS), p


def log_average(f, p, per_octave=6, lo=1.0):
    """Mean of p in log-spaced bands (per_octave bands per octave); returns band centres and means."""
    edges = lo * 2 ** (np.arange(0, np.log2(f[-1] / lo) * per_octave + 1) / per_octave)
    idx = np.digitize(f, edges)
    fc, pm = [], []
    for i in range(1, len(edges)):
        s = idx == i
        if s.any():
            fc.append(np.sqrt(edges[i - 1] * edges[i]))
            pm.append(p[s].mean())
    return np.array(fc), np.array(pm)


def mode_psd(case, mode, channel):
    """Mean PSD over the two runs of the mode (A-B-B-A), full record."""
    ps = []
    for k in RUNS[mode]:
        f, p = psd(getattr(trial(case, k, mode), channel))
        ps.append(p)
    return f, np.mean(ps, axis=0)


def tms(r):
    return 1e3 * (r.t_s - MOVE_START_S)


# ------------------------------------------------------------------ fig 1: FRF
def phase_deg(z):
    return np.degrees(np.unwrap(np.angle(z)))


def fig1_frf(ctx):
    f = ctx.gate.M.f
    model = ctx.gate.M.P[0]
    ph = phase_deg(model)
    ph -= 360 * np.round((ph[0] + 180) / 360)
    D6 = ctx.Ds["ms060"]
    sel = (D6["f"] >= 1) & (D6["f"] <= FRF_MAX_PLOT)
    fl, Hl = D6["f"][sel], D6["Hl"][sel]
    m = np.interp(np.log(fl), np.log(f), model.real) + 1j * np.interp(np.log(fl), np.log(f), model.imag)
    phm = np.interp(np.log(fl), np.log(f), ph) + (np.degrees(np.angle(Hl / m)) + 180) % 360 - 180
    fig, axs = bode()
    axs[0].plot(fl, db(Hl), label="Measured", **scatter_style())
    axs[1].plot(fl, phm, **scatter_style())
    s = f <= FRF_MAX_PLOT
    axs[0].plot(f[s], db(model[s]), color=D, label="Model")
    axs[1].plot(f[s], ph[s], color=D)
    axs[0].set_ylabel("Magnitude [dB]")
    axs[1].set_ylabel("Phase [deg]")
    axs[1].set_xlabel("Frequency [Hz]")
    axs[1].set_yticks(np.arange(-540, 1, 180))
    axs[0].legend(loc="upper right", handlelength=1.5)
    logx(axs[1], 1, FRF_MAX_PLOT)
    fig.tight_layout(h_pad=.4)
    return save(fig, "fig1_frf")


# ------------------------------------------------------------------ fig 2 and 3: DF blocks and filters
def hw_blocks(ctx, mode, f):
    """Linear C* and DF counterpart D* = N V C* of the integrator block (omega_i / s) and the low-pass block (Butterworth), kp excluded.
    N is the analytic first-harmonic DF of the continuous HIGS (R.df_analytic, kh = 1, omega_h = omega_c / SQ); V, C* use the bilinear
    frequency of the 16 kHz controller."""
    c = B.corners(ctx.des[mode]["design"])
    sw = 1j * (2 / TS) * np.tan(2 * np.pi * f * TS / 2)
    wl = c["wl"]
    lpb = wl**2 / (sw**2 + np.sqrt(2) * wl * sw + wl**2)
    n_lp, n_i = (R.df_analytic(2 * np.pi * f, c[k] / SQ) for k in ("wc_lp", "wc_i"))
    i_lin = c["wi"] / sw
    lp_h = n_lp * (sw + c["wc_lp"]) / c["wc_lp"] * lpb
    i_h = n_i * (sw + c["wc_i"]) / c["wc_i"] * i_lin
    return dict(i=(i_lin, i_h, c["wc_i"] / SQ / (2 * np.pi)), lp=(lpb, lp_h, c["wc_lp"] / SQ / (2 * np.pi)))


def fig2_block_df(ctx):
    f = np.geomspace(0.5, FMAX_PLOT, 700)
    blk = hw_blocks(ctx, "both", f)
    names = []
    for key, name in (("i", "fig2a_block_i"), ("lp", "fig2b_block_lp")):
        lin, hg, _ = blk[key]
        fig, axs = bode()
        axs[0].plot(f, db(lin), color=D, label="Linear")
        axs[0].plot(f, db(hg), color=M, label="HIGS")
        axs[1].plot(f, phase_deg(lin), color=D)
        axs[1].plot(f, phase_deg(hg), color=M)
        axs[0].set_ylabel("Magnitude [dB]")
        axs[1].set_ylabel("Phase [deg]")
        axs[1].set_xlabel("Frequency [Hz]")
        axs[0].legend(loc="upper right" if key == "i" else "lower left", handlelength=1.5)
        logx(axs[1], 0.5, FMAX_PLOT)
        fig.tight_layout(h_pad=.4)
        names.append(save(fig, name))
    return names


def glyph_curves(ctx, n=40):
    """Magnitude [dB] over 1..3000 Hz of every block of the HIGS design, for the glyphs under the blocks of the diagram."""
    c = ctx.corners("both")
    f = np.geomspace(1., FMAX_PLOT, n)
    sw = 1j * (2 / TS) * np.tan(2 * np.pi * f * TS / 2)
    wz, bz, wp, bp = c["wi_filter"]
    wl = c["wl"]
    lpb = wl**2 / (sw**2 + np.sqrt(2) * wl * sw + wl**2)
    wi = (wp**2 / wz**2) * (sw**2 + 2 * bz * wz * sw + wz**2) / (sw**2 + 2 * bp * wp * sw + wp**2)
    resp = dict(
        flat=np.ones(n),
        nlp=R.df_analytic(2 * np.pi * f, c["wc_lp"] / SQ),
        vlp=(sw + c["wc_lp"]) / c["wc_lp"] * lpb,
        lead=(1 + sw / c["wz"]) / (1 + sw / c["wp"]),
        wi=wi, wiinv=1 / wi,
        ni=R.df_analytic(2 * np.pi * f, c["wc_i"] / SQ),
        vi=(sw + c["wc_i"]) / c["wc_i"] * c["wi"] / sw,
        notch=B.notch_fr(sw, c["notch"]),
        plant=np.interp(np.log(f), np.log(ctx.gate.M.f), np.abs(ctx.gate.M.P[0])))
    return {k: db(v) for k, v in resp.items()}


# ------------------------------------------------------------------ fig 4: block diagram (Ipe)
class Ipe:
    """Minimal Ipe XML writer: boxes, arrows, summing circles, dots and TeX labels; all strokes black, pen 0.4."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.items = []

    def _path(self, body, stroke=True, fill=None, arrow=None, pen=0.4):
        a = f' stroke="black" pen="{pen}"' if stroke else ""
        a += f' fill="{fill}"' if fill else ""
        a += f' arrow="{arrow}"' if arrow else ""
        self.items.append(f"<path{a}>\n{body}\n</path>")

    def box(self, cx, cy, w, h, label, fill=None):
        x0, x1, y0, y1 = cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2
        self._path(f"{x0:g} {y0:g} m {x1:g} {y0:g} l {x1:g} {y1:g} l {x0:g} {y1:g} l h", fill=fill)
        self.text(cx, cy, label)

    def arrow(self, *pts):
        self._path(" ".join(f"{x:g} {y:g} " + ("m" if i == 0 else "l") for i, (x, y) in enumerate(pts)), arrow="normal/small")

    def line(self, *pts):
        self._path(" ".join(f"{x:g} {y:g} " + ("m" if i == 0 else "l") for i, (x, y) in enumerate(pts)))

    def glyph(self, x0, y0, w, h, curve):
        """Tiny Bode sketch (axes without text, magnitude curve scaled to its own range) in the box [x0, x0 + w] x [y0, y0 + h]."""
        lo, hi = float(np.min(curve)), float(np.max(curve))
        span = max(hi - lo, 6.0)
        mid = (hi + lo) / 2
        xs = np.linspace(x0 + 1, x0 + w, len(curve))
        ys = y0 + h / 2 + (np.asarray(curve) - mid) / span * h * 0.85
        self._path(f"{x0:g} {y0 + h:g} m {x0:g} {y0:g} l {x0 + w:g} {y0:g} l", pen=0.2)
        self._path(" ".join(f"{x:.2f} {y:.2f} " + ("m" if i == 0 else "l") for i, (x, y) in enumerate(zip(xs, ys))), pen=0.5)

    def sum(self, cx, cy, r=5.5):
        self._path(f"{r:g} 0 0 {r:g} {cx:g} {cy:g} e")

    def dot(self, cx, cy, r=1.9):
        self._path(f"{r:g} 0 0 {r:g} {cx:g} {cy:g} e", stroke=False, fill="black")

    def text(self, x, y, tex, halign="center", valign="center"):
        self.items.append(f'<text transformations="translations" pos="{x:g} {y:g}" stroke="black" type="label" size="footnote" '
                          f'halign="{halign}" valign="{valign}">{tex}</text>')

    def xml(self):
        basic = Path(IPE_BIN.parent / "styles/basic.isy").read_text(encoding="utf-8")
        inner = basic[basic.index("<ipestyle"):basic.rindex("</ipestyle>")]
        pre = ("<preamble>\\usepackage{newtxtext,newtxmath}\\usepackage{amsmath}</preamble>")
        return ('<?xml version="1.0"?>\n<!DOCTYPE ipe SYSTEM "ipe.dtd">\n<ipe version="70218" creator="higs_hw_figures.py">\n'
                f'{inner}\n{pre}\n<layout paper="{self.w:g} {self.h:g}" origin="0 0" frame="{self.w:g} {self.h:g}"/>\n</ipestyle>\n'
                '<page>\n<layer name="alpha"/>\n<view layers="alpha" active="alpha"/>\n' + "\n".join(self.items) + "\n</page>\n</ipe>\n")


def build_diagram(ctx):
    """Block diagram of the HIGS loop as an Ipe drawing (pt, y up), following the PID structure of the book (Figs. 8.7 and 8.9):
    e -> C_lp{H} = W_lp, HIGS, W_lp^-1, V_lp -> k_p lead -> [1 | C_i{H} = W_i, HIGS, W_i^-1, V_i] -> C_n -> + (FF, d) -> P.
    The glyph under each block is its magnitude response (log f, 1..3000 Hz) computed from the design."""
    g = Ipe(0, 0)
    gc = glyph_curves(ctx)
    yt, yb, yfb, h, gap = 118., 76., 14., 24., 8.

    def run(x, y, items):
        for label, w, key in items:
            g.arrow((x, y), (x + gap, y))
            x += gap
            g.box(x + w / 2, y, w, h, label)
            g.glyph(x, y - h / 2 - 17, w, 12, gc[key])
            x += w
        return x

    def two(a, b):
        return r"\begin{tabular}{c}" + a + r"\\" + b + r"\end{tabular}"
    x1 = 30.
    g.text(6, yt + 8, "$r$")
    g.arrow((0, yt), (x1 - 5.5, yt))
    g.sum(x1, yt)
    g.text(x1 - 8, yt + 8, "$+$")
    g.text(x1 + 9, yt - 9, "$-$")
    g.text(x1 + 14, yt + 7, "$e$")
    g.line((x1 + 5.5, yt), (x1 + 15, yt))
    x = run(x1 + 15, yt, [(two(r"$W_\mathrm{lp}$", "$=1$"), 28, "flat"), (r"HIGS$_\mathrm{lp}$", 38, "nlp"),
                           (two(r"$W_\mathrm{lp}^{-1}$", "$=1$"), 28, "flat"), (r"$V_\mathrm{lp}$", 28, "vlp"), (r"$k_p\,$lead", 38, "lead")])
    xs = x + gap
    g.line((x, yt), (xs, yt))
    g.dot(xs, yt)
    g.line((xs, yt), (xs, yb))
    xb = run(xs, yb, [(r"$W_i$", 28, "wi"), (r"HIGS$_i$", 38, "ni"), (r"$W_i^{-1}$", 28, "wiinv"), (r"$V_i$", 28, "vi")])
    x2 = xb + gap
    g.line((xb, yb), (x2, yb))
    g.arrow((x2, yb), (x2, yt - 5.5))
    g.sum(x2, yt)
    g.arrow((xs, yt), (x2 - 5.5, yt))
    g.text((xs + x2) / 2, yt + 8, "$1$")
    g.text(x2 + 9, yt + 8, "$+$")
    x = run(x2 + 5.5, yt, [("$C_n$", 32, "notch")])
    x3 = x + 2 * gap + 3
    g.arrow((x, yt), (x3 - 5.5, yt))
    g.sum(x3, yt)
    g.arrow((x3, yt + 24), (x3, yt + 5.5))
    g.text(x3, yt + 31, r"FF, $d$")
    x = run(x3 + 5.5, yt, [("$P$", 36, "plant")])
    xo = x + 2 * gap
    g.line((x, yt), (xo, yt))
    g.dot(xo, yt)
    g.arrow((xo, yt), (xo + 18, yt))
    g.text(xo + 14, yt + 8, "$y$")
    g.line((xo, yt), (xo, yfb), (x1, yfb))
    g.arrow((x1, yfb), (x1, yt - 5.5))
    g.w, g.h = xo + 22, yt + 40
    return g


def fig4_diagram(ctx):
    """Writes fig4_diagram.ipe (in OUT_DIR) and converts it with Ipe (PDF) and pdftoppm (PNG, 300 dpi); returns the name."""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ipe, pdf = OUT_DIR / "fig4_diagram.ipe", OUT_DIR / "fig4_diagram.pdf"
    ipe.write_text(build_diagram(ctx).xml(), encoding="utf-8")
    env = dict(os.environ, PATH=str(TEX_BIN) + os.pathsep + os.environ["PATH"])
    subprocess.run([str(IPE_BIN / "ipetoipe.exe"), "-pdf", "-export", str(ipe), str(pdf)], check=True, env=env, capture_output=True)
    if "png" in EXTS:
        subprocess.run([str(TEX_BIN / "pdftoppm.exe"), "-png", "-r", str(DPI), "-singlefile", str(pdf), str(OUT_DIR / "fig4_diagram")], check=True)
    if "pdf" not in EXTS:
        pdf.unlink()
    if "ipe" not in EXTS:
        ipe.unlink()
    print("saved fig4_diagram")
    return "fig4_diagram"


# ------------------------------------------------------------------ fig 5: closed-loop sensitivity
def fig5_sensitivity(ctx, mode):
    fig, ax = single(54)
    f_m, S = measured_sensitivity(mode)
    f, Lm = ctx.loop(mode)
    sel = (f >= 5) & (f <= 1000)
    ax.plot(f_m, db(S), label="Measured", **scatter_style(ms=1.6))
    ax.plot(f[sel], db(1 / (1 + Lm[sel])), color=D, label="Model")
    ax.axhline(db(2.0), color=L, lw=.6, zorder=0)
    ax.set_xlabel("Frequency [Hz]")
    ax.set_ylabel("Magnitude [dB]")
    ax.set_ylim(-30, 14)
    ax.legend(loc="lower right", handlelength=1.5)
    logx(ax, 5, 1000)
    fig.tight_layout()
    return save(fig, f"fig5_sens_{mode}")


# ------------------------------------------------------------------ fig 6: time response
def time_window(case):
    """Window [ms from move start]: the first move and its settling for the short moves (a...), the whole round trip for the 5-rev cases."""
    r = trial(case, 1, "linear")
    t = np.asarray(r.t_s)
    moving = np.abs(np.gradient(np.asarray(r.ref_value, float))) > 1e-7
    idx = np.where(moving)[0]
    ends = idx[np.r_[np.where(np.diff(idx) > 200)[0], len(idx) - 1]]            # last sample of each move
    if case.startswith("r"):
        return -20.0, 1e3 * (t[ends[-1]] - MOVE_START_S) + 50.0
    return -10.0, 1e3 * (t[ends[0]] - MOVE_START_S) + 20.0


def fig6_time(case):
    """Stacked time response, runs k = 1 (linear) and k = 2 (HIGS): reference and load position, motor current, error."""
    runs = {"linear": trial(case, 1, "linear"), "both": trial(case, 2, "both")}
    win = time_window(case)
    fig, axs = stack(3, 100)
    r0 = runs["linear"]
    s = (tms(r0) >= win[0]) & (tms(r0) <= win[1])
    t = tms(r0)[s]
    axs[0].plot(t, r0.ref_value[s], color=L, lw=1.8, label="Reference")
    for m, r in runs.items():
        axs[0].plot(t, r.load_position[s], color=COLOR[m], label=LABEL[m])
        axs[1].plot(t, r.motor_current_act[s], color=COLOR[m])
        axs[2].plot(t, 1e3 * r.error[s], color=COLOR[m])
    axs[0].set_ylabel("Position [rad]")
    axs[1].set_ylabel("Input [A]")
    axs[2].set_ylabel("Error [mrad]")
    axs[2].set_xlabel("Time [ms]")
    axs[2].set_xlim(*win)
    legend_above(axs[0], 3)
    fig.tight_layout(h_pad=.5)
    return save(fig, f"fig6_time_{case}")


# ------------------------------------------------------------------ fig 7: frequency decomposition
def fig7_spectra(case="a10m010"):
    names = []
    for channel, ylab, name, scale in (("error", r"Error [mrad/$\sqrt{\mathrm{Hz}}$]", "fig7a_error_spectrum", 1e3),
                                       ("motor_current_act", r"Input [A/$\sqrt{\mathrm{Hz}}$]", "fig7b_input_spectrum", 1.0)):
        fig, ax = single(54)
        for m in ("linear", "both"):
            f, p = mode_psd(case, m, channel)
            fc, pm = log_average(f[1:], p[1:], 6, 1.0)
            ax.plot(fc, scale * np.sqrt(pm), color=COLOR[m], label=LABEL[m])
        ax.set_yscale("log")
        ax.minorticks_off()
        logx(ax, 1, FS / 2)
        ax.set_xlabel("Frequency [Hz]")
        ax.set_ylabel(ylab)
        ax.legend(loc="upper right" if channel == "error" else "lower left", handlelength=1.5)
        fig.tight_layout()
        names.append(save(fig, name))
    fig, ax = single(54)
    for m in ("linear", "both"):
        f, p = mode_psd(case, m, "error")
        c = np.sqrt(np.cumsum(p[1:]) * (f[1] - f[0]))
        assert abs(c[-1] - rms_mrad(np.concatenate([trial(case, k, m).error for k in RUNS[m]])) * 1e-3) < 0.02 * c[-1]   # Parseval
        ax.plot(f[1:], 1e3 * c, color=COLOR[m], label=LABEL[m])
    logx(ax, 1, FS / 2)
    ax.set_ylim(0, None)
    ax.set_xlabel("Frequency [Hz]")
    ax.set_ylabel("Cumulative RMS error [mrad]")
    ax.legend(loc="upper left", handlelength=1.5)
    fig.tight_layout()
    names.append(save(fig, "fig7c_cumrms"))
    return names


# ------------------------------------------------------------------ fig 8: HIGS modes
def fig8_modes(case="a10m010"):
    r = trial(case, 2, "both")
    t = tms(r)
    s = (t >= WIN_MS[0] - 0.2) & (t <= WIN_MS[1] + 0.2)
    fig, axs = stack(3, 100, [1, 1, 1.25])
    axs[0].plot(t[s], r.ref_value[s], color=L, lw=2.2, label="Reference")
    axs[0].plot(t[s], r.load_position[s], color=D, label="Load")
    axs[1].plot(t[s], 1e3 * r.error[s], color=D)
    for off, ch, lab, col in ((4, "higs_lp_mode", r"HIGS$_\mathrm{lp}$", M), (0, "higs_i_mode", r"HIGS$_i$", D)):
        axs[2].step(t[s], getattr(r, ch)[s].astype(float) + off, where="post", color=col, lw=.7, label=lab)
    axs[2].set_yticks([1, 2, 3, 5, 6, 7], ["integrator", "gain", "zero", "integrator", "gain", "zero"])
    axs[2].set_ylim(0.2, 7.8)
    axs[0].set_ylabel("Position [rad]")
    axs[1].set_ylabel("Error [mrad]")
    axs[2].set_xlabel("Time [ms]")
    axs[2].set_xlim(*WIN_MS)
    legend_above(axs[0], 2)
    legend_above(axs[2], 2)
    fig.tight_layout(h_pad=.5)
    return save(fig, "fig8_modes")


# ------------------------------------------------------------------ fig 9: summary
def fig9_summary():
    fig, ax = single(58)
    wd = 0.36
    for i, case in enumerate(CASES):
        for j, m in enumerate(("linear", "both")):
            v = np.array([rms_mrad(trial(case, k, m).error) for k in RUNS[m]])
            x = i + (j - 0.5) * wd
            ax.bar(x, v.mean(), wd * 0.92, fc="none", ec=COLOR[m], lw=.9, label=LABEL[m] if i == 0 else None)
            ax.plot(x + np.array([-0.06, 0.06]), v, ls="none", marker="o", ms=2.6, color=COLOR[m])
    ax.set_xticks(range(len(CASES)), list(TICKS.values()))
    ax.set_ylabel("Error RMS [mrad]")
    ax.legend(loc="upper right", handlelength=1.2)
    fig.tight_layout()
    return save(fig, "fig9_summary")


def main(argv=None):
    """python higs_hw_figures.py [--design designs/book_design.json] [--trials trials_book] [--out figures-dir]: every figure from one design
    file (same format as book_design.json: adopted / designs / setup) and one trial folder."""
    global BOOK_JSON, TRIALS, OUT_DIR
    ap = argparse.ArgumentParser()
    ap.add_argument("--design", type=Path, default=BOOK_JSON)
    ap.add_argument("--trials", type=Path, default=TRIALS)
    ap.add_argument("--out", type=Path, default=OUT_DIR)
    a = ap.parse_args(argv)
    BOOK_JSON, TRIALS, OUT_DIR = a.design, a.trials, a.out
    ctx = Context()
    fig1_frf(ctx)
    fig2_block_df(ctx)
    fig4_diagram(ctx)
    fig5_sensitivity(ctx, "linear")
    fig5_sensitivity(ctx, "both")
    for case in CASES:
        fig6_time(case)
    fig7_spectra()
    fig8_modes()
    fig9_summary()


if __name__ == "__main__":
    main()
