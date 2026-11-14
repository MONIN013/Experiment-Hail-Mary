#!/usr/bin/env python3
"""Book-conform linear and two-HIGS controllers for the 16 kHz two-inertia bench
(van den Eijnden, Heertjes, Heemels, Nijmeijer: Hybrid Integrator-Gain Systems, ch. 7 and 8).

Controller (eq. 8.7, 8.8, Fig. 8.9; kh = 1):  C = kp * Cpid{H_i} * Clp{H_lp} * Cn
  Clp{H}: HIGS_lp -> V_lp = H_lp^-1 C_lp (C_lp: 2nd-order Butterworth low-pass); H = wc/(s + wc), wc = SQ * wh   (eq. 8.9, 8.11)
  Cpid{H}: lead * (1 + HIGS_i -> V_i), V_i = H_i^-1 (wi / s)  (the PID differentiator is a lead, as in the existing exp05 packing)
  W_i (eq. 8.14, Fig. 8.7): skew notch in front of HIGS_i, W_i^-1 behind it (folded into iPost). Pole (denominator) corner low,
      zero (numerator) corner high, W_i(0) = 1; W_lp = 1.  W_i cancels in the describing function and in the linear counterpart.
  Cn: one true notch (eq. 8.8c) on the load-position resonance (290-330 Hz, |wp/wz - 1| <= 5 %, beta_p >= 0.3, beta_z/beta_p in 0.07..0.9), Post segment.
Section packing (as exp05_Higs prepare_design): lpPost = V_lp, Hlp, p = kp*lead, iPre = W_i, Hi, iPost = W_i^-1 kp lead V_i, post = Cn.

Design criterion (eq. 8.13, p. 201): maximise the open-loop crossover subject to
    |W_S S| + lambda |W_a S P| <= 1 for all frequencies (pointwise; for lambda = 1 this is |S|/(1 - |W_a S P|) <= 1/|W_S|, the
    worst-case sensitivity statement on p. 201),   W_S = 1/2 (|S| <= 2, 6 dB),
    W_a = W_Delta * |kp lead (1 + D_i V_i) V_lp Cn|    (book: W_a = W_Delta D_pid V_lp; Cn, the linear filter behind the HIGS, is kept),
    W_Delta(w) = |D(j w_min) - D(j w)| for w >= w_start, else 0                    (eq. 7.48, p. 201; D = DF of the low-pass HIGS)
with w_min = F_MIN_HZ = 30 Hz, w_start = F_START_HZ = 200 Hz, fixed in Hz during the optimisation. Book: 100 Hz / 600 Hz at a 293 Hz
bandwidth (error content around 0.3-0.9 x bandwidth, structural content from 2 x bandwidth). Here the bandwidth is ~90 Hz: w_min is
~0.3 x bandwidth (the move/stiction error content is 10-40 Hz, see also the w_min = 10 Hz check stored per design) and w_start = 200 Hz
is the antiresonance / resonance region (200-350 Hz) of the load FRF.
Noise limit (not in the book, same for every family): max |kp C*| above 1 kHz <= HF_GAIN_MAX, anchored at about 2x the hardware-tested linear design.
The term is evaluated on the measured members (ms060 primary, ms030) spliced with the frictionless model below the splice
frequency; the frictionless model member must satisfy |S| <= 2 and the Nyquist winding check. HIGS ratios stay in the book ranges
(omega_h,lp / fc in 1..2.5, omega_h,i / fc in 0.3..0.7, Table 8.2).
Two objectives: 'maxbw' (maximum first crossover of the nominal member) and 'error' (minimum round-trip RMS on the frictionless
model, 3-sample delay, current limit 2.71 A, encoder 2^20 counts/rev, peak command <= 0.5 A). Every accepted design also passes the
time-domain screen with the real HIGS law (no divergence, no limit cycle) and, for HIGS designs, the numeric cascade DF gate.
Run: python simulations/higs_book_design.py     (three processes; needs numba)
"""
from __future__ import annotations
import argparse
import hashlib
import json
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numba as nb
import numpy as np
from scipy import signal

import higs_fig89_robustness as R
import higs_hw_design as H

base = R.base
ROOT = R.ROOT
OUT = ROOT / "simulations/hardware/designs"
SQ = R.SQ
S_LIMIT = 2.0
CURRENT_LIMIT_A = 2.71
PEAK_CMD_A = 0.5
ENC_COUNTS = 2**20
TD_DELAY = 3                                  # samples, round(tau of the free fit)
AMPS = {"ms060": 0.6, "ms030": 0.3, "ms100": 1.0}
S_MEMBERS = ("ms060", "ms030", "ms100")        # measured (spliced) S members, row 0 nominal
MEMBER_NAMES = tuple(f"{n}_spliced" for n in S_MEMBERS)
STIFFNESS_SCALE = (0.9, 1.1)                  # model members: resonance frequency about -5 % / +5 %
UNC_MAX_HZ = 2000.                            # perturbed model members are checked up to this frequency (winding on the full grid)
MEAS_MAX_HZ = 3000.                           # highest measured line used (above it |L| << 1)
F_MIN_HZ, F_START_HZ = 30., 200.              # w_min and start of the DF-uncertainty band
LAMBDAS = (0.0, 0.4)
SPLICE_PHASE_DEG, SPLICE_MAG, SPLICE_RUN = 10., 0.25, 3
HF_GAIN_MAX = 100.        # A/rad: max |kp C*(j 2 pi f)|, f >= HF_GAIN_HZ (hardware-tested linear design: ~50 A/rad), same for every family
HF_GAIN_HZ = 1000.
WI_BOOK = dict(wi_p_hz=104., wi_ratio=2000. / 104.)   # Table 8.2: 104 Hz and 2000 Hz, beta = 1 (low corner = pole, see docstring)
BOUNDS = dict(fc=(10., 200.), r_i=(1.5, 6.), lz_ratio=(1.2, 6.), lpole_ratio=(1.5, 12.), lp_hz=(60., 3000.),
              wc_lp_ratio=(0.8 * SQ, 3.0 * SQ), wc_i_ratio=(0.25 * SQ, 0.8 * SQ),
              nz_hz=(290., 330.), np_ratio=(0.95, 1.05), depth=(0.07, 0.9), np_beta=(0.3, 1.0),
              wi_p_hz=(20., 400.), wi_ratio=(2., 40.))
FD_KEYS = ("fc", "r_i", "lz_ratio", "lpole_ratio", "lp_hz", "nz_hz", "np_ratio", "depth", "np_beta")
HIGS_KEYS = ("wc_lp_ratio", "wc_i_ratio")
TD_KEYS = ("wi_p_hz", "wi_ratio")
TS = FS = None                                # set by build_setup


# ------------------------------------------------------------------ numba kernels (port of ControllerAlgorithm::Step)
@nb.njit(cache=True)
def _higs(x, hs, k, wts):
    cand = hs[2 * k] + wts * x
    inside = (cand >= 0.0 and cand <= x) if x >= 0.0 else (cand >= x and cand <= 0.0)
    same = (x >= 0.0 and hs[2 * k + 1] >= 0.0) or (x <= 0.0 and hs[2 * k + 1] <= 0.0)
    out = cand if inside else (x if same else 0.0)
    hs[2 * k] = out
    hs[2 * k + 1] = x
    return out


@nb.njit(cache=True)
def _bq(coef, st, i, x):
    y = coef[i, 0] * x + st[i, 0]
    st[i, 0] = coef[i, 1] * x - coef[i, 3] * y + st[i, 1]
    st[i, 1] = coef[i, 2] * x - coef[i, 4] * y
    return y


@nb.njit(cache=True)
def _ctrl(e, coef, cnt, st, hs, hl_on, hl_wts, hi_on, hi_wts):
    """cnt = [lpPre, lpPost, p, iPre, iPost, post]; packed rows lpPre, Hlp, lpPost, p, iPre, Hi, iPost, post."""
    o = 0
    x = e
    for i in range(cnt[0]):
        x = _bq(coef, st, o + i, x)
    o += cnt[0]
    x = _higs(x, hs, 0, hl_wts) if hl_on else _bq(coef, st, o, x)
    o += 1
    for i in range(cnt[1]):
        x = _bq(coef, st, o + i, x)
    o += cnt[1]
    p = x
    for i in range(cnt[2]):
        p = _bq(coef, st, o + i, p)
    o += cnt[2]
    v = x
    for i in range(cnt[3]):
        v = _bq(coef, st, o + i, v)
    o += cnt[3]
    v = _higs(v, hs, 1, hi_wts) if hi_on else _bq(coef, st, o, v)
    o += 1
    for i in range(cnt[4]):
        v = _bq(coef, st, o + i, v)
    o += cnt[4]
    y = p + v
    for i in range(cnt[5]):
        y = _bq(coef, st, o + i, y)
    return y


@nb.njit(cache=True)
def _td(ref, dist, du, coef, cnt, hl_on, hl_wts, hi_on, hi_wts, ad, bm, bd, delay, ilim, eq, th_m, th_l, cmd_out):
    n = len(ref)
    st = np.zeros((coef.shape[0], 2))
    hs = np.zeros(4)
    x = np.zeros(4)
    q = np.zeros(delay + 1)
    clipped = 0
    for k in range(n):
        y = x[2]
        if eq > 0.0:
            y = np.floor(y / eq + 0.5) * eq
        c = _ctrl(ref[k] - y, coef, cnt, st, hs, hl_on, hl_wts, hi_on, hi_wts)
        a = min(ilim, max(-ilim, c + du[k]))
        if abs(c + du[k]) > ilim:
            clipped += 1
        q[k % (delay + 1)] = a
        dl = q[(k - delay) % (delay + 1)] if k >= delay else 0.0
        th_m[k] = x[0]
        th_l[k] = x[2]
        cmd_out[k] = c + du[k]
        xn = np.empty(4)
        for i in range(4):
            xn[i] = ad[i, 0] * x[0] + ad[i, 1] * x[1] + ad[i, 2] * x[2] + ad[i, 3] * x[3] + bm[i] * dl + bd[i] * dist[k]
        x = xn
        if abs(x[0]) > 1e3 or not np.isfinite(x[0]):
            for j in range(k + 1, n):
                th_m[j] = np.nan
                th_l[j] = np.nan
                cmd_out[j] = np.nan
            return -1
    return clipped


@nb.njit(cache=True)
def _ctrl_df(n, coef, cnt, hl_on, hl_wts, hi_on, hi_wts, periods, keep):
    st = np.zeros((coef.shape[0], 2))
    hs = np.zeros(4)
    s = 0.0
    c = 0.0
    for k in range(periods * n):
        th = 2 * np.pi * k / n + 0.3
        y = _ctrl(np.sin(th), coef, cnt, st, hs, hl_on, hl_wts, hi_on, hi_wts)
        if k >= (periods - keep) * n:
            thk = th % (2 * np.pi)
            s += y * np.sin(thk)
            c += y * np.cos(thk)
    return 2.0 / (keep * n) * (s + 1j * c)


@nb.njit(cache=True)
def _df_table(ns, wts_arr, periods, keep):
    out = np.zeros((len(wts_arr), len(ns)), dtype=np.complex128)
    coef = np.zeros((0, 5))
    cnt = np.zeros(6, dtype=np.int64)
    for i in range(len(wts_arr)):
        for j in range(len(ns)):
            n = ns[j]
            hs = np.zeros(2)
            s = 0.0
            c = 0.0
            for k in range(periods * n):
                th = 2 * np.pi * k / n + 0.3
                y = _higs(np.sin(th), hs, 0, wts_arr[i])
                if k >= (periods - keep) * n:
                    thk = th % (2 * np.pi)
                    s += y * np.sin(thk)
                    c += y * np.cos(thk)
            out[i, j] = 2.0 / (keep * n) * (s + 1j * c)
    return out


class DFTab:
    """Numeric DF of the discrete HIGS (kh = 1, wh = wc / SQ) tabulated over wc and samples per period; bilinear in
    (log wc, log f); above FS / 4 the magnitude is continued with 1 / f (as R.DFTable)."""

    def __init__(self, wc_hz=np.geomspace(0.2, 1500., 90), n_points=130):
        n = np.unique(np.round(np.geomspace(4, FS / 0.5, n_points)).astype(np.int64))
        self.f = FS / n[::-1]
        self.wc_hz = wc_hz
        self.v = _df_table(n[::-1].copy(), 2 * np.pi * wc_hz / SQ * TS, 4, 2)

    def __call__(self, wc_hz, f):
        x = np.log(wc_hz)
        g = np.log(self.wc_hz)
        j = int(np.clip(np.searchsorted(g, x) - 1, 0, len(g) - 2))
        t = float(np.clip((x - g[j]) / (g[j + 1] - g[j]), 0, 1))
        row = (1 - t) * self.v[j] + t * self.v[j + 1]
        lf = np.log(np.minimum(f, self.f[-1]))
        return (np.interp(lf, np.log(self.f), row.real) + 1j * np.interp(lf, np.log(self.f), row.imag)) * np.minimum(1.0, self.f[-1] / f)


# ------------------------------------------------------------------ design parameters -> filters
def corners(d):
    """Continuous corner frequencies [rad/s]; notch and W_i as (wz, bz, wp, bp)."""
    t = 2 * np.pi
    c = dict(wz=t * d["fc"] / d["lz_ratio"], wp=t * d["fc"] * d["lpole_ratio"], wi=t * d["fc"] / d["r_i"], wl=t * d["lp_hz"],
             wc_lp=t * d["fc"] * d["wc_lp_ratio"] if d["mode"] != "linear" else None,
             wc_i=t * d["fc"] * d["wc_i_ratio"] if d["mode"] != "linear" else None,
             notch=(t * d["nz_hz"], d["depth"] * d["np_beta"], t * d["nz_hz"] * d["np_ratio"], d["np_beta"]),
             wi_filter=None)
    if d["mode"] != "linear":
        wp_i = t * d["wi_p_hz"]
        c["wi_filter"] = (wp_i * d["wi_ratio"], 1.0, wp_i, 1.0)          # zero (high), beta_z, pole (low), beta_p
    return c


def _quad(w, b):
    return [1.0, 2 * b * w, w * w]


def _zpk_quad(w, b):
    r = np.roots(_quad(w, b))
    return list(r)


def sections(d, kp):
    """Packed SOS of the design (rows [b0 b1 b2 a0 a1 a2]) and the six variable-segment counts, as exp05_Higs prepare_design."""
    c = corners(d)
    fs = FS
    wl, wc_lp, wc_i = c["wl"], c["wc_lp"] or 1.0, c["wc_i"] or 1.0
    higs = d["mode"] != "linear"

    def sos(z, p, k):
        zd, pd, kd = signal.bilinear_zpk(z, p, k, fs)
        return signal.zpk2sos(zd, pd, kd, pairing="nearest")

    lpf_poles = list(np.roots([1.0, np.sqrt(2) * wl, wl * wl]))
    if higs:
        hlp = sos([], [-wc_lp], wc_lp)
        lp_post = sos([-wc_lp], lpf_poles, wl * wl / wc_lp)
    else:
        hlp = np.array([[1, 0, 0, 1, 0, 0.]])                   # H = 1: the linear design needs no HIGS element
        lp_post = sos([], lpf_poles, wl * wl)
    p = sos([-c["wz"]], [-c["wp"]], kp * c["wp"] / c["wz"])
    if higs:
        hi = sos([], [-wc_i], wc_i)
        vi = (c["wi"] / wc_i, [-wc_i], [0.0])
    else:
        hi = np.array([[1, 0, 0, 1, 0, 0.]])
        vi = (c["wi"], [], [0.0])
    wz_i, bz_i, wp_i, bp_i = c["wi_filter"] or (1., 1., 1., 1.)
    zlead, plead, klead = [-c["wz"]], [-c["wp"]], kp * c["wp"] / c["wz"]
    if c["wi_filter"]:
        i_pre = sos(_zpk_quad(wz_i, bz_i), _zpk_quad(wp_i, bp_i), wp_i**2 / wz_i**2)
        i_post = sos(vi[1] + zlead + _zpk_quad(wp_i, bp_i), vi[2] + plead + _zpk_quad(wz_i, bz_i), vi[0] * klead * wz_i**2 / wp_i**2)
    else:
        i_pre = np.zeros((0, 6))
        i_post = sos(vi[1] + zlead, vi[2] + plead, vi[0] * klead)
    wz_n, bz_n, wp_n, bp_n = c["notch"]
    post = sos(_zpk_quad(wz_n, bz_n), _zpk_quad(wp_n, bp_n), 1.0)
    packed = np.vstack([np.zeros((0, 6)), hlp, lp_post, p, i_pre, hi, i_post, post])
    counts = np.array([0, len(lp_post), len(p), len(i_pre), len(i_post), len(post)], dtype=np.int64)
    omega = (wc_lp * TS / SQ if higs else 0.0, wc_i * TS / SQ if higs else 0.0)
    return packed, counts, omega


def pack(d, kp, higs_on=None):
    """Arrays for the numba kernel; higs_on overrides (False: linear counterpart of a HIGS design)."""
    packed, counts, omega = sections(d, kp)
    on = d["mode"] != "linear" if higs_on is None else higs_on
    return dict(coef=np.ascontiguousarray(packed[:, [0, 1, 2, 4, 5]]), cnt=counts, hl_on=on, hl_wts=omega[0], hi_on=on, hi_wts=omega[1])


# ------------------------------------------------------------------ frequency domain
class Grid:
    def __init__(self, f, P):
        self.f = np.asarray(f, float)
        self.w = 2 * np.pi * self.f
        self.sw = 1j * (2 / TS) * np.tan(self.w * TS / 2)
        self.P = np.atleast_2d(P)

    def sub(self, idx):
        return Grid(self.f[idx], self.P[:, idx])


def notch_fr(sw, n):
    wz, bz, wp, bp = n
    return (sw**2 + 2 * bz * wz * sw + wz**2) / (sw**2 + 2 * bp * wp * sw + wp**2)


def ctrl_parts(g, d, tab):
    """DF controller C (without kp) and G = lead (1 + D_i V_i) V_lp Cn (the uncertain part's linear factor) on grid g."""
    c = corners(d)
    sw = g.sw
    wl = c["wl"]
    lpb = wl**2 / (sw**2 + np.sqrt(2) * wl * sw + wl**2)
    lead = (1 + sw / c["wz"]) / (1 + sw / c["wp"])
    cn = notch_fr(sw, c["notch"])
    if d["mode"] == "linear":
        return lpb * lead * (1 + c["wi"] / sw) * cn, None, None
    vlp = (sw + c["wc_lp"]) / c["wc_lp"] * lpb
    nlp = tab(c["wc_lp"] / (2 * np.pi), g.f)
    ni = tab(c["wc_i"] / (2 * np.pi), g.f)
    ib = ni * c["wi"] / c["wc_i"] * (sw + c["wc_i"]) / sw
    pid = lead * (1 + ib)
    return nlp * vlp * pid * cn, pid * vlp * cn, nlp


def delta_weight(g, d, tab, f_min=F_MIN_HZ):
    """W_Delta(w) = |D(j w_min) - D(j w)| for f >= F_START_HZ (eq. 7.48)."""
    wc_hz = d["fc"] * d["wc_lp_ratio"]
    dm = tab(wc_hz, np.array([f_min]))[0]
    return np.where(g.f >= F_START_HZ, np.abs(dm - tab(wc_hz, g.f)), 0.0)


class Gate:
    """Members: S = measured (spliced) FRFs, row 0 nominal (ms060); M = frictionless model (dense) with winding check."""

    def __init__(self, S, M, tab):
        self.S, self.M, self.tab = S, M, tab
        self.cache = {}

    def kp_for_unity(self, d):
        g = Grid([d["fc"]], np.array([[np.interp(d["fc"], self.S.f, self.S.P[0].real) + 1j * np.interp(d["fc"], self.S.f, self.S.P[0].imag)]]))
        cc, _, _ = ctrl_parts(g, d, self.tab)
        return 1.0 / abs(cc[0] * g.P[0, 0])

    def terms(self, d, kp, lam, f_min=F_MIN_HZ):
        """Per S member: max over f of |S|/2 + lam |W_a S P| (term), the same with the two sup norms added (term_normsum), max|S|;
        model: max|S|."""
        cs, wa_unit, _ = ctrl_parts(self.S, d, self.tab)
        L = kp * cs[None, :] * self.S.P
        s = 1 / np.abs(1 + L)
        out = dict(S_members=s.max(axis=1), S_peak_hz=self.S.f[np.argmax(s, axis=1)], fc=R.first_crossover(self.S.f, L[0]))
        if wa_unit is None or lam == 0.0:
            out["term"] = out["term_normsum"] = np.max(s / S_LIMIT, axis=1)
        else:
            wa = delta_weight(self.S, d, self.tab, f_min) * kp * np.abs(wa_unit)
            wasp = wa[None, :] * s * np.abs(self.S.P)
            out["term"] = np.max(s / S_LIMIT + lam * wasp, axis=1)
            out["term_normsum"] = np.max(s / S_LIMIT, axis=1) + lam * np.max(wasp, axis=1)
        cm, _, _ = ctrl_parts(self.M, d, self.tab)
        Lm = kp * cm[None, :] * self.M.P
        sm = 1 / np.abs(1 + Lm)
        out["S_model"] = float(sm[0].max())
        out["S_model_hz"] = float(self.M.f[np.argmax(sm[0])])
        out["S_model_unc"] = [float(sm[i, self.M.f <= UNC_MAX_HZ].max()) for i in range(1, len(sm))]
        out["winding_ok"] = bool(np.all(R.nyquist_stable_many(Lm)))
        return out

    def evaluate(self, d, lam):
        """None if infeasible, else dict(kp, fc, ...). Constraint: term <= 1 on the three measured S members (ms060, ms030, ms100),
        |S| <= 2 on the model and its stiffness -10 % / +10 % members (<= 2 kHz), winding on all model members, HIGS ratios."""
        kp = self.kp_for_unity(d)
        t = self.terms(d, kp, lam)
        if t["fc"] is None or np.max(t["term"]) > 1.0 or t["S_model"] > S_LIMIT or max(t["S_model_unc"]) > S_LIMIT or not t["winding_ok"] or hf_gain(self.S, d, kp) > HF_GAIN_MAX:
            return None
        if d["mode"] != "linear":
            r = higs_ratios(d, t["fc"])
            if not (BOOK_LP[0] <= r["lp"] <= BOOK_LP[1] and BOOK_I[0] <= r["i"] <= BOOK_I[1]):
                return None
        t["kp"] = kp
        return t

    def cascade(self, d, kp, limit=S_LIMIT):
        """Numeric DF of the whole HIGS cascade (incl. W_i, notch) replaces the product of DFs for f in [8 Hz, FS / 4];
        returns (ok, S_max) with |S| <= limit on S and M and winding on M."""
        pk = pack(d, kp)
        n_list = np.unique(np.round(np.geomspace(4, FS / 8., 36)).astype(np.int64))
        vals = np.array([_ctrl_df(int(n), pk["coef"], pk["cnt"], pk["hl_on"], pk["hl_wts"], pk["hi_on"], pk["hi_wts"], 5, 2) for n in n_list])
        fg = FS / n_list
        order = np.argsort(fg)
        fg, vals = fg[order], vals[order]
        smax, ok = 0.0, True
        for g, check in ((self.S, False), (self.M, True)):
            cs, _, _ = ctrl_parts(g, d, self.tab)
            cn = np.interp(np.log(g.f), np.log(fg), vals.real) + 1j * np.interp(np.log(g.f), np.log(fg), vals.imag)
            ctrl = np.where((g.f <= FS / 4) & (g.f >= fg[0]), cn, kp * cs)
            L = ctrl[None, :] * g.P
            sg = 1 / np.abs(1 + L)
            smax = max(smax, float(sg[0].max()) if check else float(sg.max()))
            if check:
                smax = max(smax, float(sg[1:, g.f <= UNC_MAX_HZ].max()))
                ok = ok and bool(np.all(R.nyquist_stable_many(L)))
        return bool(ok and smax <= limit), smax


def hf_gain(g, d, kp):
    """max |kp C*| for f >= HF_GAIN_HZ with the linear counterpart C* (HIGS replaced by H^-1 D = 1): noise amplification limit."""
    sel = g.f >= HF_GAIN_HZ
    sw = g.sw[sel]
    c = corners(d)
    wl = c["wl"]
    cstar = wl**2 / (sw**2 + np.sqrt(2) * wl * sw + wl**2) * (1 + sw / c["wz"]) / (1 + sw / c["wp"]) * (1 + c["wi"] / sw)
    cstar = cstar * notch_fr(sw, c["notch"])
    return float(np.max(kp * np.abs(cstar)))


BOOK_LP, BOOK_I = H.BOOK_RATIOS["lp"], H.BOOK_RATIOS["i"]


def higs_ratios(d, fc_hz):
    return dict(lp=d["wc_lp_ratio"] * d["fc"] / SQ / fc_hz, i=d["wc_i_ratio"] * d["fc"] / SQ / fc_hz)


# ------------------------------------------------------------------ time domain
class Td:
    p = None
    ad = bm = bd = None


def set_td_model(p):
    Td.p = p
    Td.ad, Td.bm, Td.bd = (np.ascontiguousarray(x) for x in R.discrete_plant(p))


_REF = {}


def reference():
    if "r" not in _REF:
        _REF["r"] = base.reference_profile()
    return _REF["r"]


def td_run(pk, ref, dist, quantized, ilim=CURRENT_LIMIT_A, du=None):
    n = len(ref)
    du = np.zeros(n) if du is None else du
    th_m, th_l, cmd = np.zeros(n), np.zeros(n), np.zeros(n)
    eq = 2 * np.pi / ENC_COUNTS if quantized else 0.0
    code = _td(ref, dist, du, pk["coef"], pk["cnt"], pk["hl_on"], pk["hl_wts"], pk["hi_on"], pk["hi_wts"],
               Td.ad, Td.bm, Td.bd, TD_DELAY, ilim, eq, th_m, th_l, cmd)
    return th_m, th_l, cmd, code


def td_metrics(pk, quantized=True):
    """Round trip (reference_profile, 1.6 s) and load-torque step (0.005 at 0.1 s, 1.2 s) on the frictionless design model."""
    ref = reference()
    th_m, th_l, cmd, code = td_run(pk, ref, np.zeros(len(ref)), quantized)
    rec = dict(diverged=code < 0, clipped_samples=max(code, 0))
    if rec["diverged"]:
        rec["dist_diverged"] = True
        return rec, None
    e = ref - th_l
    win = R.reference_windows(ref)
    rec.update(move_rms_mrad=1e3 * float(np.sqrt(np.mean(e**2))), peak_error_mrad=1e3 * float(np.max(np.abs(e))),
               settle_rms_urad=1e6 * float(np.sqrt(np.mean(e[win]**2))), peak_current_ma=1e3 * float(np.max(np.abs(cmd))),
               twist_200_400hz_rms_urad=1e6 * R.band_rms(th_m - th_l, *R.TWIST_BAND_HZ),
               tail_rms_urad=1e6 * float(np.sqrt(np.mean(e[-R.TAIL_N():]**2))))
    n = round(1.2 / TS)
    dist = 0.005 * (np.arange(n) * TS >= 0.1)
    _, th_l2, cmd2, code2 = td_run(pk, np.zeros(n), dist, quantized)
    rec["dist_diverged"] = code2 < 0
    e2 = None
    if code2 >= 0:
        e2 = -th_l2
        rec.update(dist_iae_mrad_s=1e3 * float(np.sum(np.abs(e2)) * TS), dist_peak_mrad=1e3 * float(np.max(np.abs(e2))),
                   dist_tail_rms_urad=1e6 * float(np.sqrt(np.mean(e2[-R.TAIL_N():]**2))), dist_peak_current_ma=1e3 * float(np.max(np.abs(cmd2))))
    return rec, dict(e=e, e2=e2)


def td_sensitivity(d, kp, gate, amplitude=0.05, periods=8, skip=2, f_hi=1000.):
    """S measured in the time domain like the bench measurement: random-phase multisine on 40 log-spaced prime lines (5..f_hi Hz, 1 s
    period; primes keep the HIGS harmonics off the excited lines) added to the plant input current, S = plant input / disturbance at
    the excited lines (frictionless model, encoder quantisation, real HIGS law, reference 0).
    Returns max over the lines of |S| (TD) and of the DF prediction at the same lines, and the TD / DF values at four lines."""
    n1 = round(1.0 / TS)
    primes = np.array([k for k in range(5, int(f_hi) + 1) if all(k % q for q in range(2, int(k**0.5) + 1))])
    lines = primes[np.unique(np.round(np.geomspace(1, len(primes), 40)).astype(int) - 1)]
    rng = np.random.default_rng(7)
    t = np.arange(n1) * TS
    du1 = np.sum(np.sin(2 * np.pi * lines[:, None] * t[None, :] + rng.uniform(0, 2 * np.pi, (len(lines), 1))), axis=0)
    du1 *= amplitude / np.max(np.abs(du1))
    du = np.tile(du1, periods)
    _, _, u, code = td_run(pack(d, kp), np.zeros(len(du)), np.zeros(len(du)), True, du=du)
    if code < 0:
        return None
    seg = slice(skip * n1, periods * n1)
    k = np.arange(len(lines))
    U = np.fft.rfft(u[seg].reshape(-1, n1), axis=1).mean(axis=0)
    Dd = np.fft.rfft(du[seg].reshape(-1, n1), axis=1).mean(axis=0)
    s_td = np.abs(U[lines] / Dd[lines])
    cm, _, _ = ctrl_parts(Grid(lines.astype(float), np.ones((1, len(lines)))), d, gate.tab)
    pm = H.plant_frf(lines.astype(float), Td.p, TD_DELAY * TS)[1]
    s_df = np.abs(1 / (1 + kp * cm * pm))
    pick = [int(np.argmin(np.abs(lines - f))) for f in (11, 41, 151, 201, 401, 601)]
    return dict(max_S_td=float(s_td.max()), max_S_td_hz=float(lines[np.argmax(s_td)]), max_S_df_same_lines=float(s_df.max()),
                at_hz={int(lines[i]): dict(td=float(s_td[i]), df=float(s_df[i])) for i in pick})


def settled(e):
    nt = R.TAIL_N()
    tail, prev = np.sqrt(np.mean(e[-nt:]**2)), np.sqrt(np.mean(e[-2 * nt:-nt]**2))
    return bool(tail <= R.TAIL_LIMIT_URAD * 1e-6 or tail <= 0.9 * prev)


def td_screen(d, kp):
    """Real HIGS law: no divergence, no limit cycle, peak command <= PEAK_CMD_A in both records. Returns (ok, record)."""
    rec, tr = td_metrics(pack(d, kp))
    if rec["diverged"] or rec["dist_diverged"]:
        return False, rec
    ok = (rec["peak_current_ma"] <= 1e3 * PEAK_CMD_A and rec["dist_peak_current_ma"] <= 1e3 * PEAK_CMD_A and settled(tr["e"]) and settled(tr["e2"]))
    return bool(ok), rec


# ------------------------------------------------------------------ setup: fits, splice, members
def choose_splice(Ds, fits):
    """Lowest frequency from which both ms060 and ms100 agree with the frictionless model for SPLICE_RUN consecutive quarter-octave
    bins: |median phase(Hl / model)| <= SPLICE_PHASE_DEG and |median |Hl / model| - 1| <= SPLICE_MAG. Friction adds phase lead below."""
    f = Ds["ms060"]["f"]
    ref = fits["ms060"]["design"]
    m = H.plant_frf(f, ref["params"], ref["tau_samples"] * TS)[1]
    edges = 50. * 2 ** (np.arange(0, 3 * 4 + 1) / 4)                      # 50 .. 400 Hz
    rows, good = [], []
    for lo, hi in zip(edges[:-1], edges[1:]):
        s = (f >= lo) & (f < hi)
        rec = dict(lo_hz=float(lo), hi_hz=float(hi), n=int(s.sum()))
        ok = s.sum() > 0
        for amp in ("ms060", "ms100"):
            r = Ds[amp]["Hl"][s] / m[s]
            rec[amp] = dict(mag_err=float(np.median(np.abs(r)) - 1), phase_deg=float(np.degrees(np.median(np.angle(r)))))
            ok = ok and abs(rec[amp]["phase_deg"]) <= SPLICE_PHASE_DEG and abs(rec[amp]["mag_err"]) <= SPLICE_MAG
        rec["agree"] = bool(ok)
        rows.append(rec)
        good.append(ok)
    for i in range(len(good) - SPLICE_RUN + 1):
        if all(good[i:i + SPLICE_RUN]):
            return float(edges[i]), rows
    raise RuntimeError("no splice frequency found")


def build_setup(log=print):
    global TS, FS
    Ds = {n: H.load_frf(n) for n in AMPS}
    H.set_sample_time(Ds["ms060"]["Ts"])
    TS, FS = H.TS, H.FS
    fits = {}
    for n, D in Ds.items():
        free = H.free_fit(D, False)
        fits[n] = dict(free=free, design=H.frictionless_fit(D, free["tau_samples"]))
    f_splice, table = choose_splice(Ds, fits)
    for n, D in Ds.items():                         # sliding model refitted above the splice frequency (friction lead excluded)
        fits[n]["design"] = H.frictionless_fit(D, fits[n]["free"]["tau_samples"], band=(f_splice, 700.))
    log(f"splice {f_splice:.1f} Hz; ms060 design {H.fmt_p(fits['ms060']['design']['params'])}, tau {fits['ms060']['free']['tau_samples']:.2f} smp")
    fmax = H.F_MAX
    f = Ds["ms060"]["f"]
    fs_grid = np.concatenate([np.geomspace(0.5, f_splice, 80, endpoint=False), f[(f >= f_splice) & (f <= MEAS_MAX_HZ)],
                              np.geomspace(MEAS_MAX_HZ * 1.001, fmax, 40)])
    rows = []
    for amp in S_MEMBERS:
        D, fd = Ds[amp], fits[amp]["design"]
        mdl = H.plant_frf(fs_grid, fd["params"], fd["tau_samples"] * TS)[1]
        meas = np.interp(fs_grid, D["f"], D["Hl"].real) + 1j * np.interp(fs_grid, D["f"], D["Hl"].imag)
        rows.append(np.where((fs_grid >= f_splice) & (fs_grid <= MEAS_MAX_HZ), meas, mdl))
    fm_grid = np.unique(np.concatenate([np.geomspace(0.5, fmax, 450), np.linspace(100., 700., 240)]))
    fd = fits["ms060"]["design"]
    model = np.array([H.plant_frf(fm_grid, dict(fd["params"], stiffness=fd["params"]["stiffness"] * sc), fd["tau_samples"] * TS)[1]
                      for sc in (1.0,) + STIFFNESS_SCALE])
    set_td_model(fd["params"])
    tab = DFTab()
    gate = Gate(Grid(fs_grid, np.array(rows)), Grid(fm_grid, model), tab)
    gate.splice_hz = f_splice
    info = dict(splice_hz=f_splice, splice_table=table, fits={n: dict(free_params=H.fmt_p(v["free"]["params"]), tau_samples=v["free"]["tau_samples"],
                design_params=H.fmt_p(v["design"]["params"]), design_band_hz=v["design"]["band_hz"]) for n, v in fits.items()},
                members=[f"{n}_spliced" for n in S_MEMBERS], model_member="ms060_frictionless_model", Ds=Ds)
    return gate, info


def sub_gate(gate):
    def idx(f):
        return np.concatenate([np.where(f <= 600)[0][::3], np.where(f > 600)[0][::12]])
    return Gate(gate.S.sub(idx(gate.S.f)), gate.M.sub(idx(gate.M.f)), gate.tab)


# ------------------------------------------------------------------ search
def start_design(mode):
    d = dict(mode=mode, fc=60., r_i=3., lz_ratio=2., lpole_ratio=4., lp_hz=600., nz_hz=310., np_ratio=1., depth=0.3, np_beta=0.5,
             wc_lp_ratio=1.5 * SQ, wc_i_ratio=0.5 * SQ)
    if mode != "linear":
        d.update(WI_BOOK)
    return d


def keys_for(mode, objective):
    k = list(FD_KEYS)
    if mode != "linear":
        k += list(HIGS_KEYS)
        if objective == "error":
            k += list(TD_KEYS)
    return k


def clip(d):
    return {k: (float(np.clip(v, *BOUNDS[k])) if k in BOUNDS else v) for k, v in d.items()}


def random_designs(mode, n, rng, fd_keys):
    """Log-uniform samples."""
    out = []
    for i in range(n):
        d = start_design(mode)
        for k in fd_keys:
            lo, hi = BOUNDS[k]
            d[k] = float(np.exp(rng.uniform(np.log(lo), np.log(hi))))
        out.append(d)
    return out


class Search:
    def __init__(self, gate, gate_sub, mode, lam, objective, rng, log):
        self.gate, self.gate_sub, self.mode, self.lam, self.objective, self.rng, self.log = gate, gate_sub, mode, lam, objective, rng, log
        self.cache = {}
        self.n_td = 0

    def fd(self, d, g=None):
        return (g or self.gate).evaluate(d, self.lam)

    def accept(self, d):
        """Full gate + time-domain screen + cascade DF gate. Returns dict(kp, fc, ..., rms) or None. Cached."""
        key = tuple(d.values())
        if key not in self.cache:
            res = None
            r = self.fd(d)
            if r is not None:
                ok, rec = td_screen(d, r["kp"])
                self.n_td += 1
                if ok:
                    casc_ok, casc_s = (True, None) if self.mode == "linear" else self.gate.cascade(d, r["kp"])
                    if casc_ok:
                        res = dict(r, rms=rec["move_rms_mrad"], cascade_S=casc_s)
            self.cache[key] = res
        return self.cache[key]

    def cost(self, d):
        r = self.accept(d)
        if r is None:
            return None
        return -r["fc"] if self.objective == "maxbw" else r["rms"]

    def refine(self, d, keys, steps=(0.2, 0.1, 0.05, 0.025, 0.0125), pair_tries=80, max_evals=4000):
        c = self.cost(d)
        n = 0
        for step in steps:
            improved = True
            while improved and n < max_evals:
                improved = False
                for k in keys:
                    for sgn in (1 + step, 1 / (1 + step)):
                        q = dict(d)
                        q[k] = float(np.clip(d[k] * sgn, *BOUNDS[k]))
                        if q[k] == d[k]:
                            continue
                        n += 1
                        cq = self.cost(q)
                        if cq is not None and cq < c - 1e-9 * abs(c):
                            d, c, improved = q, cq, True
            if step <= 0.1:
                for _ in range(pair_tries):
                    a, b = self.rng.choice(len(keys), 2, replace=False)
                    q = dict(d)
                    for i in (a, b):
                        q[keys[i]] = float(np.clip(d[keys[i]] * (1 + step * self.rng.uniform(-1.5, 1.5)), *BOUNDS[keys[i]]))
                    cq = self.cost(q)
                    if cq is not None and cq < c - 1e-9 * abs(c):
                        d, c = q, cq
        return d, c

    def feasible_start(self, d, tries=200, factor=0.97):
        """Shrink fc (all ratios kept) until the full accept test passes."""
        d = dict(d)
        for _ in range(tries):
            if self.accept(d) is not None:
                return d
            d["fc"] *= factor
            if d["fc"] < BOUNDS["fc"][0]:
                break
        return None

    def starts(self, n_random, n_top, extra):
        fd_keys = [k for k in keys_for(self.mode, "maxbw")]
        found = []
        for d in random_designs(self.mode, n_random, self.rng, fd_keys):
            r = self.fd(d, self.gate_sub)
            if r is not None:
                found.append((r["fc"], d))
        found.sort(key=lambda x: -x[0])
        out = []
        for fc, d in found:
            if all(abs(fc / x - 1) > 5e-3 for x, _ in out):
                out.append((fc, d))
            if len(out) >= n_top:
                break
        self.log(f"    {self.mode} lam {self.lam} {self.objective}: {len(found)} feasible of {n_random} random designs (search grid)")
        return [d for _, d in out] + extra

    def run(self, n_random, n_top, extra=()):
        keys = keys_for(self.mode, self.objective)
        results = []
        for s in self.starts(n_random, n_top, list(extra)):
            d0 = self.feasible_start(s)
            if d0 is None:
                continue
            # first release all FD parameters with the max-crossover objective on the full grid, then (error) the RMS objective
            d, c = self.refine(d0, keys if self.objective == "maxbw" else keys)
            results.append((c, d))
            self.log(f"    start -> cost {c:.5g}  fc {self.accept(d)['fc']:.2f} Hz")
        if not results:
            return None
        results.sort(key=lambda x: x[0])
        return results[0][1]


# ------------------------------------------------------------------ reporting
def tuning_fields(d, kp):
    c = corners(d)
    t = dict(kp=float(kp), integral_hz=d["fc"] / d["r_i"], lead_zero_hz=d["fc"] / d["lz_ratio"], lead_pole_hz=d["fc"] * d["lpole_ratio"],
             lowpass_hz=d["lp_hz"], higs_lp_corner_hz=d["fc"] * d["wc_lp_ratio"] if d["mode"] != "linear" else 100.,
             higs_i_corner_hz=d["fc"] * d["wc_i_ratio"] if d["mode"] != "linear" else 2., higs_lp_gain=1.0, higs_i_gain=1.0)
    wz, bz, wp, bp = c["notch"]
    t.update(notch_zero_hz=wz / (2 * np.pi), notch_pole_hz=wp / (2 * np.pi), notch_zero_beta=bz, notch_pole_beta=bp)
    if d["mode"] != "linear":
        wz, bz, wp, bp = c["wi_filter"]
        t.update(wi_zero_hz=wz / (2 * np.pi), wi_pole_hz=wp / (2 * np.pi), wi_zero_beta=bz, wi_pole_beta=bp)
    return t


def describe(gate, d, lam_list=LAMBDAS):
    kp = gate.kp_for_unity(d)
    out = dict(design=d, kp=float(kp), tuning=tuning_fields(d, kp))
    t0 = gate.terms(d, kp, 0.0)
    out["crossover_hz"] = t0["fc"]
    out["S_max_measured"] = dict(zip(MEMBER_NAMES, map(float, t0["S_members"])))
    out["S_max_peak_hz"] = dict(zip(MEMBER_NAMES, map(float, t0["S_peak_hz"])))
    out["hf_gain_a_per_rad"] = hf_gain(gate.S, d, kp)
    out["edge_flags"] = [k for k in keys_for(d["mode"], "error") if d[k] <= BOUNDS[k][0] * 1.005 or d[k] >= BOUNDS[k][1] * 0.995]
    flags = []
    if out["hf_gain_a_per_rad"] >= 0.99 * HF_GAIN_MAX:
        flags.append("hf_gain_cap")
    if d["mode"] != "linear":
        r = higs_ratios(d, t0["fc"])
        flags += [f"book_ratio_{k}_{'low' if r[k] <= 1.01 * b[0] else 'high'}" for k, b in (("lp", BOOK_LP), ("i", BOOK_I)) if r[k] <= 1.01 * b[0] or r[k] >= 0.99 * b[1]]
    out["binding_constraints"] = flags
    out["S_max_model"] = t0["S_model"]
    out["S_max_model_stiffness_pm10pct_upto2kHz"] = dict(zip(("x0.9", "x1.1"), t0["S_model_unc"]))
    ab = gate.S.f >= gate.splice_hz
    cs, _, _ = ctrl_parts(gate.S, d, gate.tab)
    out["S_max_measured_above_splice"] = dict(zip(MEMBER_NAMES, map(float, (1 / np.abs(1 + kp * cs[None, :] * gate.S.P))[:, ab].max(axis=1))))
    out["S_max_model_hz"] = t0["S_model_hz"]
    out["winding_ok_model"] = t0["winding_ok"]
    for lam in lam_list:
        t = gate.terms(d, kp, lam)
        out[f"eq813_term_lambda{lam:g}"] = dict(zip(MEMBER_NAMES, map(float, t["term"])))
        out[f"eq813_normsum_lambda{lam:g}"] = dict(zip(MEMBER_NAMES, map(float, t["term_normsum"])))
    if d["mode"] != "linear":
        t = gate.terms(d, kp, 0.4, f_min=10.)
        out["eq813_term_lambda0.4_wmin10Hz"] = dict(zip(MEMBER_NAMES, map(float, t["term"])))
    wz_n, _, wp_n, _ = corners(d)["notch"]
    out["kp_times_notch_dc_gain"] = float(kp * (wz_n / wp_n) ** 2)
    if d["mode"] != "linear":
        out["higs_omega_h_over_crossover"] = higs_ratios(d, t0["fc"])
        out["higs_corner_hz"] = dict(lp=d["fc"] * d["wc_lp_ratio"] / SQ, i=d["fc"] * d["wc_i_ratio"] / SQ, note="omega_h; DF corner omega_c = SQ * omega_h")
    L = kp * ctrl_parts(gate.S, d, gate.tab)[0] * gate.S.P[0]
    mt = R.loop_metrics(gate.S.f, L)
    out["margins_nominal"] = dict(fc_hz=mt["fc_hz"], pm_deg=mt["pm_deg"], pm_min_deg=mt["pm_min_deg"], gm_up_db=mt["gm_up_db"], gm_low_db=mt["gm_low_db"])
    ok, rec = td_screen(d, kp)
    out["td_screen_ok"] = ok
    for name, q in (("time_domain_quantised_2e20", True), ("time_domain_unquantised", False)):
        rec, _ = td_metrics(pack(d, kp), quantized=q)
        out[name] = {k: v for k, v in rec.items()}
    out["td_sensitivity_multisine"] = td_sensitivity(d, kp, gate)
    if d["mode"] != "linear":
        out["cascade_ok"], out["cascade_S"] = gate.cascade(d, kp)
        lin, _ = td_metrics(pack(d, kp, higs_on=False))
        out["linear_counterpart_td"] = {k: lin.get(k) for k in ("move_rms_mrad", "peak_current_ma", "twist_200_400hz_rms_urad")}
        out["linear_counterpart_S_max"] = linear_counterpart_s(gate, d, kp)
        nowi, _ = td_metrics(pack(dict(d, wi_ratio=1.0), kp))
        out["time_domain_without_wi"] = {k: nowi.get(k) for k in ("move_rms_mrad", "settle_rms_urad", "peak_current_ma", "twist_200_400hz_rms_urad", "dist_iae_mrad_s")}
    return out


def linear_counterpart_s(gate, d, kp):
    """max|S| of the design with every HIGS replaced by its linear C* (HIGS ignored): ms060 / ms030 members and the model."""
    out = []
    for g in (gate.S, gate.M):
        sw = g.sw
        c = corners(d)
        wl = c["wl"]
        cs = wl**2 / (sw**2 + np.sqrt(2) * wl * sw + wl**2) * (1 + sw / c["wz"]) / (1 + sw / c["wp"]) * (1 + c["wi"] / sw)
        cs = cs * notch_fr(sw, c["notch"])
        out += list((1 / np.abs(1 + kp * cs[None, :] * g.P)).max(axis=1))
    return dict(zip(MEMBER_NAMES + ("model", "model_x0.9", "model_x1.1"), map(float, out)))


def python_port_check(d, kp):
    """Round-trip RMS with the class-based Python port (R.Higs, R.Biquad, the C++ Step order) vs the numba kernel."""
    pk = pack(d, kp)
    coef = pk["coef"]
    bqs = [R.Biquad([row[0], row[1], row[2], 1.0, row[3], row[4]]) for row in coef]
    cnt = pk["cnt"]
    hl, hi = (R.Higs(pk["hl_wts"]) if pk["hl_on"] else None), (R.Higs(pk["hi_wts"]) if pk["hi_on"] else None)

    def step(e):
        o, x = 0, e
        x = (hl.step(x) if hl else bqs[o].step(x)); o += 1
        for i in range(cnt[1]):
            x = bqs[o + i].step(x)
        o += cnt[1]
        p = x
        for i in range(cnt[2]):
            p = bqs[o + i].step(p)
        o += cnt[2]
        v = x
        for i in range(cnt[3]):
            v = bqs[o + i].step(v)
        o += cnt[3]
        v = hi.step(v) if hi else bqs[o].step(v)
        o += 1
        for i in range(cnt[4]):
            v = bqs[o + i].step(v)
        o += cnt[4]
        y = p + v
        for i in range(cnt[5]):
            y = bqs[o + i].step(y)
        return y

    class C:
        pass
    c = C()
    c.step = step
    H.set_td_model(Td.p, TD_DELAY)
    out, _, div = H.simulate_hw(c, reference(), quantized=True, current_limit=CURRENT_LIMIT_A, angle_counts=ENC_COUNTS)
    e = reference() - out[:, 2]
    return 1e3 * float(np.sqrt(np.mean(e**2))), bool(div)


# ------------------------------------------------------------------ worker
def record(gate, d, name, mode, lam, objective):
    rec = describe(gate, d)
    rec.update(name=name, mode=mode, lam=lam, objective=objective)
    rec["rms_port_check"] = python_port_check(d, rec["kp"])
    return rec


def variant_worker(args):
    """One family (linear, or both at a given lambda): maximum-crossover design, then the error-optimal design started from it."""
    name, mode, lam, seed, n_random, n_top, hf_gain_max = args
    global HF_GAIN_MAX
    HF_GAIN_MAX = hf_gain_max
    t0 = time.time()
    gate, _ = build_setup(log=lambda *a: None)
    rng = np.random.default_rng(seed)

    def log(*a):
        print(f"[{name} {time.time() - t0:5.0f}s] " + " ".join(str(x) for x in a), flush=True)

    out = {}
    d_bw = None
    for objective in ("maxbw", "error"):
        search = Search(gate, sub_gate(gate), mode, lam, objective, rng, log)
        d = search.run(n_random if objective == "maxbw" else n_random // 3, n_top, [d_bw] if d_bw else [])
        if d is None:
            log(objective, "no feasible design")
            continue
        if objective == "maxbw":
            d_bw = d
        rec = record(gate, d, f"{name}_{objective}", mode, lam, objective)
        out[objective] = rec
        log(objective, f"fc {rec['crossover_hz']:.1f} Hz  RMS {rec['time_domain_quantised_2e20']['move_rms_mrad']:.4f} mrad  "
            f"max|S| {rec['S_max_measured']} model {rec['S_max_model']:.3f}")
    return name, out


def exp05_design(rec, label):
    ref = json.loads((ROOT / "simulations/higs_design.json").read_text())
    d = dict(ref)
    d.update(sample_time_s=TS, sensitivity_limit=2, max_current_a=CURRENT_LIMIT_A, max_position_rad=0.5, max_velocity_rad_s=5, max_twist_rad=0.05)
    tun = dict(rec["tuning"])
    tun["measured_crossover_target_hz"] = rec["design"]["fc"]
    tun["gain_basis"] = ("Load FRF frf_ms060.mat (Hl) spliced with the frictionless two-inertia fit below %.0f Hz; kp = 1 / |C(j2 pi fc) G(j2 pi fc)| "
                         "at the design crossover fc (delay 0 samples, the FRF contains the delay)" % rec["splice_hz"])
    d["tuning"] = tun
    d["provenance"] = (f"simulations/higs_book_design.py {label}: error-optimal under eq. 8.13 (lambda = {rec['lam']:g}) with notch and W_i, "
                       f"book ratios, frf_ms060.mat (primary), frf_ms030.mat, frf_ms100.mat, model stiffness x0.9/x1.1 members; peak command <= {PEAK_CMD_A} A on the frictionless model, delay {TD_DELAY} samples")
    h = hashlib.sha256()
    for n in ("frf_ms060.mat", "frf_ms030.mat", "frf_ms100.mat"):
        h.update((H.DATA / n).read_bytes())
    d["source_sha256"] = h.hexdigest()
    return d


def main():
    global HF_GAIN_MAX
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--output", type=Path, default=OUT)
    ap.add_argument("--n-random", type=int, default=40000)
    ap.add_argument("--n-top", type=int, default=8)
    ap.add_argument("--seeds", type=int, default=4, help="independent random-start searches per family; the best result is kept")
    ap.add_argument("--workers", type=int, default=12)
    ap.add_argument("--hf-gain-max", type=float, default=HF_GAIN_MAX, help="A/rad, max |kp C*| above 1 kHz")
    ap.add_argument("--lambdas", default=",".join(f"{x:g}" for x in LAMBDAS), help="values of lambda for the two-HIGS family")
    args = ap.parse_args()
    t0 = time.time()
    gate, info = build_setup()
    lambdas = [float(x) for x in args.lambdas.split(",")]
    families = [("linear", "linear", 0.0)] + [(f"both_lam{lam:g}", "both", lam) for lam in lambdas]
    jobs = [(f"{fam}__s{seed}", mode, lam, seed, args.n_random, args.n_top, args.hf_gain_max) for fam, mode, lam in families for seed in range(1, args.seeds + 1)]
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        res = dict(ex.map(variant_worker, jobs))
    designs, candidates = {}, {}
    for fam, _, _ in families:
        for objective in ("maxbw", "error"):
            cand = [(seed, res[f"{fam}__s{seed}"][objective]) for seed in range(1, args.seeds + 1) if objective in res[f"{fam}__s{seed}"]]
            val = (lambda r: -r["crossover_hz"]) if objective == "maxbw" else (lambda r: r["time_domain_quantised_2e20"]["move_rms_mrad"])
            seed, best = min(cand, key=lambda x: val(x[1]))
            best.update(name=f"{fam}_{objective}", seed=seed, splice_hz=info["splice_hz"])
            designs[best["name"]] = best
            candidates[best["name"]] = {f"seed{sd}": (r["crossover_hz"] if objective == "maxbw" else r["time_domain_quantised_2e20"]["move_rms_mrad"]) for sd, r in cand}
    HF_GAIN_MAX = args.hf_gain_max
    rng = np.random.default_rng(1)
    for objective in ("maxbw", "error"):          # the feasible set of lambda is nested: a design found at a smaller lambda is a start at a larger one
        for i, lam in enumerate(lambdas):
            name = f"both_lam{lam:g}_{objective}"
            search = Search(gate, sub_gate(gate), "both", lam, objective, rng, print)
            for prev in lambdas[:i]:
                d0 = search.feasible_start(designs[f"both_lam{prev:g}_{objective}"]["design"])
                if d0 is None:
                    continue
                d1, c1 = search.refine(d0, keys_for("both", objective))
                c0 = search.cost(designs[name]["design"])
                if c0 is None or c1 < c0:
                    print(f"{name}: restart from lambda {prev:g} design improves cost {c0} -> {c1}")
                    designs[name] = record(gate, d1, name, "both", lam, objective)
                    designs[name].update(seed=f"from_lambda{prev:g}", splice_hz=info["splice_hz"])
    lin = designs.get("linear_error")
    both = designs.get("both_lam0.4_error")
    out = dict(
        setup=dict(splice_hz=info["splice_hz"], splice_rule=f"lowest quarter-octave bin (50..400 Hz) starting {SPLICE_RUN} consecutive bins in which ms060 and ms100 agree "
                   f"with the frictionless model: |median phase| <= {SPLICE_PHASE_DEG} deg and |median magnitude error| <= {SPLICE_MAG}; the model is refitted above the splice frequency (700 Hz)",
                   splice_table=info["splice_table"], fits=info["fits"], members=info["members"], model_member=info["model_member"],
                   measured_max_hz=MEAS_MAX_HZ, sample_time_s=TS, td=dict(delay_samples=TD_DELAY, current_limit_a=CURRENT_LIMIT_A, encoder_counts=ENC_COUNTS,
                                                                       peak_command_limit_a=PEAK_CMD_A)),
        eq813=dict(W_S=f"1/{S_LIMIT:g} (|S| <= {S_LIMIT:g})", Delta="|D(j w_min) - D(j w)|, D = DF of the low-pass HIGS (numeric, discrete), eq. 7.48",
                   w_min_hz=F_MIN_HZ, w_start_hz=F_START_HZ, W_a="W_Delta |kp lead (1 + D_i V_i) V_lp Cn| (W_Delta = 0 below w_start)",
                   constraint="max_f (|W_S S| + lambda |W_a S P|) <= 1 on the ms060, ms030 and ms100 spliced members; |S| <= 2 (<= 2 kHz for the stiffness x0.9 / x1.1 members) and winding on the frictionless model and its two perturbed members",
                   lambdas=lambdas, book_ratios=dict(lp=BOOK_LP, i=BOOK_I), bounds={k: list(v) for k, v in BOUNDS.items()}),
        hf_gain_max_a_per_rad=args.hf_gain_max, seed_candidates=candidates, designs=designs, runtime_s=time.time() - t0)
    args.output.mkdir(parents=True, exist_ok=True)
    adopted_both = both or designs.get("both_lam0_error")
    if lin is not None and adopted_both is not None:
        for n, r, label in (("book_linear.json", lin, "linear"), ("book_both.json", adopted_both, "both")):
            (args.output / n).write_text(json.dumps(R.jsonable(exp05_design(r, label)), indent=2, allow_nan=False) + "\n")
        out["adopted"] = dict(linear="linear_error", both=adopted_both["name"])
        print({k: f"{r['crossover_hz']:.1f} Hz, RMS {r['time_domain_quantised_2e20']['move_rms_mrad']:.4f} mrad" for k, r in designs.items()})
    (args.output / "book_design.json").write_text(json.dumps(R.jsonable(out), indent=1, allow_nan=False) + "\n")
    print("saved", args.output, f"{time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
