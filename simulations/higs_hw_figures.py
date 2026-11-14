#!/usr/bin/env python3
"""Figures of the 16 kHz HIGS hardware study (book-conform designs) -> docs/operations/figures/higs16k/*.png.

Python only (numpy, scipy, matplotlib, numba); reads files, touches no hardware.
  designs : simulations/hardware/designs/book_design.json (adopted linear and both design, tuning and parameters)
  FRF     : simulations/hardware/frf/frf_ms060.mat (primary, sliding), frf_ms030.mat; the design members are these Hl spliced with the
            frictionless model below the splice frequency (higs_book_design.build_setup), the loop is L = kp * C(DF) * P
  trials  : simulations/hardware/trials_book/<case>_<k>_<mode>.mat (A-B-B-A: k = 1, 4 linear, 2, 3 both; field `error` = reference - load)
            and sens_<mode>.mat / sens_<mode>_dist.mat (closed-loop sensitivity, same analysis as higs_bench_sensitivity.m)
Every figure function takes the context from `Context()` and returns the saved file names; style and widths are module variables so
that another script (the report) can reuse the functions with other sizes (set_style, OUT_DIR, EXTS).
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import scipy.io as sio
from matplotlib.patches import FancyBboxPatch, Circle

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
EXTS = ("png",)
DPI = 150
SQ = R.SQ

W = 7.0                       # width of a one-axis figure [in]
C_LIN, C_HIGS, C_MEAS, C_GRAY, C_RED = "#1f5fbf", "#d4561a", "#222222", "#9a9a9a", "#b01e1e"
COLOR = {"linear": C_LIN, "both": C_HIGS}
LABEL = {"linear": "linear", "both": "HIGS (both)"}
RUNS = {"linear": (1, 4), "both": (2, 3)}
CASES = {"a01m010": "0.1 rad / 0.1 s", "a10m010": "1 rad / 0.1 s", "r5m100": "5 rev / 1 s", "r5m050": "5 rev / 0.5 s",
         "a002m005": "0.02 rad / 5 ms"}
MOVE_START_S = 0.4            # first move of the reference starts here in every record
ENC_COUNT_RAD = 2 * np.pi / 2**20


def set_style(base=14.0, width=7.0):
    global W
    W = width
    plt.rcParams.update({
        "font.size": base, "axes.titlesize": base, "axes.labelsize": base, "legend.fontsize": base * 0.9,
        "xtick.labelsize": base * 0.9, "ytick.labelsize": base * 0.9, "axes.grid": True, "grid.alpha": 0.25, "grid.linewidth": 0.5,
        "axes.axisbelow": True, "legend.framealpha": 0.9, "lines.linewidth": 2.0 * base / 14, "axes.spines.top": False,
        "axes.spines.right": False, "figure.dpi": 100, "savefig.dpi": DPI, "pdf.fonttype": 42, "legend.frameon": False,
        "axes.linewidth": 0.8 * base / 14,
    })


set_style()


def db(x):
    return 20 * np.log10(np.abs(x))


def save(fig, name):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for ext in EXTS:
        fig.savefig(OUT_DIR / f"{name}.{ext}", bbox_inches="tight", pad_inches=0.03)
    plt.close(fig)
    print("saved", name)
    return name


def fig_ax(aspect=0.62, w=None):
    w = w or W
    fig, ax = plt.subplots(figsize=(w, w * aspect))
    return fig, ax


def bode(aspect=0.95, w=None):
    w = w or W
    fig, axs = plt.subplots(2, 1, figsize=(w, w * aspect), sharex=True, gridspec_kw=dict(height_ratios=[1.15, 1]))
    return fig, axs


def logx(ax, lo, hi):
    ax.set_xscale("log")
    ax.set_xlim(lo, hi)


# ------------------------------------------------------------------ context
class Context:
    def __init__(self):
        self.gate, self.info = B.build_setup(log=lambda *a: None)
        self.bd = json.loads(BOOK_JSON.read_text())
        self.des = {m: self.bd["designs"][self.bd["adopted"][m]] for m in ("linear", "both")}
        self.splice = self.bd["setup"]["splice_hz"]
        self.Ds = self.info["Ds"]
        self.tab = self.gate.tab
        for m in self.des:                                   # the stored design reproduces the stored kp
            assert abs(self.gate.kp_for_unity(self.des[m]["design"]) / self.des[m]["kp"] - 1) < 1e-6

    def loop(self, mode, member=0, grid="S"):
        """kp * C(DF) * P on the spliced measured member `member` (0 = ms060, 1 = ms030) or on the frictionless model grid ('M')."""
        g = self.gate.S if grid == "S" else self.gate.M
        d, kp = self.des[mode]["design"], self.des[mode]["kp"]
        cs = B.ctrl_parts(g, d, self.tab)[0]
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


# ------------------------------------------------------------------ fig 1: FRF
def fig1_frf(ctx, w=None):
    f = ctx.gate.M.f
    model = ctx.gate.M.P[0]
    ph = np.degrees(np.unwrap(np.angle(model)))
    ph -= 360 * np.round((ph[0] + 180) / 360)
    fig, axs = bode(0.95, w)
    for amp, color, label, ms in (("ms030", "#8fb5ea", "measured, 0.3 A", 3), ("ms060", C_LIN, "measured, 0.6 A (sliding)", 3)):
        D = ctx.Ds[amp]
        sel = (D["f"] >= 1) & (D["f"] <= 3000)
        fl, Hl = D["f"][sel], D["Hl"][sel]
        m = np.interp(np.log(fl), np.log(f), model.real) + 1j * np.interp(np.log(fl), np.log(f), model.imag)
        phm = np.interp(np.log(fl), np.log(f), ph) + (np.degrees(np.angle(Hl / m)) + 180) % 360 - 180
        axs[0].plot(fl, db(Hl), ".", ms=ms, color=color, label=label, rasterized=True)
        axs[1].plot(fl, phm, ".", ms=ms, color=color, rasterized=True)
    sel = f <= 3000
    axs[0].plot(f[sel], db(model[sel]), color=C_MEAS, lw=1.8, label="frictionless model")
    axs[1].plot(f[sel], ph[sel], color=C_MEAS, lw=1.8)
    for ax in axs:
        ax.axvspan(1, ctx.splice, color="#e8a33a", alpha=0.16, lw=0)
        ax.axvline(ctx.splice, color="k", ls="-.", lw=1.0)
    axs[0].text(1.25, 0.04, "friction region", transform=axs[0].get_xaxis_transform(), va="bottom", color="#8a5a00")
    axs[0].text(ctx.splice * 0.93, 0.97, f"splice {ctx.splice:.0f} Hz", transform=axs[0].get_xaxis_transform(), va="top", ha="right", rotation=90)
    axs[0].set_ylabel("|Hl| [dB re rad/A]")
    axs[1].set_ylabel("phase [deg]")
    axs[1].set_xlabel("frequency [Hz]")
    axs[1].set_yticks(np.arange(-540, 1, 180))
    axs[0].legend(loc="upper right")
    logx(axs[1], 1, 3000)
    fig.tight_layout()
    return save(fig, "fig1_frf")


# ------------------------------------------------------------------ fig 2 and 3: DF blocks and elements
def hw_blocks(ctx, mode, f):
    """Linear C* and DF counterpart D* = N V C* of the integrator block (omega_i / s) and the low-pass block (Butterworth), kp excluded."""
    d = ctx.des[mode]["design"]
    c = B.corners(d)
    sw = 1j * (2 / TS) * np.tan(2 * np.pi * f * TS / 2)
    wl = c["wl"]
    lpb = wl**2 / (sw**2 + np.sqrt(2) * wl * sw + wl**2)
    n_lp, n_i = ctx.tab(c["wc_lp"] / (2 * np.pi), f), ctx.tab(c["wc_i"] / (2 * np.pi), f)
    i_lin = c["wi"] / sw
    lp_h = n_lp * (sw + c["wc_lp"]) / c["wc_lp"] * lpb
    i_h = n_i * (sw + c["wc_i"]) / c["wc_i"] * i_lin
    lead = (1 + sw / c["wz"]) / (1 + sw / c["wp"])
    g = B.Grid(f, np.ones((1, len(f))))
    assert np.allclose(lp_h * lead * (1 + i_h) * B.notch_fr(sw, c["notch"]), B.ctrl_parts(g, d, ctx.tab)[0], rtol=1e-9)
    return dict(i=(i_lin, i_h, c["wc_i"] / SQ / (2 * np.pi)), lp=(lpb, lp_h, c["wc_lp"] / SQ / (2 * np.pi)))


def fig2_block_df(ctx, w=None):
    f = np.geomspace(0.5, 3000., 700)
    blk = hw_blocks(ctx, "both", f)
    w = w or 1.55 * W
    fig, axs = plt.subplots(2, 2, figsize=(w, 0.66 * w), sharex=True)
    for col, (key, title, lin_lab) in enumerate((("i", "integrator block", r"linear $C^*$"), ("lp", "low-pass block", r"linear $C^*$"))):
        lin, hg, fh = blk[key]
        axs[0, col].plot(f, db(lin), color=C_GRAY, label=lin_lab)
        axs[0, col].plot(f, db(hg), color=C_HIGS, label=r"HIGS DF $D^*$")
        axs[1, col].plot(f, np.degrees(np.unwrap(np.angle(lin))), color=C_GRAY)
        axs[1, col].plot(f, np.degrees(np.unwrap(np.angle(hg))), color=C_HIGS)
        for ax in axs[:, col]:
            ax.axvline(fh, color="k", ls=":", lw=1.2)
        axs[0, col].text(fh * 1.1, 0.04, rf"$\omega_h/2\pi$ = {fh:.0f} Hz", transform=axs[0, col].get_xaxis_transform(), va="bottom")
        axs[0, col].set_title(title)
        axs[0, col].legend(loc="upper right" if key == "i" else "lower left")
        axs[1, col].set_xlabel("frequency [Hz]")
        logx(axs[1, col], 0.5, 3000)
    axs[0, 0].set_ylabel("magnitude [dB]")
    axs[1, 0].set_ylabel("phase [deg]")
    fig.tight_layout()
    return save(fig, "fig2_block_df")


def fig3_element(ctx, which, w=None):
    """Bare HIGS element (kh = 1): DF N vs its linear counterpart H = wc / (s + wc), wc = SQ * wh (continuous time)."""
    c = ctx.corners("both")
    wh = c["wc_lp" if which == "lp" else "wc_i"] / SQ
    fh = wh / (2 * np.pi)
    f = np.geomspace(fh / 100, fh * 50, 600)
    w_rad = 2 * np.pi * f
    n = R.df_analytic(w_rad, wh)
    h = SQ * wh / (1j * w_rad + SQ * wh)
    fig, axs = bode(0.95, w)
    axs[0].plot(f, db(h), color=C_GRAY, label=r"linear $H=\omega_c/(s+\omega_c)$")
    axs[0].plot(f, db(n), color=C_HIGS, label=r"HIGS DF $N$")
    axs[1].plot(f, np.degrees(np.unwrap(np.angle(h))), color=C_GRAY)
    axs[1].plot(f, np.degrees(np.unwrap(np.angle(n))), color=C_HIGS)
    ph_hf = np.degrees(np.angle(R.df_analytic(1e4 * wh, wh)))
    axs[1].axhline(ph_hf, color=C_HIGS, ls=":", lw=1.2)
    axs[1].text(f[0] * 1.3, ph_hf - 4, f"\u2212{abs(ph_hf):.0f}$^\\circ$", color=C_HIGS, va="top")
    for ax in axs:
        ax.axvline(fh, color="k", ls=":", lw=1.2)
    axs[0].text(fh * 1.12, 0.05, rf"$\omega_h/2\pi$ = {fh:.0f} Hz", transform=axs[0].get_xaxis_transform(), va="bottom")
    axs[0].set_ylabel("magnitude [dB]")
    axs[1].set_ylabel("phase [deg]")
    axs[1].set_xlabel("frequency [Hz]")
    axs[0].legend(loc="lower left")
    logx(axs[1], f[0], f[-1])
    fig.tight_layout()
    return save(fig, f"fig3{'a' if which == 'lp' else 'b'}_element_{which}")


def small_bode(f, curves, name, ylab, w=None, marks=(), legend="best"):
    """curves: [(complex response, label, color, linestyle)]."""
    fig, axs = bode(0.95, w)
    for r, lab, col, ls in curves:
        axs[0].plot(f, db(r), color=col, ls=ls, label=lab)
        axs[1].plot(f, np.degrees(np.unwrap(np.angle(r))), color=col, ls=ls)
    for ax in axs:
        for x in marks:
            ax.axvline(x, color="k", ls=":", lw=1.1)
    axs[0].set_ylabel(ylab)
    axs[1].set_ylabel("phase [deg]")
    axs[1].set_xlabel("frequency [Hz]")
    if any(c[1] for c in curves):
        axs[0].legend(loc=legend)
    logx(axs[1], f[0], f[-1])
    fig.tight_layout()
    return save(fig, name)


def fig3_filters(ctx, w=None):
    d = ctx.des["both"]["design"]
    c = B.corners(d)
    f = np.geomspace(1., 3000., 600)
    sw = 1j * (2 / TS) * np.tan(2 * np.pi * f * TS / 2)
    wz, bz, wp, bp = c["wi_filter"]
    wi_f = (wp**2 / wz**2) * (sw**2 + 2 * bz * wz * sw + wz**2) / (sw**2 + 2 * bp * wp * sw + wp**2)
    wl = c["wl"]
    lpb = wl**2 / (sw**2 + np.sqrt(2) * wl * sw + wl**2)
    v_i = (sw + c["wc_i"]) / c["wc_i"] * c["wi"] / sw
    v_lp = (sw + c["wc_lp"]) / c["wc_lp"] * lpb
    names = []
    names.append(small_bode(f, [(wi_f, r"$W_i$", C_HIGS, "-"), (1 / wi_f, r"$W_i^{-1}$", C_GRAY, "--")], "fig3c_wi", "magnitude [dB]", w,
                            marks=(wp / (2 * np.pi), wz / (2 * np.pi)), legend="center left"))
    names.append(small_bode(f, [(v_i, r"$V_i=H_i^{-1}\,\omega_i/s$", C_HIGS, "-")], "fig3d_vi", "magnitude [dB]", w,
                            marks=(c["wc_i"] / (2 * np.pi),), legend="upper right"))
    names.append(small_bode(f, [(v_lp, r"$V_{lp}=H_{lp}^{-1}C_{lp}$", C_HIGS, "-")], "fig3e_vlp", "magnitude [dB]", w,
                            marks=(c["wc_lp"] / (2 * np.pi), wl / (2 * np.pi)), legend="lower left"))
    names.append(small_bode(f, [(B.notch_fr(sw, c["notch"]), r"notch $C_n$", C_HIGS, "-")], "fig3f_notch", "magnitude [dB]", w,
                            marks=(c["notch"][0] / (2 * np.pi), c["notch"][2] / (2 * np.pi)), legend="lower left"))
    return names


# ------------------------------------------------------------------ fig 4: block diagram
def fig4_diagram(ctx, figw=12.0):
    t = ctx.des["both"]["tuning"]
    fs = 7.0 * figw / 7.1                     # 7 pt at the report width of 7.1 in
    fig = plt.figure(figsize=(figw, figw * 0.47))
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, 20)
    ax.set_ylim(-1.3, 8.6)
    ax.axis("off")
    ax.set_aspect("auto")
    lw = 1.3 * figw / 12

    def box(x, y, label, kind, w=2.1, h=1.1):
        face = {"higs": "#fbd9c6", "lin": "#ececec", "plant": "#d6e4f7"}[kind]
        ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.02,rounding_size=0.12", fc=face, ec="k", lw=lw, zorder=3))
        ax.text(x, y, label, ha="center", va="center", fontsize=fs * 1.12, zorder=4)
        return x - w / 2, x + w / 2

    def note(x, y, text):
        ax.text(x, y, text, ha="center", va="top", fontsize=fs * 0.93, color="#333333", linespacing=1.2)

    def arrow(p, q, **kw):
        ax.annotate("", xy=q, xytext=p, arrowprops=dict(arrowstyle="-|>", lw=lw, color="k", shrinkA=0, shrinkB=0, **kw), zorder=2)

    def line(*pts):
        ax.plot([p[0] for p in pts], [p[1] for p in pts], color="k", lw=lw, zorder=2, solid_capstyle="butt")

    def node(x, y, signs):
        ax.add_patch(Circle((x, y), 0.3, fc="white", ec="k", lw=lw, zorder=3))
        ax.plot([x - 0.3, x + 0.3], [y, y], "k", lw=lw * 0.6, zorder=4)
        ax.plot([x, x], [y - 0.3, y + 0.3], "k", lw=lw * 0.6, zorder=4)
        for (dx, dy, s) in signs:
            ax.text(x + dx, y + dy, s, ha="center", va="center", fontsize=fs, zorder=5)

    ytop, yi, ypl = 6.4, 3.7, 1.0
    # controller, top row
    ax.text(0.15, ytop + 0.15, "$r$", ha="center", va="bottom", fontsize=fs * 1.2)
    arrow((0.15, ytop), (1.1, ytop))
    node(1.4, ytop, [(-0.55, 0.45, "+"), (0.45, -0.55, "$-$")])
    arrow((1.7, ytop), (2.85, ytop))
    ax.text(2.3, ytop + 0.15, "$e$", ha="center", va="bottom", fontsize=fs * 1.1)
    l, r = box(3.8, ytop, r"HIGS$_{lp}$", "higs")
    arrow((r, ytop), (5.7, ytop))
    l, r = box(6.8, ytop, r"$V_{lp}$", "lin")
    line((r, ytop), (8.3, ytop))
    ax.plot(8.3, ytop, "ko", ms=4 * figw / 12 + 1.5, zorder=4)
    note(3.8, ytop - 0.7, f"nonlinear LPF\n$\\omega_h$ = {t['higs_lp_corner_hz'] / SQ:.0f} Hz")
    note(6.8, ytop - 0.7, "restores $C_{lp}$\n(2nd-order LPF)")
    # P branch
    arrow((8.3, ytop), (9.9, ytop))
    l, r = box(11.0, ytop, r"$k_p\,$lead", "lin")
    note(11.0, ytop - 0.7, f"$k_p$ = {t['kp']:.1f} A/rad\nlead {t['lead_zero_hz']:.0f} / {t['lead_pole_hz']:.0f} Hz")
    arrow((r, ytop), (15.45, ytop))
    node(15.75, ytop, [(-0.2, 0.55, "+"), (0.55, -0.45, "+")])
    # I branch
    line((8.3, ytop), (8.3, yi))
    arrow((8.3, yi), (8.75, yi))
    l, r = box(9.8, yi, r"$W_i$", "lin", w=2.0)
    arrow((r, yi), (11.2, yi))
    l, r = box(12.3, yi, r"HIGS$_i$", "higs", w=2.0)
    arrow((r, yi), (13.7, yi))
    l, r = box(14.8, yi, r"$V_i$", "lin", w=2.0)
    line((r, yi), (15.75, yi))
    arrow((15.75, yi), (15.75, ytop - 0.31))
    note(9.8, yi - 0.7, f"skew notch\n{t['wi_pole_hz']:.0f} Hz / {t['wi_zero_hz'] / 1e3:.1f} kHz")
    note(12.3, yi - 0.7, f"nonlinear integrator\n$\\omega_h$ = {t['higs_i_corner_hz'] / SQ:.0f} Hz")
    note(14.8, yi - 0.7, f"restores $\\omega_i/s$\n$\\omega_i/2\\pi$ = {t['integral_hz']:.0f} Hz")
    # notch and wrap to the plant row
    arrow((16.05, ytop), (16.7, ytop))
    l, r = box(17.75, ytop, r"$C_n$", "lin", w=2.0)
    note(17.75, ytop - 0.7, f"notch {t['notch_zero_hz']:.0f} / {t['notch_pole_hz']:.0f} Hz")
    line((r, ytop), (19.6, ytop), (19.6, ypl))
    ax.text(19.3, ytop + 0.15, "$u_c$", ha="center", va="bottom", fontsize=fs * 1.1)
    # plant row (right to left)
    arrow((19.6, ypl), (18.3, ypl))
    node(18.0, ypl, [(0.0, 0.62, "+"), (0.5, -0.5, "+")])
    arrow((18.0, ypl - 1.3), (18.0, ypl - 0.31))
    ax.text(18.0, ypl - 1.4, "friction FF", ha="center", va="top", fontsize=fs)
    arrow((17.7, ypl), (16.3, ypl))
    node(16.0, ypl, [(0.0, 0.62, "+"), (0.5, -0.5, "+")])
    arrow((16.0, ypl - 1.3), (16.0, ypl - 0.31))
    ax.text(16.0, ypl - 1.4, "disturbance $d$", ha="center", va="top", fontsize=fs)
    arrow((15.7, ypl), (14.5, ypl))
    l, r = box(13.4, ypl, "current\nloop", "plant", w=2.2, h=1.2)
    arrow((l, ypl), (11.7, ypl))
    l, r = box(10.7, ypl, "motor\n$J_m$", "plant", w=2.0, h=1.2)
    arrow((l, ypl), (9.0, ypl))
    l, r = box(8.0, ypl, "shaft\n$k,\\ c$", "plant", w=2.0, h=1.2)
    arrow((l, ypl), (6.3, ypl))
    l, r = box(5.3, ypl, "load\n$J_l$", "plant", w=2.0, h=1.2)
    line((l, ypl), (3.4, ypl))
    ax.plot(3.4, ypl, "ko", ms=4 * figw / 12 + 1.5, zorder=4)
    arrow((3.4, ypl), (3.4, ypl - 0.85))
    ax.text(3.65, ypl - 0.95, "$y_{load}$", ha="left", va="center", fontsize=fs * 1.15)
    line((3.4, ypl), (1.4, ypl))
    arrow((1.4, ypl), (1.4, ytop - 0.31))
    note(13.4, ypl - 0.75, "incl. 3-sample delay")
    ax.text(0.5, 8.35, "controller", fontsize=fs * 1.1, va="top", fontweight="bold")
    ax.text(0.5, 2.95, "plant", fontsize=fs * 1.1, va="top", fontweight="bold")
    return save(fig, "fig4_diagram")


# ------------------------------------------------------------------ fig 5: measured vs DF sensitivity
def fig5_sensitivity(ctx, mode, w=None):
    fig, ax = fig_ax(0.62, w)
    f_m, S = measured_sensitivity(mode)
    f, L = ctx.loop(mode)
    sel = (f >= 5) & (f <= 1000)
    ax.plot(f[sel], np.abs(1 / (1 + L[sel])), color=COLOR[mode], lw=2.0, label="DF prediction")
    ax.plot(f_m, np.abs(S), "o", ms=3.6 * W / 7, color=C_MEAS, mfc="none", mew=0.8, label="measured")
    ax.axhline(2.0, color=C_RED, lw=1.5, ls="--")
    ax.text(5.5, 1.95, r"$|S|=2$", color=C_RED, va="top")
    ax.set_xlabel("frequency [Hz]")
    ax.set_ylabel(r"$|S|$")
    ax.set_ylim(0, 4.0 if mode == "both" else 2.6)
    ax.set_title(LABEL[mode], loc="left", color=COLOR[mode])
    ax.legend(loc="upper left")
    logx(ax, 5, 1000)
    fig.tight_layout()
    return save(fig, f"fig5{'a' if mode == 'linear' else 'b'}_sens_{mode}")


# ------------------------------------------------------------------ fig 6: time response
def tms(r):
    return 1e3 * (r.t_s - MOVE_START_S)


def fig6_time(w=None, case="a10m010", win_ms=(-20, 250)):
    runs = {"linear": trial(case, 1, "linear"), "both": trial(case, 2, "both")}
    names = []
    fig, ax = fig_ax(0.55, w)
    for m, r in runs.items():
        ax.plot(tms(r), 1e3 * r.error, color=COLOR[m], lw=1.4, label=LABEL[m])
    ax.set_xlim(*win_ms)
    ax.set_xlabel("time from move start [ms]")
    ax.set_ylabel("tracking error [mrad]")
    ax.legend(loc="upper right")
    fig.tight_layout()
    names.append(save(fig, "fig6a_error"))
    ylim = 1.08 * max(np.abs(r.current_cmd[(tms(r) >= win_ms[0]) & (tms(r) <= win_ms[1])]).max() for r in runs.values())
    for m, r in runs.items():
        fig, ax = fig_ax(0.55, w)
        ax.plot(tms(r), r.current_cmd, color="#c9c9c9", lw=1.0, label="command")
        ax.plot(tms(r), r.motor_current_act, color=COLOR[m], lw=1.4, label="actual")
        ax.set_xlim(*win_ms)
        ax.set_ylim(-ylim, ylim)
        ax.set_xlabel("time from move start [ms]")
        ax.set_ylabel("motor current [A]")
        ax.set_title(LABEL[m], loc="left", color=COLOR[m])
        ax.legend(loc="upper right")
        fig.tight_layout()
        names.append(save(fig, f"fig6{'b' if m == 'linear' else 'c'}_current_{m}"))
    return names


# ------------------------------------------------------------------ fig 7: frequency decomposition
def fig7_spectra(case, w=None):
    names = []
    for channel, ylab, unit, tag, scale in (("error", "error ASD", r"mrad/$\sqrt{\mathrm{Hz}}$", "err_spec", 1e3),
                                            ("current_cmd", "command current ASD", r"A/$\sqrt{\mathrm{Hz}}$", "cmd_spec", 1.0)):
        fig, ax = fig_ax(0.62, w)
        for m in ("linear", "both"):
            f, p = mode_psd(case, m, channel)
            fc, pm = log_average(f[1:], p[1:], 6, 1.0)
            ax.plot(fc, scale * np.sqrt(pm), color=COLOR[m], label=LABEL[m])
        ax.set_xscale("log")
        ax.set_yscale("log")
        ax.set_xlim(1, FS / 2)
        ax.set_xlabel("frequency [Hz]")
        ax.set_ylabel(f"{ylab} [{unit}]")
        ax.set_title(f"{case}: {CASES[case]}", loc="left")
        ax.legend(loc="upper right")
        fig.tight_layout()
        names.append(save(fig, f"fig7{'a' if tag == 'err_spec' else 'b'}_{tag}_{case}"))
    fig, ax = fig_ax(0.62, w)
    for m in ("linear", "both"):
        f, p = mode_psd(case, m, "error")
        c = np.sqrt(np.cumsum(p[1:]) * (f[1] - f[0]))
        assert abs(c[-1] - rms_mrad(np.concatenate([trial(case, k, m).error for k in RUNS[m]])) * 1e-3) < 0.02 * c[-1]   # Parseval, mean of two runs
        ax.plot(f[1:], 1e3 * c, color=COLOR[m], label=f"{LABEL[m]}: {1e3 * c[-1]:.2f} mrad")
    ax.set_xscale("log")
    ax.set_xlim(1, FS / 2)
    ax.set_ylim(0, None)
    ax.set_xlabel("frequency [Hz]")
    ax.set_ylabel("cumulative RMS error [mrad]")
    ax.set_title(f"{case}: {CASES[case]}", loc="left")
    ax.legend(loc="upper left")
    fig.tight_layout()
    names.append(save(fig, f"fig7c_cumrms_{case}"))
    return names


# ------------------------------------------------------------------ fig 8: HIGS modes
def fig8_modes(w=None, case="a10m010", win_ms=(-10.0, 30.0)):
    r = trial(case, 2, "both")
    t = tms(r)
    s = (t >= win_ms[0] - 0.2) & (t <= win_ms[1] + 0.2)
    fig, ax = fig_ax(0.5, w)
    for off, ch, lab in ((4, "higs_lp_mode", r"HIGS$_{lp}$"), (0, "higs_i_mode", r"HIGS$_i$")):
        ax.step(t[s], getattr(r, ch)[s].astype(float) + off, where="post", color=C_HIGS if off == 0 else C_LIN, lw=1.5)
        ax.text(win_ms[1] + 0.01 * (win_ms[1] - win_ms[0]), off + 2, lab, va="center", color=C_HIGS if off == 0 else C_LIN)
    ax.axvline(0, color="k", ls=":", lw=1.2)
    ax.text(0.8, 7.45, "move start", va="top")
    ax.set_yticks([1, 2, 3, 5, 6, 7], ["integrator", "gain", "zero", "integrator", "gain", "zero"])
    ax.set_ylim(0.5, 7.5)
    ax.set_xlim(*win_ms)
    ax.set_xlabel("time from move start [ms]")
    ax.grid(axis="x", alpha=0.0)
    fig.tight_layout()
    return save(fig, "fig8_modes")


# ------------------------------------------------------------------ fig 9: summary
def fig9_summary(w=None):
    fig, ax = fig_ax(0.62, w)
    wd = 0.36
    for i, case in enumerate(CASES):
        means = {}
        for j, m in enumerate(("linear", "both")):
            v = np.array([rms_mrad(trial(case, k, m).error) for k in RUNS[m]])
            means[m] = v.mean()
            x = i + (j - 0.5) * wd
            ax.bar(x, v.mean(), wd * 0.92, color=COLOR[m], alpha=0.55, label=LABEL[m] if i == 0 else None)
            ax.plot(np.full(2, x) + np.array([-0.05, 0.05]), v, "o", color="k", ms=4.5 * W / 7, zorder=5, label="single run" if (i == 0 and j == 0) else None)
        pct = 100 * (means["both"] / means["linear"] - 1)
        ax.text(i, max(means.values()) * 1.07 + 0.12, f"{pct:+.0f} %", ha="center", va="bottom", fontweight="bold", color=C_HIGS)
    ax.set_xticks(range(len(CASES)), [c.replace(" / ", "\n") for c in CASES.values()])
    ax.set_ylabel("tracking-error RMS [mrad]")
    ax.set_ylim(0, 7.0)
    ax.legend(loc="upper left")
    ax.grid(axis="x", visible=False)
    fig.tight_layout()
    return save(fig, "fig9_summary")


def main():
    ctx = Context()
    fig1_frf(ctx)
    fig2_block_df(ctx)
    fig3_element(ctx, "lp")
    fig3_element(ctx, "i")
    fig3_filters(ctx)
    fig4_diagram(ctx)
    fig5_sensitivity(ctx, "linear")
    fig5_sensitivity(ctx, "both")
    fig6_time()
    for case in ("a01m010", "r5m100"):
        fig7_spectra(case)
    fig8_modes()
    fig9_summary()


if __name__ == "__main__":
    main()
