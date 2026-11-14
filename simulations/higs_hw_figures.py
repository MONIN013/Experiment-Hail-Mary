#!/usr/bin/env python3
"""Figures of the 16 kHz HIGS hardware study -> docs/operations/figures/higs16k/*.png (150 dpi).

Python only (numpy, scipy, matplotlib); reads files, touches no hardware.
Frequency-domain figures reuse higs_hw_design / higs_fig89_robustness (gate "measured", Ts = 62.5 us, extra delay 0):
  fits and designs : simulations/results/hw16b/hw_design.json (frictionless design model, tuning of both error-optimal designs)
  measured member  : Hl of smsync/frf_ms030 / frf_ms015 (the stored designs were computed on the older hardware16k/frf_*.mat; the
                     script first reproduces their numbers on that file, then uses the SM-sync FRF for all plots) for 70 Hz <= f <= 3000 Hz spliced with the design model below 70 Hz and above 3000 Hz
  loop             : L = kp * C(jw) * G, C = describing-function controller R.FreqModel.controller (product of the HIGS DFs)
Time-domain figures read simulations/data/hardware16k/erropt/eo_<case>_<k>_<mode>.mat (A-B-B-A, field `error` is the tracking error).
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
from scipy import signal

sys.path.insert(0, str(Path(__file__).resolve().parent))
import higs_hw_design as H          # noqa: E402
import higs_fig89_robustness as R   # noqa: E402

ROOT = H.ROOT
TS = 6.25e-5
FRF_DIR = ROOT / "simulations/data/hardware16k/smsync"          # drives SM-synchronous: FRF of the rig during the A-B-B-A trials
DESIGN_FRF_DIR = ROOT / "simulations/data/hardware16k"          # FRF the designs in hw_design.json were computed on (used for the check only)
DESIGN_JSON = ROOT / "simulations/results/hw16b/hw_design.json"
TRIAL_DIR = ROOT / "simulations/data/hardware16k/erropt"
OUT = ROOT / "docs/operations/figures/higs16k"
F_PLOT_MAX = 3000.
FRICTION_HZ = (0.5, 70.)

C_LIN, C_HIGS, C_MEAS, C_MODEL = "#2a78d6", "#6250d6", "#8a8a8a", "black"
PAIR = {"linear": "linear_error_opt", "both": "both_book_error_opt"}
LABEL = {"linear": "linear", "both": "HIGS (both)"}
COLOR = {"linear": C_LIN, "both": C_HIGS}
CASES = {"a01m010": "0.1 rad, 0.1 s", "a10m010": "1 rad, 0.1 s", "r5m100": "5 rev, 1 s"}
RUNS = {"linear": (1, 4), "both": (2, 3)}

plt.rcParams.update({
    "font.size": 12, "axes.titlesize": 13, "axes.labelsize": 12, "legend.fontsize": 10.5, "xtick.labelsize": 11, "ytick.labelsize": 11,
    "axes.grid": True, "grid.alpha": 0.25, "grid.linewidth": 0.6, "axes.axisbelow": True, "legend.framealpha": 0.9,
    "figure.dpi": 150, "savefig.dpi": 150, "lines.linewidth": 1.6,
})


def db(x):
    return 20 * np.log10(np.abs(x))


def save(fig, name):
    OUT.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT / name, bbox_inches="tight")
    plt.close(fig)
    print("saved", name)


def logfreq(ax, lo=None, hi=F_PLOT_MAX):
    ax.set_xscale("log")
    ax.set_xlim(lo, hi)


# ------------------------------------------------------------------ setup shared with the design
class Setup:
    def __init__(self, frf_dir):
        H.set_sample_time(TS)
        H.DATA = frf_dir
        H.GATE_KIND = "measured"
        self.res = json.loads(DESIGN_JSON.read_text())
        self.fits = self.res["fits"]
        self.Ds = {n: H.load_frf(n) for n in H.AMPS}
        (self.fs, self.Gs), (self.fm_grid, self.Gm), *_ = H.build_gate_measured(self.fits, self.Ds)
        self.designs = {k: self.res["designs"][v] for k, v in PAIR.items()}
        R.df_table()                                    # numeric DF of the discrete HIGS at 16 kHz (as in the design)
        self.fm_s = {n: R.FreqModel(self.fs, self.Gs[i], extra_delay=0) for i, n in enumerate(H.AMPS)}
        self.fm_m = R.FreqModel(self.fm_grid, self.Gm[0], extra_delay=0)

    def loop(self, key, member):
        """Open loop L(jw) of design `key` on member 'ms030' | 'ms015' (spliced, grid fs) | 'model' (dense, grid fm_grid)."""
        rec = self.designs[key]
        fm = self.fm_m if member == "model" else self.fm_s[member]
        return fm.f, rec["kp"] * fm.controller(rec["design"]) * fm.G

    def check(self):
        """The reproduced loops must match the numbers stored in hw_design.json."""
        for key, rec in self.designs.items():
            for member, name, tol_hz in (("ms030", "ms030_measured_spliced", 0.05), ("ms015", "ms015_measured_spliced", 0.05),
                                         ("model", "ms030_design_model_nominal", 0.05)):
                f, L = self.loop(key, member)
                sel = f <= H.MEAS_MAX_HZ if member == "model" else slice(None)
                s = float(np.max(np.abs(1 / (1 + L[sel]))))
                ref = rec["S_max_members"][name]["S_max"]
                assert abs(s - ref) < 0.01 * ref, (key, member, s, ref)
            f, L = self.loop(key, "ms030")
            fc = R.loop_metrics(f, L)["fc_hz"]
            assert abs(fc - rec["crossover_hz"]) < 0.01 * fc, (key, fc, rec["crossover_hz"])
        print("design numbers reproduced from hw_design.json")


# ------------------------------------------------------------------ fig 1
def fig1(su):
    fd = {n: su.fits[n]["design"] for n in H.AMPS}
    f = np.unique(np.concatenate([np.geomspace(0.5, F_PLOT_MAX, 1500), np.linspace(50, F_PLOT_MAX, 3000)]))
    Hm_mod, Hl_mod = H.plant_frf(f, fd["ms030"]["params"], fd["ms030"]["tau_samples"] * TS)
    models = {"Hm": Hm_mod, "Hl": Hl_mod}
    shade = {"ms030": "#4d4d4d", "ms015": "#b5b5b5"}
    fig, axs = plt.subplots(2, 2, figsize=(7.4, 6.2), sharex=True)
    for col, (key, title) in enumerate((("Hm", "(a) motor position / current"), ("Hl", "(b) load position / current"))):
        Hmod = models[key]
        ph = np.unwrap(np.angle(Hmod), discont=1.5 * np.pi)
        ph = np.degrees(ph) - 360 * np.round((np.degrees(ph[0]) + 180) / 360)
        for amp, D in su.Ds.items():
            sel = D["f"] <= F_PLOT_MAX
            fl, Hd = D["f"][sel], D[key][sel]
            Hmod_l = H.plant_frf(fl, fd["ms030"]["params"], fd["ms030"]["tau_samples"] * TS)[0 if key == "Hm" else 1]
            rel = np.degrees(np.angle(Hd / Hmod_l))
            ph_l = np.interp(np.log(fl), np.log(f), ph) + (rel + 180) % 360 - 180
            lab = f"measured {H.AMPS[amp]:.2f} A"
            axs[0, col].plot(fl, db(Hd), ".", ms=2.6, color=shade[amp], label=lab, rasterized=True)
            axs[1, col].plot(fl, ph_l, ".", ms=2.6, color=shade[amp], rasterized=True)
        axs[0, col].plot(f, db(Hmod), color=C_MODEL, lw=1.4, label="frictionless model")
        axs[1, col].plot(f, ph, color=C_MODEL, lw=1.4)
        axs[0, col].set_title(title)
        axs[1, col].set_xlabel("frequency [Hz]")
        for ax in axs[:, col]:
            ax.axvspan(*FRICTION_HZ, color="#e8a33a", alpha=0.18, lw=0)
        axs[0, col].text(2.2, 0.04, "friction:\namplitude\ndependent", transform=axs[0, col].get_xaxis_transform(), ha="left", va="bottom",
                         fontsize=9.5, color="#8a5a00")
        logfreq(axs[1, col], 1.0)
    axs[0, 0].set_ylabel("magnitude [dB re 1 rad/A]")
    axs[1, 0].set_ylabel("phase [deg]")
    axs[0, 0].legend(loc="upper right")
    for ax in axs[1]:
        ax.set_yticks(np.arange(-720, 181, 180))
        ax.set_ylim(-760, 120)
    fig.tight_layout()
    save(fig, "fig1_frf.png")


# ------------------------------------------------------------------ fig 2
def hw_blocks(su, d, f):
    """Linear blocks C* and HIGS-DF counterparts D* = N * V * C* of the two HIGS elements of design d on grid f
    (the branches of R.FreqModel.controller; kp excluded)."""
    fm = R.FreqModel(f, np.ones(len(f), complex), extra_delay=0)
    c = R.corners(d)
    sw = fm.sw
    wl = c["wl"]
    lp_lin = wl**2 / (sw**2 + np.sqrt(2) * wl * sw + wl**2)
    n_lp, n_i = fm.df(c["wc_lp"]), fm.df(c["wc_i"])
    lp_h = n_lp * (sw + c["wc_lp"]) / c["wc_lp"] * lp_lin
    i_lin = c["wi"] / sw
    i_h = n_i * (sw + c["wc_i"]) / c["wc_i"] * i_lin
    lead = (1 + sw / c["wz"]) / (1 + sw / c["wp"])
    assert np.allclose(lp_h * lead * (1 + i_h), fm.controller(d), rtol=1e-9), "block split does not recombine"
    return dict(i=(i_lin, i_h, c["wc_i"] / R.SQ / (2 * np.pi)), lp=(lp_lin, lp_h, c["wc_lp"] / R.SQ / (2 * np.pi)))


def fig2(su):
    d = su.designs["both"]["design"]
    f = np.geomspace(0.5, 3000., 700)
    blk = hw_blocks(su, d, f)
    fig, axs = plt.subplots(2, 2, figsize=(7.4, 6.2), sharex=True)
    for col, (key, title, lin_lab, h_lab) in enumerate((
            ("i", "(a) integrator block", r"linear $C^*=\omega_i/s$", r"HIGS DF $D^*=N\,V\,C^*$"),
            ("lp", "(b) low-pass block", r"linear $C^*$ (2nd-order LPF)", r"HIGS DF $D^*=N\,V\,C^*$"))):
        lin, hg, fh = blk[key]
        ph_l = np.degrees(np.unwrap(np.angle(lin)))
        ph_h = np.degrees(np.unwrap(np.angle(hg)))
        axs[0, col].plot(f, db(lin), color=C_MEAS, label=lin_lab)
        axs[0, col].plot(f, db(hg), color=C_HIGS, label=h_lab)
        axs[1, col].plot(f, ph_l, color=C_MEAS)
        axs[1, col].plot(f, ph_h, color=C_HIGS)
        for ax in axs[:, col]:
            ax.axvline(fh, color="k", ls=":", lw=1.2)
        axs[0, col].text(fh * 1.08, 0.03, rf"$\omega_h/2\pi$ = {fh:.0f} Hz", transform=axs[0, col].get_xaxis_transform(), fontsize=10.5,
                         va="bottom")
        axs[0, col].set_title(title)
        axs[0, col].legend(loc="upper right" if key == "i" else "center left")
        axs[1, col].set_xlabel("frequency [Hz]")
        logfreq(axs[1, col], 0.5)
    axs[0, 0].set_ylabel("magnitude [dB]")
    axs[1, 0].set_ylabel("phase [deg]")
    fig.tight_layout()
    save(fig, "fig2_df.png")


# ------------------------------------------------------------------ fig 3
def unwrapped_phase(L, anchor):
    ph = np.degrees(np.unwrap(np.angle(L)))
    return ph - 360 * np.round((ph[0] - anchor) / 360)


F3_MAX = 1500.


def mark_splice(ax, y=0.97):
    ax.axvline(H.SPLICE_HZ, color="k", ls="-.", lw=0.9, alpha=0.6)
    ax.text(H.SPLICE_HZ * 1.06, y, "splice 70 Hz", transform=ax.get_xaxis_transform(), fontsize=9.5, va="top", alpha=0.8)


def fig3(su):
    fig, axs = plt.subplots(2, 1, figsize=(7.2, 6.4), sharex=True)
    for key in ("linear", "both"):
        f, L = su.loop(key, "ms030")
        m = R.loop_metrics(f, L)
        lab = f"{LABEL[key]}  (crossover {m['fc_hz']:.0f} Hz, PM {m['pm_deg']:.0f}$^\\circ$)"
        sel = f <= F3_MAX
        axs[0].plot(f[sel], db(L[sel]), color=COLOR[key], label=lab)
        axs[1].plot(f[sel], unwrapped_phase(L[sel], -270.), color=COLOR[key])
        axs[0].plot(m["fc_hz"], 0, "o", color=COLOR[key], mfc="white", ms=9, mew=2, zorder=5)
        axs[1].axvline(m["fc_hz"], color=COLOR[key], ls=":", lw=1.2)
    axs[0].axhline(0, color="k", lw=0.9)
    axs[1].axhline(-180, color="k", lw=0.9)
    axs[0].set_ylabel("|L| [dB]")
    axs[1].set_ylabel("phase of L [deg]")
    axs[1].set_xlabel("frequency [Hz]")
    axs[0].set_title(r"open loop $L=CG$, measured $G$ (0.30 A); circles: first crossover")
    axs[0].set_ylim(-60, 80)
    axs[1].set_ylim(-700, 0)
    axs[0].legend(loc="upper right")
    for ax in axs:
        mark_splice(ax, 0.3 if ax is axs[0] else 0.97)
    logfreq(axs[1], 0.5, F3_MAX)
    fig.tight_layout()
    save(fig, "fig3_loop.png")


# ------------------------------------------------------------------ fig 4
def fig4(su):
    fig = plt.figure(figsize=(7.2, 8.6))
    gs = fig.add_gridspec(2, 1, height_ratios=[1, 0.95])
    ax = fig.add_subplot(gs[0])
    style = {"ms030": ("-", "measured 0.30 A"), "ms015": ("--", "measured 0.15 A"), "model": (":", "frictionless model")}
    for key in ("linear", "both"):
        for member, (ls, lab) in style.items():
            f, L = su.loop(key, member)
            sel = f <= F_PLOT_MAX
            ax.plot(f[sel], db(1 / (1 + L[sel])), ls=ls, color=COLOR[key], lw=1.4 if member != "ms030" else 1.8)
    ax.axhline(db(2.0), color="#d6402a", lw=1.4)
    ax.text(0.55, db(2.0) + 0.3, r"$|S|=2$ (6.02 dB)", color="#d6402a", fontsize=10.5)
    handles = [plt.Line2D([], [], color=COLOR[k], label=LABEL[k]) for k in COLOR] + \
              [plt.Line2D([], [], color="k", ls=ls, label=lab) for ls, lab in style.values()]
    ax.legend(handles=handles, loc="lower right", ncol=2, fontsize=9.5)
    ax.set_xlabel("frequency [Hz]")
    ax.set_ylabel("|S| [dB]")
    ax.set_title("(a) sensitivity")
    ax.set_ylim(-45, 9)
    mark_splice(ax, 0.55)
    logfreq(ax, 0.5)
    ax2 = fig.add_subplot(gs[1])
    for key in ("linear", "both"):
        f, L = su.loop(key, "ms030")
        ax2.plot(L.real, L.imag, color=COLOR[key], lw=1.5, label=LABEL[key])
        fmod, Lmod = su.loop(key, "model")
        sel = fmod <= F_PLOT_MAX
        ax2.plot(Lmod[sel].real, Lmod[sel].imag, color=COLOR[key], lw=1.2, ls=":")
    th = np.linspace(0, 2 * np.pi, 400)
    ax2.plot(-1 + 0.5 * np.cos(th), 0.5 * np.sin(th), color="#d6402a", lw=1.4, label=r"$|S|=2$: $|1+L|=0.5$")
    ax2.plot(-1, 0, "k+", ms=12, mew=2)
    ax2.set_xlim(-2.4, 0.8)
    ax2.set_ylim(-1.5, 1.0)
    ax2.set_aspect("equal")
    ax2.set_xlabel("Re L")
    ax2.set_ylabel("Im L")
    ax2.set_title("(b) Nyquist plot, f > 0 (solid: measured 0.30 A, dotted: model)")
    ax2.legend(loc="upper left", fontsize=9.5)
    fig.tight_layout()
    save(fig, "fig4_sensitivity.png")


# ------------------------------------------------------------------ time-domain data
def trial(case, k, mode):
    raw = sio.loadmat(TRIAL_DIR / f"eo_{case}_{k}_{mode}.mat", squeeze_me=True, struct_as_record=False)["raw"]
    return raw


def band(x, lo, hi, fs=1 / TS):
    sos = signal.butter(4, [lo, hi], btype="bandpass", fs=fs, output="sos")
    return signal.sosfiltfilt(sos, x)


def fig5(case="a10m010"):
    t0, t1 = 0.37, 0.85
    runs = {"linear": trial(case, 1, "linear"), "both": trial(case, 2, "both")}
    fig, axs = plt.subplots(4, 1, figsize=(7.2, 9.0), sharex=True)
    ref = runs["linear"].ref_value
    t = runs["linear"].t_s
    axs[0].plot(t, ref, color="k", ls="--", lw=1.2, label="reference")
    for m, r in sorted(runs.items(), reverse=True):
        axs[0].plot(r.t_s, r.load_position, color=COLOR[m], lw=1.4, label=f"load, {LABEL[m]}")
        axs[1].plot(r.t_s, 1e3 * r.error, color=COLOR[m], lw=1.0, label=LABEL[m])
        axs[2].plot(r.t_s, 1e3 * r.current_cmd, color=COLOR[m], lw=0.9)
        axs[3].plot(r.t_s, 1e6 * band(r.motor_position - r.load_position, 200., 400.), color=COLOR[m], lw=0.8)
    axs[0].set_ylabel("position [rad]")
    axs[1].set_ylabel("error [mrad]")
    axs[2].set_ylabel("current [mA]")
    axs[3].set_ylabel(r"twist [$\mu$rad]")
    axs[3].set_xlabel("time [s]")
    for ax, tt in zip(axs, ("(a) reference and load", "(b) tracking error", "(c) commanded current", "(d) twist (motor - load, band-passed)")):
        ax.set_title(tt, loc="left")
    axs[0].legend(loc="upper left", fontsize=9.5)
    axs[1].legend(loc="upper center", ncol=2, fontsize=9.5)
    axs[0].set_xlim(t0, t1)
    fig.suptitle(f"hardware, case {case} ({CASES[case]})", y=1.0, fontsize=13)
    fig.tight_layout()
    save(fig, "fig5_time.png")


def cumrms(e, fs=1 / TS):
    """Cumulative RMS from the one-sided periodogram (Parseval: last value = sqrt(mean(e^2)))."""
    n = len(e)
    X = np.fft.rfft(e)
    p = np.abs(X) ** 2 / n**2
    p[1:(n + 1) // 2] *= 2                                  # two-sided -> one-sided (Nyquist bin of even n stays single)
    f = np.fft.rfftfreq(n, 1 / fs)
    return f, p


def fig6():
    fig, axs = plt.subplots(3, 1, figsize=(7.2, 9.4), sharex=True)
    for ax, (case, desc) in zip(axs, CASES.items()):
        for m in ("linear", "both"):
            ps = []
            for k in RUNS[m]:
                e = trial(case, k, m).error
                f, p = cumrms(e)
                ps.append(p)
                ax.plot(f[1:], 1e3 * np.sqrt(np.cumsum(p))[1:], color=COLOR[m], lw=0.8, alpha=0.45)
            pm = np.mean(ps, axis=0)
            c = np.sqrt(np.cumsum(pm))
            e_all = [trial(case, k, m).error for k in RUNS[m]]
            assert abs(c[-1] - np.sqrt(np.mean([np.mean(x**2) for x in e_all]))) < 1e-9 * c[-1] + 1e-12
            ax.plot(f[1:], 1e3 * c[1:], color=COLOR[m], lw=2.0, label=f"{LABEL[m]}: {1e3 * c[-1]:.2f} mrad")
        ax.set_title(f"({'abc'[list(CASES).index(case)]}) {case}: {desc}", loc="left")
        ax.set_ylabel("cumulative RMS error [mrad]")
        ax.set_ylim(0, None)
        ax.legend(loc="lower right")
    axs[-1].set_xlabel("frequency [Hz]")
    logfreq(axs[-1], 0.3, 1 / (2 * TS))
    fig.tight_layout()
    save(fig, "fig6_cumrms.png")


def mv_mask(t):
    return (t >= 0.4) & (t <= 0.8)


def fig7(case="a10m010"):
    r = trial(case, 2, "both")
    t = r.t_s
    t0, t1 = 0.38, 0.84
    n = int(0.020 / TS)
    chg = sum(np.abs(np.diff(getattr(r, ch).astype(int))) > 0 for ch in ("higs_i_mode", "higs_lp_mode"))
    chg = np.convolve(np.where(mv_mask(t[1:]), chg, 0), np.ones(n), "valid")
    z0 = float(t[1 + int(np.argmax(chg))])
    z1 = z0 + 0.020                                           # 20 ms window with the most mode changes during the move
    names = {1: "integrator", 2: "gain", 3: "zero"}
    mv = (t >= 0.4) & (t <= 0.8)
    occ = {}
    for ch in ("higs_i_mode", "higs_lp_mode"):
        occ[ch] = {names[int(v)]: 100 * float(np.mean(getattr(r, ch)[mv] == v)) for v in np.unique(getattr(r, ch))}
        print(" ", ch, {k: round(v, 1) for k, v in occ[ch].items()})
    fig, axs = plt.subplots(3, 2, figsize=(8.6, 6.8), sharex="col")
    for col, (a, b) in enumerate(((t0, t1), (z0, z1))):
        axs[0, col].plot(t, 1e3 * r.error, color=C_HIGS, lw=1.0)
        for row, (ch, lab) in enumerate((("higs_i_mode", "integrator HIGS"), ("higs_lp_mode", "low-pass HIGS")), start=1):
            axs[row, col].step(t, getattr(r, ch), where="post", color=C_HIGS, lw=1.0)
            axs[row, col].set_yticks([1, 2, 3], ["integr.", "gain", "zero"])
            axs[row, col].set_ylim(0.6, 3.4)
            axs[row, col].set_ylabel("mode" if col == 0 else "")
            axs[row, col].grid(axis="y")
            if col == 0:
                axs[row, col].set_title(f"{lab}, time in move: " + ", ".join(f"{k} {v:.0f} %" for k, v in occ[ch].items() if v >= 0.5),
                                        loc="left", fontsize=10.5)
        axs[2, col].set_xlabel("time [s]")
        axs[0, col].set_xlim(a, b)
        if col == 1:
            e = 1e3 * r.error[(t >= a) & (t <= b)]
            axs[0, col].set_ylim(e.min() - 0.05 * np.ptp(e), e.max() + 0.05 * np.ptp(e))
    axs[0, 0].set_ylabel("error [mrad]")
    axs[0, 0].set_title("(a) move", loc="left")
    axs[0, 1].set_title("(b) 20 ms zoom, most active window", loc="left")
    fig.suptitle(f"HIGS (both) modes, hardware, case {case}", y=1.0, fontsize=13)
    fig.tight_layout()
    save(fig, "fig7_modes.png")


def fig8():
    fig, ax = plt.subplots(figsize=(7.2, 4.8))
    w = 0.36
    for i, case in enumerate(CASES):
        means = {}
        for j, m in enumerate(("linear", "both")):
            v = np.array([1e3 * np.sqrt(np.mean(trial(case, k, m).error ** 2)) for k in RUNS[m]])
            means[m] = v.mean()
            x = i + (j - 0.5) * w
            ax.bar(x, v.mean(), w * 0.92, color=COLOR[m], alpha=0.55, label=LABEL[m] if i == 0 else None)
            ax.plot(np.full(2, x) + np.array([-0.06, 0.06]), v, "o", color="k", ms=5, zorder=5, label="single run" if (i == 0 and j == 0) else None)
        pct = 100 * (means["both"] / means["linear"] - 1)
        ax.text(i, max(means.values()) * 1.12 + 0.12, f"{pct:+.0f} %", ha="center", va="bottom", fontsize=12, fontweight="bold", color=C_HIGS)
    ax.set_xticks(range(len(CASES)), [f"{c}\n{d}" for c, d in CASES.items()])
    ax.set_ylabel("tracking-error RMS, full record [mrad]")
    ax.set_ylim(0, 3.2)
    ax.legend(loc="upper left")
    ax.set_title("A-B-B-A trials: linear vs HIGS (mean and runs)")
    ax.grid(axis="x", visible=False)
    fig.tight_layout()
    save(fig, "fig8_summary.png")


# ------------------------------------------------------------------ fig 9
def fig9(su):
    """Closed-loop |S| measured on hardware (multisine disturbance on dist_value, 2 rad/s ramp) vs the DF prediction."""
    d = H.ROOT / "simulations/data/hardware16k/sensitivity"
    fig, ax = plt.subplots(figsize=(7.2, 4.2))
    for key, name in (("linear", "linear"), ("both", "both")):
        m = sio.loadmat(d / f"S_sens_{name}.mat", squeeze_me=True)
        ax.plot(m["f"], db(np.abs(m["Sx"])), "o", ms=2.5, color=COLOR[key], alpha=0.7, label=LABEL[key] + " measured")
        f, L = su.loop(key, "ms030")
        sel = (f >= 5) & (f <= 1000)
        ax.plot(f[sel], db(1 / (1 + L[sel])), color=COLOR[key], lw=1.4, label=LABEL[key] + " DF prediction (0.30 A FRF)")
    ax.axhline(db(2.0), color="#d6402a", lw=1.4)
    ax.text(5.5, db(2.0) + 0.3, r"$|S|=2$", color="#d6402a", fontsize=10.5)
    ax.set_xlabel("frequency [Hz]")
    ax.set_ylabel("|S| [dB]")
    ax.set_title("closed-loop sensitivity on hardware (0.05 A multisine disturbance, 2 rad/s)")
    ax.legend(loc="lower right", fontsize=9)
    logfreq(ax, 5, 1000)
    fig.tight_layout()
    save(fig, "fig9_measured_sensitivity.png")


def main():
    Setup(DESIGN_FRF_DIR).check()
    su = Setup(FRF_DIR)
    fig1(su)
    fig2(su)
    fig3(su)
    fig4(su)
    fig5()
    fig6()
    fig7()
    fig8()
    fig9(su)


if __name__ == "__main__":
    main()
