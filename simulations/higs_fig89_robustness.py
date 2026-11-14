#!/usr/bin/env python3
"""Linear vs chapter-8 Fig. 8.9 HIGS controllers at equal robustness (measured FRF).

Python with numpy, scipy, matplotlib (see requirements.txt). No g++/MATLAB/TwinCAT needed:
the trimodal HIGS law of ControllerCore/ControllerAlgorithm.cpp is ported line by line.

Controller (as implemented by ControllerAlgorithm + higs_two_inertia.make_design, W = 1, Post = identity):
  x = LP-block[e];  u = kp*Lead[x] + kp*Lead[Vi[I-block[x]]]   =>  C* = kp * Clp * Lead * (1 + wi/s)
A HIGS block is HIGS -> V with V = H^-1 C*, H = kh*wc/(s+wc) (kh = 1, wh = wc/sqrt(1+16/pi^2)), so that
replacing the HIGS by H returns the linear block C*. Modes: linear, I (integrator HIGS), LP (low-pass HIGS), both.

Loop used for robustness:  L = kp*C(DF)*G8*exp(-j w Ts*extra)
  G8 = measured old 16 kHz load FRF re-expressed for an 8 kHz zero-order hold
       (higs_two_inertia.measured_response(): sinc(f*Ts)/sinc(f*Ts_src) * exp(-j*pi*f*(Ts-Ts_src))),
  extra = 1 (one-sample computational delay; scenario "nominal_delay1") or 6 (the stress used by the repo's
          measured_linear_metrics; scenario "stress_delay6"),
  digital controller blocks are bilinear (Tustin) as in the repo, evaluated at z = exp(j w Ts).
Time-domain checks use the identified model (exact ZOH, 2-sample delay) with the real nonlinear law.
Run:  python simulations/higs_fig89_robustness.py [--output DIR]   (about 12 minutes)
      python simulations/higs_fig89_robustness.py --gate-sweep      (max fc per mode vs gate strictness G0..G5, about 25 minutes)
      python simulations/higs_fig89_robustness.py --followup all    (old-shape linear limit, error-optimal designs, parameter table
                                                                     -> fig89_followup.json; needs fig89_gate_sweep.json)
"""
from __future__ import annotations
import argparse
import heapq
import itertools
import json
from pathlib import Path
import time

import numpy as np
from scipy import linalg, signal

import higs_two_inertia as base

ROOT = base.ROOT
TS = base.TS
FS = 1 / TS
SQ = float(np.sqrt(1 + 16 / np.pi**2))        # wc = SQ*wh for kh = 1
S_LIMIT = 2.0                                  # modulus margin: max|S| <= 6 dB
EXTRA_DELAY_SAMPLES = 1                        # one-sample computational delay
F_BAND = (1.0, 3990.0)                         # measured band used for S (Nyquist = 4000 Hz)
CURRENT_LIMIT = 0.08
MODES = ("linear", "I", "LP", "both")
TWIST_BAND_HZ = (200., 400.)
TAIL_LIMIT_URAD = 50.0
OUT_DIR = ROOT / "simulations/results"
TAIL_S = 0.2                                   # error-tail window [s] of the time-domain metrics and screens


def TAIL_N():
    return round(TAIL_S / TS)


# ------------------------------------------------------------------ HIGS law and DF
class Higs:
    """Port of ControllerAlgorithm::TryApplyHigs (gain = 1)."""
    __slots__ = ("wts", "gain", "state", "prev", "mode")

    def __init__(self, omega_ts, gain=1.0):
        self.wts, self.gain, self.state, self.prev, self.mode = omega_ts, gain, 0.0, 0.0, 0

    def step(self, x):
        cand = self.state + self.wts * x
        bnd = self.gain * x
        inside = (0.0 <= cand <= bnd) if x >= 0.0 else (bnd <= cand <= 0.0)
        same = (x >= 0.0 and self.prev >= 0.0) or (x <= 0.0 and self.prev <= 0.0)
        self.mode = 1 if inside else (2 if same else 3)
        self.state = cand if inside else (bnd if same else 0.0)
        self.prev = x
        return self.state


class Biquad:
    """Direct form II transposed, same as TryApplyBiquad. coefficients: b0 b1 b2 a1 a2."""
    __slots__ = ("b0", "b1", "b2", "a1", "a2", "s1", "s2")

    def __init__(self, sos_row):
        self.b0, self.b1, self.b2, _, self.a1, self.a2 = (float(v) for v in sos_row)
        self.s1 = self.s2 = 0.0

    def step(self, x):
        y = self.b0 * x + self.s1
        self.s1 = self.b1 * x - self.a1 * y + self.s2
        self.s2 = self.b2 * x - self.a2 * y
        return y


def df_analytic(w, wh):
    """Exact first-harmonic DF of the continuous HIGS (kh=1, gamma=0) vs w/wh. Input sin(theta):
    x = r(1-cos th) until th1 = 2 atan(w/wh), then x = sin th (gain mode); half-wave symmetric."""
    r = wh / w
    t1 = 2 * np.arctan(w / wh)
    s1, s2 = np.sin(t1), np.sin(2 * t1)
    b = 2 / np.pi * (r * ((1 - np.cos(t1)) - s1**2 / 2) + (np.pi - t1) / 2 + s2 / 4)
    a = 2 / np.pi * (r * (s1 - t1 / 2 - s2 / 4) - s1**2 / 2)
    return b + 1j * a


def df_numeric(n_per_period, wh_ts, amplitude=1.0, phase0=0.3, periods=8, keep=3):
    """First harmonic of the discrete HIGS (the C++ law) for a sine of n samples per period."""
    h = Higs(wh_ts)
    n = int(n_per_period)
    k = np.arange(periods * n)
    th = 2 * np.pi * k / n + phase0
    u = amplitude * np.sin(th)
    y = np.empty_like(u)
    for i, v in enumerate(u):
        y[i] = h.step(float(v))
    sl = slice((periods - keep) * n, periods * n)
    thk = th[sl] % (2 * np.pi)
    b = 2 / (keep * n) * np.sum(y[sl] * np.sin(thk)) / amplitude
    a = 2 / (keep * n) * np.sum(y[sl] * np.cos(thk)) / amplitude
    return b + 1j * a


def df_check():
    """Numeric DF (discrete law, Ts=125 us, 0.5 Hz..2 kHz) vs analytic; amplitude and w/wh scaling."""
    n_list = np.unique(np.round(np.geomspace(4, 16000, 70)).astype(int))
    f = FS / n_list
    out = dict(freq_hz=f.tolist(), cases=[])
    for wc_hz in (5., 20., 80.):
        wh = 2 * np.pi * wc_hz / SQ
        num = np.array([df_numeric(n, wh * TS) for n in n_list])
        ana = df_analytic(2 * np.pi * f, wh)
        err = np.abs(num - ana)
        out["cases"].append(dict(wc_hz=wc_hz, abs_error=err.tolist(), numeric_re=num.real.tolist(),
                                 numeric_im=num.imag.tolist(), analytic_re=ana.real.tolist(),
                                 analytic_im=ana.imag.tolist(), w_over_wh=(2 * np.pi * f / wh).tolist()))
    # amplitude independence (exact homogeneity) and phase-offset independence
    n, wts = 400, 2 * np.pi * 20 / SQ * TS
    ref = df_numeric(n, wts)
    out["amplitude_max_dev"] = float(max(abs(df_numeric(n, wts, amplitude=a) - ref) for a in (1e-6, 1e-3, 1e3)))
    out["phase0_max_dev"] = float(max(abs(df_numeric(n, wts, phase0=p) - ref) for p in (0.0, 0.7, 2.0)))
    # same w/wh at two different wh: depends only on w/wh while w*Ts is small
    pairs = []
    for ratio in (0.1, 0.3, 1., 3., 10., 30.):
        v = []
        for wc_hz in (5., 50.):
            wh = 2 * np.pi * wc_hz / SQ
            fq = ratio * wh / (2 * np.pi)
            v.append(df_numeric(int(round(FS / fq)), wh * TS))
        pairs.append(dict(w_over_wh=ratio, abs_diff=float(abs(v[0] - v[1])), rel_diff=float(abs(v[0] - v[1]) / abs(v[0])),
                          freqs_hz=[ratio * 5 / SQ, ratio * 50 / SQ]))
    out["scaling_pairs_wh5_vs_wh50"] = pairs
    lf = df_analytic(2 * np.pi * 0.01, 2 * np.pi * 10)
    hf = df_analytic(2 * np.pi * 1e5, 2 * np.pi * 10) * (2 * np.pi * 1e5) / (2 * np.pi * 10)
    out["anchors"] = dict(low_freq=[lf.real, lf.imag], high_freq_mag_ratio_to_1p62=float(abs(hf) / SQ),
                          high_freq_phase_deg=float(np.degrees(np.angle(hf))))
    # lowest frequency at which the numeric DF deviates >2 % of |N| from the analytic one
    rng = []
    fq = np.array(out["freq_hz"])
    for c in out["cases"]:
        e = np.array(c["abs_error"])
        mag = np.abs(np.array(c["analytic_re"]) + 1j * np.array(c["analytic_im"]))
        bad = e / mag > 0.02
        rng.append(dict(wc_hz=c["wc_hz"], first_freq_over_2pct_hz=float(fq[bad].min()) if bad.any() else None,
                        max_rel_err_below_500hz=float(np.max((e / mag)[fq < 500]))))
    out["agreement"] = rng
    return out


class DFTable:
    """Numeric DF of the discrete HIGS (Ts = 125 us) tabulated over corner wc and frequency (integer
    samples per period), interpolated bilinearly in (log wc, log f). Above the highest tabulated
    frequency (2 kHz, 4 samples/period) |N| is continued with 1/f at constant phase."""

    def __init__(self, wc_hz=np.geomspace(0.1, 1000., 100), n_points=120):
        self.n = np.unique(np.round(np.geomspace(4, FS / F_BAND[0], n_points)).astype(int))
        self.f = FS / self.n[::-1]
        self.wc_hz = np.asarray(wc_hz)
        self.v = np.array([[df_numeric(int(n), 2 * np.pi * wc / SQ * TS, periods=4, keep=2) for n in self.n[::-1]]
                           for wc in self.wc_hz])

    def __call__(self, wc_rad, f):
        x = np.log(wc_rad / (2 * np.pi))
        g = np.log(self.wc_hz)
        j = int(np.clip(np.searchsorted(g, x) - 1, 0, len(g) - 2))
        t = float(np.clip((x - g[j]) / (g[j + 1] - g[j]), 0, 1))
        row = (1 - t) * self.v[j] + t * self.v[j + 1]
        lf = np.log(np.minimum(f, self.f[-1]))
        out = np.interp(lf, np.log(self.f), row.real) + 1j * np.interp(lf, np.log(self.f), row.imag)
        return out * np.minimum(1.0, self.f[-1] / f)


_TABLE = None


def df_table():
    global _TABLE
    if _TABLE is None:
        _TABLE = DFTable()
    return _TABLE


# ------------------------------------------------------------------ design -> blocks
def design_params(mode, fc, kp_scale, r_i, lead_ratio, lp_hz, wc_lp_ratio=None, wc_i_ratio=None):
    return dict(mode=mode, fc=float(fc), kp_scale=float(kp_scale), r_i=float(r_i),
                lead_ratio=float(lead_ratio), lp_hz=float(lp_hz),
                wc_lp_ratio=None if wc_lp_ratio is None else float(wc_lp_ratio),
                wc_i_ratio=None if wc_i_ratio is None else float(wc_i_ratio))


def corners(d):
    """Continuous-time corner frequencies [rad/s]."""
    tau = 2 * np.pi
    c = dict(wz=tau * d["fc"] / d["lead_ratio"], wp=tau * d["fc"] * d["lead_ratio"], wi=tau * d["fc"] / d["r_i"],
             wl=tau * d["lp_hz"], wc_lp=None, wc_i=None)
    if d["mode"] in ("LP", "both"):
        c["wc_lp"] = tau * d["fc"] * d["wc_lp_ratio"]
    if d["mode"] in ("I", "both"):
        c["wc_i"] = tau * d["fc"] * d["wc_i_ratio"]
    return c


def tuning_fields(d, kp):
    """MATLAB exp05_Higs design-JSON `tuning` fields of a design (kh = 1). HIGS corners a mode does not use are filled with
    higs_design.json's defaults (100 Hz / 2 Hz); they have no effect in that mode and are listed in `unused`."""
    fc = d["fc"]
    unused = ([] if d["mode"] in ("LP", "both") else ["higs_lp_corner_hz"]) + ([] if d["mode"] in ("I", "both") else ["higs_i_corner_hz"])
    if d["mode"] == "linear":
        unused += ["higs_lp_gain", "higs_i_gain"]
    return dict(kp=float(kp), integral_hz=fc / d["r_i"], lead_zero_hz=fc / d["lead_ratio"], lead_pole_hz=fc * d["lead_ratio"],
                lowpass_hz=d["lp_hz"],
                higs_lp_corner_hz=fc * d["wc_lp_ratio"] if d["wc_lp_ratio"] is not None else 100.,
                higs_i_corner_hz=fc * d["wc_i_ratio"] if d["wc_i_ratio"] is not None else 2.,
                higs_lp_gain=1.0, higs_i_gain=1.0, mode=d["mode"], unused=unused)


class FreqModel:
    """Frequency-domain evaluation of the loop on a frequency grid with a plant array G."""

    def __init__(self, f, G, extra_delay=EXTRA_DELAY_SAMPLES, analytic_df=False):
        self.analytic_df = analytic_df
        self.f, self.w = np.asarray(f), 2 * np.pi * np.asarray(f)
        self.sw = 1j * (2 / TS) * np.tan(self.w * TS / 2)          # bilinear image of j*w
        self.G = np.asarray(G) * np.exp(-1j * self.w * TS * extra_delay)
        self._df = {}

    def df(self, wc):
        key = round(float(wc), 6)
        if key not in self._df:
            self._df[key] = df_analytic(self.w, wc / SQ) if self.analytic_df else df_table()(wc, self.f)
        return self._df[key]

    def controller(self, d, c=None, df_override=None):
        """Describing-function controller C(jw) without kp (kp applied by caller)."""
        c = c or corners(d)
        sw = self.sw
        wl = c["wl"]
        lp = wl**2 / (sw**2 + np.sqrt(2) * wl * sw + wl**2)
        if c["wc_lp"] is not None:
            n = df_override["lp"] if df_override else self.df(c["wc_lp"])
            lp = n * (sw + c["wc_lp"]) / c["wc_lp"] * lp
        lead = (1 + sw / c["wz"]) / (1 + sw / c["wp"])
        if c["wc_i"] is not None:
            n = df_override["i"] if df_override else self.df(c["wc_i"])
            ib = n * c["wi"] / c["wc_i"] * (sw + c["wc_i"]) / sw
        else:
            ib = c["wi"] / sw
        return lp * lead * (1 + ib)

    def loop(self, d, kp):
        return kp * self.controller(d) * self.G

    def kp_for_unity(self, d, fc=None):
        """kp that makes |L(j 2 pi fc)| = 1 (gain basis for the design crossover)."""
        fc = d["fc"] if fc is None else fc
        sub = FreqModel.__new__(FreqModel)
        sub.f = np.array([fc]); sub.w = 2 * np.pi * sub.f
        sub.sw = 1j * (2 / TS) * np.tan(sub.w * TS / 2)
        gr = np.interp(fc, self.f, self.G.real); gi = np.interp(fc, self.f, self.G.imag)
        sub.G = np.array([gr + 1j * gi]); sub._df = {}; sub.analytic_df = self.analytic_df
        return 1.0 / abs(sub.controller(d)[0] * sub.G[0])


def loop_metrics(f, L):
    S = 1 / (1 + L)
    aS = np.abs(S)
    i = int(np.argmax(aS))
    mag = np.abs(L)
    ang = np.angle(L)
    down = np.where((mag[:-1] > 1) & (mag[1:] <= 1))[0]
    cross = []
    for j in down:
        t = np.log(mag[j]) / (np.log(mag[j]) - np.log(mag[j + 1]))
        fx = float(np.exp(np.log(f[j]) + t * (np.log(f[j + 1]) - np.log(f[j]))))
        ph = float(np.angle(np.exp(1j * ang[j]) * (np.exp(1j * ang[j + 1]) / np.exp(1j * ang[j])) ** t))
        cross.append((fx, abs(float((180 + np.degrees(ph) + 180) % 360 - 180))))
    # phase crossings of -180 deg (Im changes sign with Re<0)
    gm_up, gm_low = None, None
    k = np.where((L.imag[:-1] * L.imag[1:] < 0) & (L.real[:-1] < 0) & (L.real[1:] < 0))[0]
    for j in k:
        t = L.imag[j] / (L.imag[j] - L.imag[j + 1])
        m = float(abs(L[j] + t * (L[j + 1] - L[j])))
        if m < 1:
            gm_up = -20 * np.log10(m) if gm_up is None else min(gm_up, -20 * np.log10(m))
        else:
            gm_low = 20 * np.log10(m) if gm_low is None else min(gm_low, 20 * np.log10(m))
    return dict(S_max=float(aS[i]), S_max_freq_hz=float(f[i]), T_max=float(np.max(np.abs(L * S))),
                fc_hz=cross[0][0] if cross else None, fc_last_hz=cross[-1][0] if cross else None, pm_deg=cross[0][1] if cross else None,
                crossings_hz=[x[0] for x in cross], pm_all_deg=[x[1] for x in cross],
                pm_min_deg=min((x[1] for x in cross), default=None),
                gm_up_db=gm_up, gm_low_db=gm_low, nyquist_stable=nyquist_stable(L))


def nyquist_stable(L):
    """Winding check for a type-2 loop with no open-loop RHP poles: unwrapped phase of 1+L, started
    at -pi (|L|>>1, phase -180 deg as w->0) must end at 0. Z = -2m closed-loop RHP poles, m = round(end/2pi)."""
    psi = np.unwrap(np.angle(1 + L))
    psi = psi + 2 * np.pi * np.round((-np.pi - psi[0]) / (2 * np.pi))
    return bool(round(psi[-1] / (2 * np.pi)) == 0)


# ------------------------------------------------------------------ plants
def load_frf():
    f, G, periods, src_ts = base.measured_response()
    keep = (f >= F_BAND[0]) & (f <= F_BAND[1])
    return f[keep], G[keep], periods[:, keep], src_ts


def model_frf(f, extra_delay=2, p=None):
    """Identified 4-state model, 8 kHz ZOH, 'extra_delay' samples (the time-domain setting)."""
    a, b = base.plant_matrices(p or base.NOMINAL)
    z = np.exp(2j * np.pi * f * TS)
    g = np.linalg.solve(z[:, None, None] * np.eye(4) - a, np.broadcast_to(b, (len(f), 4, 1)))[:, 2, 0]
    return g / z**extra_delay


def sos_response(sos, f):
    _, h = signal.sosfreqz(np.asarray(sos), worN=2 * np.pi * f * TS)
    return h


# ------------------------------------------------------------------ time-domain closed loop
class Controller:
    """Time-domain Fig. 8.9 controller, same signal flow as ControllerAlgorithm::Step with make_design()
    sections: x = LP-block[e]; u = kp*Lead[x] + kp*Lead[Vi[HIGS_i[x]]] (I post-section includes the lead)."""

    def __init__(self, d, kp, linear_h=False):
        """linear_h=True replaces every HIGS by its linear H (bilinear), which must reproduce the linear controller."""
        c = corners(d)
        wl = c["wl"]
        self.kp = kp

        def element(wc):
            if not wc:
                return None
            return Biquad(base.section([wc], [1, wc])) if linear_h else Higs(wc * TS / SQ)
        self.hl = element(c["wc_lp"])
        if c["wc_lp"]:
            lp = base.section([wl**2 / c["wc_lp"], wl**2], [1, np.sqrt(2) * wl, wl**2])
        else:
            lp = base.section([wl**2], [1, np.sqrt(2) * wl, wl**2])
        self.lp = Biquad(lp)
        lead = base.section([c["wp"] / c["wz"], c["wp"]], [1, c["wp"]])
        self.lead, self.lead_i = Biquad(lead), Biquad(lead)
        self.hi = element(c["wc_i"])
        if c["wc_i"]:
            ib = base.section([c["wi"] / c["wc_i"], c["wi"]], [1, 0])
        else:
            ib = base.section([c["wi"]], [1, 0])
        self.ib = Biquad(ib)

    def step(self, e):
        a = self.hl.step(e) if self.hl else e
        x = self.kp * self.lp.step(a)
        h = self.hi.step(x) if self.hi else x
        return self.lead.step(x) + self.lead_i.step(self.ib.step(h))


def discrete_plant(p=None):
    p = p or base.NOMINAL
    jm, jl, bm, bl, k, c, kt = (p[x] for x in base.NOMINAL)
    a = np.array([[0, 1, 0, 0], [-k / jm, -(bm + c) / jm, k / jm, c / jm],
                  [0, 0, 0, 1], [k / jl, c / jl, -k / jl, -(bl + c) / jl]])
    bcols = np.array([[0, 0], [kt / jm, 0], [0, 0], [0, 1 / jl]])       # motor current, load torque (Kt=1 units)
    m = np.zeros((6, 6)); m[:4, :4] = a; m[:4, 4:] = bcols
    e = linalg.expm(m * TS)
    return e[:4, :4], e[:4, 4], e[:4, 5]


def simulate(ctrl, reference, load_torque=None, *, delay=2, quantized=False, current_limit=CURRENT_LIMIT, angle_counts=8388608):
    ad, bm_, bd_ = (x.tolist() for x in discrete_plant())
    n = len(reference)
    out = np.zeros((n, 6))     # theta_m, w_m, theta_l, w_l, command, applied
    x = [0.0] * 4
    queue = [0.0] * (delay + 1)
    cq = 0.0016 if quantized else 0.0
    eq = 2 * np.pi / angle_counts if quantized else 0.0
    clipped = 0
    r_list = reference.tolist()
    d_list = (load_torque if load_torque is not None else np.zeros(n)).tolist()
    for k in range(n):
        y = x[2]
        if eq:
            y = np.floor(y / eq + 0.5) * eq
        cmd = ctrl.step(r_list[k] - y)
        app = max(-current_limit, min(current_limit, cmd))
        clipped += abs(cmd) > current_limit
        if cq:
            app = np.floor(app / cq + 0.5) * cq
        queue[k % (delay + 1)] = app
        dl = queue[(k - delay) % (delay + 1)] if k >= delay else 0.0
        out[k] = (x[0], x[1], x[2], x[3], cmd, dl)
        dk = d_list[k]
        x = [ad[i][0] * x[0] + ad[i][1] * x[1] + ad[i][2] * x[2] + ad[i][3] * x[3] + bm_[i] * dl + bd_[i] * dk
             for i in range(4)]
        if abs(x[0]) > 1e3:
            out[k + 1:] = np.nan
            return out, int(clipped), True
    return out, int(clipped), False


def band_rms(x, lo, hi):
    f = np.fft.rfftfreq(len(x), TS)
    s = np.fft.rfft(x) / len(x)
    m = (f >= lo) & (f <= hi)
    return float(np.sqrt(2 * np.sum(np.abs(s[m]) ** 2)))


def reference_windows(ref):
    """round-trip profile: settle 0.4, move 0.1 (0.4-0.5), dwell 0.2, move 0.1 (0.7-0.8), settle 0.4"""
    t = np.arange(len(ref)) * TS
    w1 = (t >= 0.5) & (t < 0.7)          # first 0.2 s after move 1 (whole dwell)
    w2 = (t >= 0.8) & (t < 1.0)          # first 0.2 s after move 2
    return w1 | w2


def td_metrics(make_ctrl, *, quantized=False, disturbance_record=1.6, angle_counts=8388608):
    ref = base.reference_profile()
    ctrl = make_ctrl()
    out, clipped, diverged = simulate(ctrl, ref, quantized=quantized, angle_counts=angle_counts)
    e = ref - out[:, 2]
    win = reference_windows(ref)
    twist = out[:, 0] - out[:, 2]
    rec = dict(diverged=diverged, clipped_samples=clipped)
    if diverged:
        return rec, None
    rec.update(move_rms_mrad=1e3 * float(np.sqrt(np.mean(e**2))), peak_error_mrad=1e3 * float(np.max(abs(e))),
               settle_rms_urad=1e6 * float(np.sqrt(np.mean(e[win]**2))),
               peak_current_ma=1e3 * float(np.max(abs(out[:, 4]))),
               twist_200_400hz_rms_urad=1e6 * band_rms(twist, *TWIST_BAND_HZ),
               tail_rms_urad=1e6 * float(np.sqrt(np.mean(e[-TAIL_N():]**2))))
    # step load-torque disturbance (0.005 in Kt=1 current units) at t=0.1 s on the load, 1.6 s record
    n = round(disturbance_record / TS)
    t = np.arange(n) * TS
    dist = 0.005 * (t >= 0.1)
    ctrl = make_ctrl()
    out2, clip2, div2 = simulate(ctrl, np.zeros(n), dist, quantized=quantized, angle_counts=angle_counts)
    rec["dist_diverged"] = div2
    traces = dict(t=np.arange(len(ref)) * TS, e=e, t2=t, e2=None)
    if not div2:
        e2 = -out2[:, 2]
        traces["e2"] = e2
        rec.update(dist_iae_mrad_s=1e3 * float(np.sum(abs(e2)) * TS), dist_peak_mrad=1e3 * float(np.max(abs(e2))),
                   dist_clipped=clip2, dist_tail_rms_urad=1e6 * float(np.sqrt(np.mean(e2[-TAIL_N():]**2))))
    return rec, traces


# ------------------------------------------------------------------ search
SEARCH = dict(
    fc=np.geomspace(4., 150., 44), kp_scale=(0.7, 0.85, 1.0, 1.2, 1.4), r_i=(1.5, 2., 3., 4., 6.),
    lead_ratio=(2., 3., 4.), lp_hz=(60., 80., 100., 150., 200., 300.),
    wc_lp_ratio=(0.1, 0.25, 0.5, 1., 2., 4.), wc_i_ratio=(0.05, 0.1, 0.25, 0.5, 1., 2.))
# Hard bounds of the local refinement (wider than the grid except lp_hz, which stays in the requested 60-300 Hz).
BOUNDS = dict(fc=(4., 200.), kp_scale=(0.4, 2.5), r_i=(1.5, 12.), lead_ratio=(1.5, 5.), lp_hz=(60., 300.),
              wc_lp_ratio=(0.03, 8.), wc_i_ratio=(0.01, 4.))


def evaluate(fm, d):
    kp = d["kp_scale"] * fm.kp_for_unity(d)
    return kp, float(np.max(np.abs(1 / (1 + fm.loop(d, kp)))))


def df_feasible(fm, d):
    """Describing-function robustness gate: max|S| <= limit and Nyquist-stable. Returns (kp, metrics) or None."""
    kp, smax = evaluate(fm, d)
    if smax > S_LIMIT:
        return None
    L = fm.loop(d, kp)
    if not nyquist_stable(L):
        return None
    m = loop_metrics(fm.f, L)
    return (kp, m) if m["fc_hz"] is not None else None


def td_screen(d, kp):
    """Nonlinear time-domain gate on the identified model (8 kHz, 2-sample delay): no divergence, no current
    clipping (|command| <= 0.08 A) in the round trip or the load step, no limit cycle (last 0.2 s error RMS <= 50 urad)."""
    rec, _ = td_metrics(lambda: Controller(d, kp), disturbance_record=1.2)
    ok = (not rec["diverged"] and rec["clipped_samples"] == 0 and rec["tail_rms_urad"] <= TAIL_LIMIT_URAD
          and not rec.get("dist_diverged", True) and rec.get("dist_clipped", 1) == 0
          and rec["dist_tail_rms_urad"] <= TAIL_LIMIT_URAD)
    return ok, rec


def search_mode(fm_coarse, fm_full, mode, grid=SEARCH, per_shape=4, log=print):
    """Grid search on a decimated frequency grid. For every shape (r_i, lead ratio, LP corner, HIGS corner
    ratios) the `per_shape` best (fc, kp_scale) are kept, re-checked on the full measured grid, and returned
    sorted by crossover (best first)."""
    names = ["fc", "kp_scale", "r_i", "lead_ratio", "lp_hz"]
    axes = [grid[k] for k in names]
    if mode in ("LP", "both"):
        names.append("wc_lp_ratio"); axes.append(grid["wc_lp_ratio"])
    if mode in ("I", "both"):
        names.append("wc_i_ratio"); axes.append(grid["wc_i_ratio"])
    shapes, count, t0 = {}, 0, time.time()
    for vals in itertools.product(*axes):
        d = design_params(mode, **dict(zip(names, vals)))
        count += 1
        r = df_feasible(fm_coarse, d)
        if r is None:
            continue
        key = tuple(vals[2:])
        lst = shapes.setdefault(key, [])
        item = (r[1]["fc_hz"], -r[1]["S_max"], d)
        lst.append(item)
        lst.sort(key=lambda x: x[:2], reverse=True)
        del lst[per_shape:]
    cands = []
    for lst in shapes.values():
        for _, _, d in lst:
            r = df_feasible(fm_full, d)
            if r is not None:
                cands.append((r[1]["fc_hz"], -r[1]["S_max"], d, r[0]))
    cands.sort(key=lambda x: x[:2], reverse=True)
    log(f"  [{mode}] {count} grid evaluations, {len(shapes)} feasible shapes, {len(cands)} candidates, "
        f"{time.time() - t0:.0f}s; DF-only best fc {cands[0][0]:.2f} Hz")
    return cands


def refine(fm, d, kp, m, accept=None):
    """Pattern search around a design on all continuous parameters (bounded by the search ranges).
    `accept(d, kp)` is an additional gate (default none)."""
    keys = [k for k in ("fc", "kp_scale", "r_i", "lead_ratio", "lp_hz", "wc_lp_ratio", "wc_i_ratio") if d[k] is not None]
    lo = {k: BOUNDS[k][0] for k in keys}
    hi = {k: BOUNDS[k][1] for k in keys}
    for step in (0.2, 0.1, 0.05, 0.025, 0.0125):
        improved = True
        while improved:
            improved = False
            for k in keys:
                for s in (1 + step, 1 / (1 + step)):
                    q = dict(d)
                    q[k] = float(np.clip(d[k] * s, lo[k], hi[k]))
                    if q[k] == d[k]:
                        continue
                    r = df_feasible(fm, q)
                    if r is None or (r[1]["fc_hz"], -r[1]["S_max"]) <= (m["fc_hz"], -m["S_max"]):
                        continue
                    if accept is not None and not accept(q, r[0]):
                        continue
                    d, kp, m, improved = q, r[0], r[1], True
    return d, kp, m


def edge_flags(d):
    """List parameters at the edge of the refinement bounds."""
    flags = []
    for k, (lo, hi) in BOUNDS.items():
        v = d.get(k)
        if v is None:
            continue
        if v <= lo * 1.001:
            flags.append(f"{k} at lower edge ({lo})")
        if v >= hi * 0.999:
            flags.append(f"{k} at upper edge ({hi})")
    return flags


# ------------------------------------------------------------------ numeric DF of the full controller
def controller_df_numeric(d, kp, f_eval, n_grid=90):
    """First harmonic of the whole nonlinear controller (sine in, controller out) on integer samples/period;
    interpolated to f_eval. Captures the cascade of two HIGS blocks (product of DFs is only approximate)."""
    n_list = np.unique(np.round(np.geomspace(4, FS / max(F_BAND[0], 1.0), n_grid)).astype(int))
    vals = []
    for n in n_list:
        ctrl = Controller(d, kp)
        periods, keep = 6, 3
        k = np.arange(periods * n)
        th = 2 * np.pi * k / n + 0.3
        u = 1e-3 * np.sin(th)
        y = np.array([ctrl.step(float(v)) for v in u])
        sl = slice((periods - keep) * n, periods * n)
        thk = th[sl] % (2 * np.pi)
        b = 2 / (keep * n) * np.sum(y[sl] * np.sin(thk)) / 1e-3
        a = 2 / (keep * n) * np.sum(y[sl] * np.cos(thk)) / 1e-3
        vals.append(b + 1j * a)
    fg = FS / n_list
    order = np.argsort(fg)
    fg, vals = fg[order], np.array(vals)[order]
    re = np.interp(np.log(f_eval), np.log(fg), vals.real)
    im = np.interp(np.log(f_eval), np.log(fg), vals.imag)
    return re + 1j * im, fg, vals


# ------------------------------------------------------------------ analysis helpers
def jsonable(x):
    if isinstance(x, dict):
        return {k: jsonable(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [jsonable(v) for v in x]
    if isinstance(x, np.ndarray):
        return jsonable(x.tolist())
    if isinstance(x, (np.floating, float)):
        return None if not np.isfinite(x) else float(x)
    if isinstance(x, np.integer):
        return int(x)
    if isinstance(x, np.bool_):
        return bool(x)
    return x


def slim(m):
    keep = ("S_max", "S_max_freq_hz", "T_max", "fc_hz", "fc_last_hz", "pm_deg", "pm_min_deg", "crossings_hz", "gm_up_db",
            "gm_low_db", "nyquist_stable")
    return {k: m[k] for k in keep}


class Context:
    def __init__(self, extra_delay=EXTRA_DELAY_SAMPLES):
        self.extra_delay = extra_delay
        self.f, self.G, self.periods, self.src_ts = load_frf()
        data = np.load(ROOT / "simulations/data/measured_frf.npz")
        keep = (data["freq_hz"] >= F_BAND[0]) & (data["freq_hz"] <= F_BAND[1])
        self.coh = data["coherence_load"][keep]
        self.sub = slice(None, None, 3)
        self.fm_search = FreqModel(self.f[self.sub], self.G[self.sub], extra_delay=extra_delay)
        self.fm = FreqModel(self.f, self.G, extra_delay=extra_delay)
        self.fm0 = FreqModel(self.f, self.G, extra_delay=0)
        self.fm2 = FreqModel(self.f, self.G, extra_delay=2)
        self.fm6 = FreqModel(self.f, self.G, extra_delay=6)
        self.fm_analytic = FreqModel(self.f, self.G, analytic_df=True)
        self.fm_model = FreqModel(self.f, model_frf(self.f, 2), extra_delay=0)

    def analyze(self, d, kp, cascade=True):
        fm = self.fm
        L = fm.loop(d, kp)
        m = loop_metrics(self.f, L)
        out = slim(m)
        out["tuning"] = tuning_fields(d, kp)
        out["S_max_extra_delay0"] = float(np.max(abs(1 / (1 + self.fm0.loop(d, kp)))))
        out["S_max_extra_delay2"] = float(np.max(abs(1 / (1 + self.fm2.loop(d, kp)))))
        out["S_max_extra_delay6"] = float(np.max(abs(1 / (1 + self.fm6.loop(d, kp)))))
        out.update(self.old_gate(d, kp))
        ctrl = fm.controller(d)
        out["S_max_worst_period"] = float(max(
            np.max(abs(1 / (1 + kp * ctrl * g * np.exp(-1j * fm.w * TS * self.extra_delay)))) for g in self.periods))
        out["coherence_at_S_max"] = float(np.interp(m["S_max_freq_hz"], self.f, self.coh))
        out["S_max_analytic_df"] = float(np.max(abs(1 / (1 + self.fm_analytic.loop(d, kp)))))
        mm = loop_metrics(self.f, self.fm_model.loop(d, kp))
        out["model_S_max"] = mm["S_max"]
        out["model_S_max_freq_hz"] = mm["S_max_freq_hz"]
        out["model_nyquist_stable"] = mm["nyquist_stable"]
        out["model_fc_hz"] = mm["fc_hz"]
        out["model_pm_deg"] = mm["pm_deg"]
        if cascade and d["mode"] != "linear":
            cn, _, _ = controller_df_numeric(d, kp, self.f)
            cn = np.where(self.f <= FS / 4, cn, kp * ctrl)
            Lc = cn * fm.G
            out["S_max_cascade_df"] = float(np.max(abs(1 / (1 + Lc))))
            out["cascade_vs_product_max_rel_diff_below_500hz"] = float(np.max(
                (abs(cn - kp * ctrl) / abs(kp * ctrl))[self.f <= 500]))
            out["cascade_nyquist_stable"] = nyquist_stable(Lc)
        return out, L

    def old_gate(self, d, kp):
        """The gate the 8 Hz design passed in higs_two_inertia.main(): max|S| over 96 perturbed identified models
        (Jm, Jl, K +-20 %, C and viscous x0.5/1.5, delay 1/4/8 samples) and over the 8 measured periods with 6 extra
        samples (no 1-sample delay added, repo convention). DF controller in both."""
        ctrl = kp * self.fm.controller(d)
        z = np.exp(1j * self.fm.w * TS)
        n = base.NOMINAL
        worst, stable = 0.0, True
        for jm, jl, k, c, b in itertools.product([.8, 1.2], [.8, 1.2], [.8, 1.2], [.5, 1.5], [.5, 1.5]):
            p = n | dict(jm=n["jm"] * jm, jl=n["jl"] * jl, stiffness=n["stiffness"] * k, damping=n["damping"] * c,
                         bm=n["bm"] * b, bl=n["bl"] * b)
            g = model_frf(self.f, 0, p)
            for delay in (1, 4, 8):
                L = ctrl * g / z**delay
                worst = max(worst, float(np.max(abs(1 / (1 + L)))))
                stable = stable and nyquist_stable(L)
        pw = float(max(np.max(abs(1 / (1 + ctrl * g * np.exp(-1j * self.fm.w * TS * 6)))) for g in self.periods))
        return dict(old_gate_S_max_96_models=worst, old_gate_S_max_worst_period_6_extra=pw,
                    old_gate_models_nyquist_stable=stable, old_gate_pass=bool(worst <= S_LIMIT and pw <= S_LIMIT and stable))

    def reference_designs(self):
        """8 Hz designs of the repo (tuning in higs_design.json, kp from the measured gain at 8 Hz):
        linear, previous single LP-HIGS (corner 20 Hz, from the previous commit), current repo default (LP-HIGS 100 Hz + I-HIGS 2 Hz)."""
        tuning = json.loads((ROOT / "simulations/higs_design.json").read_text())["tuning"]
        fc = tuning["measured_crossover_target_hz"]
        common = dict(fc=fc, kp_scale=1.0, r_i=fc / tuning["integral_hz"], lead_ratio=tuning["lead_pole_hz"] / fc,
                      lp_hz=tuning["lowpass_hz"])
        designs = {
            "ref8_linear": dict(mode="linear", wc_lp_ratio=None, wc_i_ratio=None, **common),
            "ref8_LP_HIGS_20Hz_previous": dict(mode="LP", wc_lp_ratio=20. / fc, wc_i_ratio=None, **common),
            "ref8_both_HIGS_current": dict(mode="both", wc_lp_ratio=tuning["higs_lp_corner_hz"] / fc,
                                           wc_i_ratio=tuning["higs_i_corner_hz"] / fc, **common)}
        return tuning, designs


def run_scenario(name, extra_delay, refs, kp_ref, max_screens, log):
    ctx = Context(extra_delay)
    log(f"scenario {name}: extra delay {extra_delay} samples")
    loops = {}
    ref_res = {}
    for rn, d in refs.items():
        ref_res[rn], loops[rn] = ctx.analyze(d, kp_ref)
        ref_res[rn].update(params=d, kp=kp_ref)
    designs = {}     # name -> (d, kp)
    ana = {"df_only": {}, "screened": {}}

    def cascade_ok(d, kp):
        if d["mode"] == "linear":
            return True
        cn, _, _ = controller_df_numeric(d, kp, ctx.f)
        Lc = np.where(ctx.f <= FS / 4, cn, kp * ctx.fm.controller(d)) * ctx.fm.G
        return bool(np.max(abs(1 / (1 + Lc))) <= S_LIMIT and nyquist_stable(Lc))

    def record(group, mode, d, kp, extra=None):
        dname = ("df_" if group == "df_only" else "scr_") + mode
        a, loops[dname] = ctx.analyze(d, kp)
        a.update(params=d, kp=kp, grid_edge_flags=edge_flags(d),
                 corners_hz={k: (v / (2 * np.pi) if v else None) for k, v in corners(d).items()}, **(extra or {}))
        ana[group][mode] = a
        designs[dname] = (d, kp)

    for mode in MODES:
        log("search", mode)
        cands = search_mode(ctx.fm_search, ctx.fm, mode, log=log)
        _, _, d, kp = cands[0]
        m = loop_metrics(ctx.f, ctx.fm.loop(d, kp))
        d, kp, m = refine(ctx.fm, d, kp, m)
        record("df_only", mode, d, kp, dict(grid_fc_hz=cands[0][0]))
        log(f"  {mode} DF-only: fc {m['fc_hz']:.2f} Hz (grid {cands[0][0]:.2f}), Smax {m['S_max']:.3f}")
        found, screens = None, 0
        for fc_c, _, dc, kpc in cands[:max_screens]:
            screens += 1
            ok, _ = td_screen(dc, kpc)
            if ok and cascade_ok(dc, kpc):
                found = (dc, kpc)
                break
        if found is None:
            log(f"  {mode}: no candidate passed the time-domain gate in {screens} screens")
            continue
        d, kp = found
        m = loop_metrics(ctx.f, ctx.fm.loop(d, kp))
        fc0 = m["fc_hz"]
        d1, kp1, m1 = refine(ctx.fm, d, kp, m, accept=lambda q, kq: td_screen(q, kq)[0])
        if mode != "linear" and not cascade_ok(d1, kp1):
            d1, kp1, m1 = d, kp, m
        record("screened", mode, d1, kp1, dict(screens_until_first_pass=screens, fc_before_refine_hz=fc0))
        log(f"  {mode} screened: first pass after {screens} screens at fc {fc0:.2f}; refined {m1['fc_hz']:.2f} Hz, Smax {m1['S_max']:.3f}")

    # matched: screened linear C* with HIGS switched on, corners = those of each mode's screened design
    dl, kl = designs["scr_linear"]
    matched = {}
    for mode in ("I", "LP", "both"):
        if f"scr_{mode}" not in designs:
            continue
        dm = dict(dl, mode=mode)
        src = designs[f"scr_{mode}"][0]
        if mode in ("LP", "both"):
            dm["wc_lp_ratio"] = src["wc_lp_ratio"] * src["fc"] / dl["fc"]
        if mode in ("I", "both"):
            dm["wc_i_ratio"] = src["wc_i_ratio"] * src["fc"] / dl["fc"]
        a, loops[f"matched_{mode}"] = ctx.analyze(dm, kl)
        a.update(params=dm, kp=kl, corners_hz={k: (v / (2 * np.pi) if v else None) for k, v in corners(dm).items()})
        matched[mode] = a
        designs[f"matched_{mode}"] = (dm, kl)

    td, traces = {}, {}
    for dname, (d, kp) in designs.items():
        td[dname], traces[dname] = td_metrics(lambda d=d, kp=kp: Controller(d, kp))
    for rn, d in refs.items():
        td[rn], traces[rn] = td_metrics(lambda d=d: Controller(d, kp_ref))
    for dname, v in td.items():
        log("td", dname, {k: (round(x, 3) if isinstance(x, float) else x) for k, x in v.items()})
    out = dict(extra_delay_samples=extra_delay, reference_designs=ref_res, best_designs=ana, matched_designs=matched,
               time_domain=td)
    return out, (ctx, loops, td, traces)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--output", type=Path, default=OUT_DIR)
    ap.add_argument("--max-screens", type=int, default=3000)
    ap.add_argument("--gate-sweep", action="store_true",
                    help="max crossover per mode vs gate strictness G0..G5 (+ ablations) -> fig89_gate_sweep.json/.png; "
                         "needs results/fig89_robustness.json (G0 optima)")
    ap.add_argument("--followup", choices=("q1", "q2", "all"),
                    help="q1: max linear crossover with the old design shape under G5; q2: error-optimal designs (G5, G1, quantization); "
                         "-> fig89_followup.json (needs fig89_gate_sweep.json; fig89_robustness.json for the matched corners)")
    ap.add_argument("--no-ablations", action="store_true", help="with --gate-sweep: skip the single-element ablation gates")
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    t0 = time.time()

    def log(*a):
        print(f"[{time.time() - t0:5.0f}s]", *a, flush=True)

    if args.gate_sweep:
        gate_sweep(args, log)
        return
    if args.followup:
        followup(args, log)
        return

    ctx = Context()
    res = dict(setup=dict(
        sample_time_s=TS, S_limit=S_LIMIT, S_limit_db=20 * np.log10(S_LIMIT),
        band_hz=list(F_BAND), frf_points=len(ctx.f), source_ts_s=ctx.src_ts, W="W = 1 (no pre-filter)", Post="identity",
        structure="x=LP[e]; u=kp*Lead[x]+kp*Lead[Vi[HIGS_i[x]]] i.e. C*=kp*Clp*Lead*(1+wi/s) as in ControllerAlgorithm/make_design; "
                  "HIGS kh=1, wc=wh*sqrt(1+16/pi^2); bilinear digital blocks",
        loop="L = kp*C_DF(z=exp(jwTs)) * G8 * exp(-j w Ts*extra); G8 = measured_response() (16 kHz hold -> 8 kHz hold)",
        scenarios="nominal_delay1: extra = 1 sample computational delay (requested). stress_delay6: extra = 6 samples, the "
                  "delay stress of the repo's measured_linear_metrics (old_gate_* fields give the repo's full gate)",
        td_gate=f"screened designs (this script's addition): no divergence, no clipping at 0.08 A, last-0.2 s error RMS <= {TAIL_LIMIT_URAD} urad "
                "(round trip and load step) and, for HIGS modes, max|S| <= 2 with the numeric DF of the whole cascade",
        search_grid={k: list(map(float, v)) for k, v in SEARCH.items()},
        refine_bounds={k: list(v) for k, v in BOUNDS.items()}))

    log("DF check")
    dfc = df_check()
    res["df_check"] = dfc

    sm = json.loads((ROOT / "simulations/results/summary.json").read_text())
    case = next((x for x in sm["cases"] if x["name"] == "no quantization"), None)
    tuning, refs = ctx.reference_designs()
    kp_ref = tuning["kp"]
    ref = base.reference_profile()
    # Port validation. summary.json (if still the pre-merge one) holds the C++ results of the previous single
    # LP-HIGS (20 Hz corner in front of V*PI*lead); the same design in the Fig. 8.9 flow must reproduce them.
    val = {}
    for key, name in (("linear", "ref8_linear"), ("higs", "ref8_LP_HIGS_20Hz_previous")):
        out, _, _ = simulate(Controller(refs[name], kp_ref), ref, delay=2)
        e = ref - out[:, 2]
        cpp = (case or {}).get(key)
        val[key] = dict(rms_rad=float(np.sqrt(np.mean(e * e))), rms_rad_cpp=cpp and cpp["rms_rad"],
                        peak_current_a=float(np.max(abs(out[:, 4]))), peak_current_a_cpp=cpp and cpp["peak_feedback_a"],
                        twist_250_380_rms=band_rms(out[:, 0] - out[:, 2], 250, 380),
                        twist_250_380_rms_cpp=cpp and cpp["resonance_twist_rms_rad"],
                        note=None if cpp else "reference absent in summary.json (regenerated by the two-HIGS host?)")
    baseline, _, _ = base.make_design()
    c_repo = sos_response(baseline["linear_sos"], ctx.f)
    c_mine = kp_ref * ctx.fm.controller(refs["ref8_linear"])
    val["kp_repo_vs_tuning"] = [float(baseline["linear_sos"][0, 0]), kp_ref]
    val["linear_blocks_vs_repo_sos_max_rel_diff"] = float(np.max(abs(c_mine / c_repo - 1)))
    k = ctx.f <= 1000
    val["measured_S_max_1_1000hz_no_extra_delay"] = float(np.max(abs(1 / (1 + (c_repo * ctx.G)[k]))))
    val["measured_S_max_cpp_summary"] = sm.get("measured_linear_reference", {}).get("peak_sensitivity")
    # repo gate numbers of the 8 Hz design: summary.json bandwidth_comparison (96 models / worst period + 6 samples)
    bw8 = next((x for x in sm.get("bandwidth_comparison", []) if x["crossover_hz"] == 8.0), None)
    val["old_gate_8hz_mine"] = ctx.old_gate(refs["ref8_linear"], kp_ref)
    val["old_gate_8hz_summary"] = bw8
    # HIGS replaced by its linear H must give back the linear controller; checks V*H = C* of both blocks
    # (including the lead in the I path) in the time domain.
    dd = refs["ref8_both_HIGS_current"]
    out_l, _, _ = simulate(Controller(refs["ref8_linear"], kp_ref), ref, delay=2)
    out_h, _, _ = simulate(Controller(dd, kp_ref, linear_h=True), ref, delay=2)
    val["both_blocks_linear_H_vs_linear_max_abs_diff_rad"] = float(np.max(abs(out_l[:, 2] - out_h[:, 2])))
    cal = []
    for gain in (1, 3, 6, 10, 30):
        dl_ = dict(linear_sos=np.array(baseline["linear_sos"]), sample_time_s=TS)
        dl_["linear_sos"][0, :3] *= gain
        lm = base.linear_metrics(dl_)
        cal.append(dict(gain=gain, eigen_stable=bool(lm["stable"]), spectral_radius=lm["spectral_radius"],
                        winding_stable=nyquist_stable(lm["loop"]), S_max=lm["peak_sensitivity"]))
    val["winding_vs_eigenvalue_calibration"] = cal
    res["port_validation"] = val
    log("port validation", val["linear"], val["higs"], val["linear_blocks_vs_repo_sos_max_rel_diff"],
        val["both_blocks_linear_H_vs_linear_max_abs_diff_rad"])

    res["time_domain_setup"] = dict(
        plant="identified 4-state two-inertia model, exact ZOH at 8 kHz, 2-sample delay, current clamp 0.08 A, "
              "no quantization, no feedforward (ffValue = 0 as in higs_host.cpp)",
        reference="higs_two_inertia.reference_profile(): 0.1 rad round trip, 0.1 s min-jerk moves, 0.2 s dwell",
        settle_window="0.2 s after the end of each move (0.5-0.7 s and 0.8-1.0 s)",
        disturbance="0.005 (Kt=1 current units) step on the load inertia at t=0.1 s, 1.6 s record, r=0; IAE of load-angle error",
        twist_band_hz=list(TWIST_BAND_HZ))
    res["scenarios"] = {}
    for sname, delay, suffix in (("nominal_delay1", EXTRA_DELAY_SAMPLES, ""), ("stress_delay6", 6, "_stress6")):
        out, plot_data = run_scenario(sname, delay, refs, kp_ref, args.max_screens, log)
        res["scenarios"][sname] = out
        c, loops, td, traces = plot_data
        plot_all(args.output, c, loops, td, traces, suffix, delay)
    plot_df(args.output, dfc)
    (args.output / "fig89_robustness.json").write_text(json.dumps(jsonable(res), indent=1, allow_nan=False) + "\n")
    log("saved", args.output)


# ------------------------------------------------------------------ gate-strictness sweep (--gate-sweep)
# Each gate is a set of plants P_i(jw) on which max|S_i| <= 2 and Nyquist stability must hold with the DF controller.
#   nominal  : measured FRF (G8) + 1 extra sample (G0, always included; the crossover fc is measured on it)
#   period1  : the 8 measured periods, +1 extra sample
#   period6  : the 8 measured periods, +6 extra samples (repo convention, no 1-sample delay added)
#   models   : identified two-inertia model, Jm/Jl/K corners at +-spread (cb: also C and viscous x0.5/1.5), delays in samples
#              (delay 2 = the nominal time-domain setting of the identified model)
GATE_SPECS = {
    "G0": dict(label="nominal measured FRF"),
    "G1": dict(label="G0 + worst measured period (nominal delay)", period1=True),
    "G2": dict(label="G1 + Jm/Jl/K +-10 %, delay 2", period1=True, models=[dict(spread=.1, cb=False, delays=(2,))]),
    "G3": dict(label="G1 + Jm/Jl/K +-20 %, delay 2", period1=True, models=[dict(spread=.2, cb=False, delays=(2,))]),
    "G4": dict(label="G3 with delay 1/2/4", period1=True, models=[dict(spread=.2, cb=False, delays=(1, 2, 4))]),
    "G5": dict(label="repo gate: 96 models x delay 1/4/8 + worst period +6 (plus G4)", period1=True, period6=True,
               models=[dict(spread=.2, cb=False, delays=(1, 2, 4)), dict(spread=.2, cb=True, delays=(1, 4, 8))]),
    # single-element ablations, each added to G0 only (cost ranking of the gate elements)
    "X_period6": dict(label="G0 + worst period +6 samples only", period6=True),
    "X_params20": dict(label="G0 + Jm/Jl/K +-20 % at delay 2 only", models=[dict(spread=.2, cb=False, delays=(2,))]),
    "X_delay148": dict(label="G0 + nominal model, delay 1/4/8 only", models=[dict(spread=0., cb=False, delays=(1, 4, 8))]),
    "X_cb": dict(label="G0 + C and viscous x0.5/1.5 (Jm,Jl,K nominal), delay 2 only",
                 models=[dict(spread=0., cb=True, delays=(2,))]),
}
MAIN_GATES = ("G0", "G1", "G2", "G3", "G4", "G5")
SWEEP_BOUNDS = dict(BOUNDS, fc=(1., 200.))
SIGMA_PERTURB, N_PERTURB, N_REFINE_STARTS = 0.3, 300, 2


def model_set(f, spec):
    """Plants (rows) of one `models` entry: Jm/Jl/K corners (and C, viscous corners) x delays."""
    n = base.NOMINAL
    z = np.exp(2j * np.pi * f * TS)
    lo, hi = 1 - spec["spread"], 1 + spec["spread"]
    corner = [lo, hi] if spec["spread"] > 0 else [1.]
    cb = [.5, 1.5] if spec["cb"] else [1.]
    rows = []
    for jm, jl, k, c, b in itertools.product(corner, corner, corner, cb, cb):
        p = n | dict(jm=n["jm"] * jm, jl=n["jl"] * jl, stiffness=n["stiffness"] * k, damping=n["damping"] * c,
                     bm=n["bm"] * b, bl=n["bl"] * b)
        g = model_frf(f, 0, p)
        rows += [g / z**d for d in spec["delays"]]
    return rows


def nyquist_stable_many(L):
    """Vectorised nyquist_stable() over the rows of L."""
    psi = np.unwrap(np.angle(1 + L), axis=1)
    psi = psi + 2 * np.pi * np.round((-np.pi - psi[:, 0]) / (2 * np.pi))[:, None]
    return np.round(psi[:, -1] / (2 * np.pi)) == 0


def first_crossover(f, L):
    mag = np.abs(L)
    j = np.where((mag[:-1] > 1) & (mag[1:] <= 1))[0]
    if len(j) == 0:
        return None
    j = j[0]
    t = np.log(mag[j]) / (np.log(mag[j]) - np.log(mag[j + 1]))
    return float(np.exp(np.log(f[j]) + t * (np.log(f[j + 1]) - np.log(f[j]))))


class GateEval:
    """Gate = nominal measured loop (row 0) + extra plants. All evaluation uses the DF controller on grid `idx`."""

    def __init__(self, ctx, gate, idx):
        spec = GATE_SPECS[gate]
        self.gate, self.f = gate, ctx.f[idx]
        self.fm = FreqModel(self.f, ctx.G[idx], extra_delay=1)
        w, groups = 2 * np.pi * self.f, {"nominal": [self.fm.G]}
        per = ctx.periods[:, idx]
        if spec.get("period1"):
            groups["period_plus1"] = list(per * np.exp(-1j * w * TS))
        if spec.get("period6"):
            groups["period_plus6"] = list(per * np.exp(-1j * w * TS * 6))
        for i, ms in enumerate(spec.get("models", [])):
            groups[f"models{i}_spread{ms['spread']:g}_cb{int(ms['cb'])}_d{'-'.join(map(str, ms['delays']))}"] = model_set(self.f, ms)
        self.groups = {k: np.array(v) for k, v in groups.items()}
        self.P = np.vstack(list(self.groups.values()))

    def smax(self, ctrl):
        return float(1 / np.min(np.abs(1 + ctrl[None, :] * self.P)))

    def smax_groups(self, ctrl):
        return {k: float(1 / np.min(np.abs(1 + ctrl[None, :] * v))) for k, v in self.groups.items()}

    def stable(self, ctrl):
        return bool(np.all(nyquist_stable_many(ctrl[None, :] * self.P)))

    def evaluate(self, d, limit=S_LIMIT):
        """dict(kp, fc, s) of design d if it passes the gate with the DF-product controller, else None."""
        fm = self.fm
        if len(fm._df) > 400:
            fm._df.clear()
        kp = d["kp_scale"] * fm.kp_for_unity(d)
        ctrl = kp * fm.controller(d)
        s = self.smax(ctrl)
        if s > limit or not self.stable(ctrl):
            return None
        fc = first_crossover(self.f, ctrl * fm.G)
        return None if fc is None else dict(kp=kp, fc=fc, s=s)


def sweep_keys(d):
    return [k for k in ("fc", "kp_scale", "r_i", "lead_ratio", "lp_hz", "wc_lp_ratio", "wc_i_ratio") if d[k] is not None]


def make_feasible(ge, d, limit, accept=None, factor=0.97, tries=250):
    """Shrink the crossover parameter until the gate (and `accept(d, kp)`) passes (keeps all ratios)."""
    d = dict(d)
    for _ in range(tries):
        r = ge.evaluate(d, limit)
        if r is not None and (accept is None or accept(d, r["kp"])):
            return d, r
        d["fc"] *= factor
        if d["fc"] < 1.:
            break
    return None, None


def sweep_refine(ge, d, r, limit, steps=(0.2, 0.1, 0.05, 0.025, 0.0125), pair_tries=120, rng=None, max_evals=2000,
                 accept=None, keys=None):
    """Coordinate pattern search + random two-parameter moves maximising the nominal crossover under the gate."""
    keys = keys or sweep_keys(d)
    lo = {k: SWEEP_BOUNDS[k][0] for k in keys}
    hi = {k: SWEEP_BOUNDS[k][1] for k in keys}
    n_eval = 0
    best = (r["fc"], d, r)

    def try_move(q, r0):
        nonlocal n_eval, best
        n_eval += 1
        rq = ge.evaluate(q, limit)
        if rq is None:
            return None
        if not (rq["fc"] > r0["fc"] + 1e-6 or (abs(rq["fc"] - r0["fc"]) <= 1e-3 * r0["fc"] and rq["s"] < r0["s"] - 1e-4)):
            return None
        if accept is not None and not accept(q, rq["kp"]):
            return None
        if rq["fc"] > best[0]:
            best = (rq["fc"], q, rq)
        return rq

    for step in steps:
        improved = True
        while improved and n_eval < max_evals:
            improved = False
            for k in keys:
                for sgn in (1 + step, 1 / (1 + step)):
                    q = dict(d)
                    q[k] = float(np.clip(d[k] * sgn, lo[k], hi[k]))
                    if q[k] == d[k]:
                        continue
                    rq = try_move(q, r)
                    if rq is not None:
                        d, r, improved = q, rq, True
        if rng is not None and step <= 0.05:
            for _ in range(pair_tries):
                if n_eval >= max_evals:
                    break
                a, b = rng.choice(len(keys), 2, replace=False)
                q = dict(d)
                for i in (a, b):
                    q[keys[i]] = float(np.clip(d[keys[i]] * (1 + step * rng.uniform(-1.5, 1.5)), lo[keys[i]], hi[keys[i]]))
                rq = try_move(q, r)
                if rq is not None:
                    d, r = q, rq
    return best[1], best[2]


def perturb(d, rng, sigma=SIGMA_PERTURB, keys=None):
    q = dict(d)
    for k in keys or sweep_keys(d):
        q[k] = float(np.clip(d[k] * np.exp(sigma * rng.normal()), *SWEEP_BOUNDS[k]))
    return q


def optimise_gate(ge, ge_full, starts, limit, rng, sigma=SIGMA_PERTURB, n_perturb=N_PERTURB, keys=None):
    """starts: designs (any may be infeasible). Every accepted design also passes the time-domain screen
    (80 mA clamp, no limit cycle; cached). Returns (d, r) evaluated on the full grid `ge_full`."""
    cache = {}

    def td_ok(q, kp):
        key = tuple(q.values())
        if key not in cache:
            cache[key] = td_screen_sweep(q, kp)[0]
        return cache[key]

    pool, base_designs = [], []
    for s in starts:
        d0, r0 = make_feasible(ge, s, limit, td_ok)
        if d0 is None:
            continue
        pool.append((r0["fc"], d0, r0))
        base_designs.append((d0, r0))
        for _ in range(n_perturb):
            q = perturb(d0, rng, sigma, keys)
            rq = ge.evaluate(q, limit)
            if rq is not None:
                pool.append((rq["fc"], q, rq))
    pool.sort(key=lambda x: -x[0])
    chosen, seen, screens = [], [], 0
    for fc, d, r in pool:                       # distinct starts (fc differs by > 0.5 %) that pass the time-domain screen
        if all(abs(fc / x - 1) > 5e-3 for x in seen) and screens < 60:
            screens += 1
            if td_ok(d, r["kp"]):
                chosen.append((d, r)); seen.append(fc)
        if len(chosen) >= N_REFINE_STARTS:
            break
    if len(chosen) < N_REFINE_STARTS:          # unscreened perturbations failed: fall back to the (screened) start designs
        chosen += sorted(base_designs, key=lambda x: -x[1]["fc"])[:N_REFINE_STARTS - len(chosen)]
    best = None
    for d, r in chosen:
        d, r = sweep_refine(ge, d, r, limit, rng=rng, accept=td_ok, keys=keys)
        if best is None or r["fc"] > best[1]["fc"]:
            best = (d, r)
    d, r = best
    d, r = make_feasible(ge_full, d, limit, td_ok, factor=0.995, tries=300)
    return sweep_refine(ge_full, d, r, limit, steps=(0.025, 0.0125), pair_tries=30, rng=rng, max_evals=400, accept=td_ok, keys=keys)


def td_screen_sweep(d, kp):
    """td_screen() for designs of any bandwidth: no divergence, no clipping at 0.08 A, and no limit cycle, i.e. the error of
    the last 0.2 s is <= 50 urad RMS or still decaying (<= 0.9 x the RMS of the 0.2 s before) in the round trip and the load step.
    (The fixed 50 urad tail of td_screen() would reject slow low-bandwidth designs that are merely not settled yet.)"""
    rec, tr = td_metrics(lambda: Controller(d, kp), disturbance_record=1.2)
    if rec["diverged"] or rec.get("dist_diverged", True) or rec["clipped_samples"] or rec.get("dist_clipped", 1):
        return False, rec

    def settled(e):
        n_t = TAIL_N()
        tail, prev = np.sqrt(np.mean(e[-n_t:]**2)), np.sqrt(np.mean(e[-2 * n_t:-n_t]**2))
        return bool(tail <= TAIL_LIMIT_URAD * 1e-6 or tail <= 0.9 * prev)
    return settled(tr["e"]) and settled(tr["e2"]), rec


def verify_design(ge, d, kp):
    """Time-domain gate (80 mA clamp, no limit cycle) and, for HIGS modes, the numeric DF of the whole cascade
    inside the same gate (all plants of the gate)."""
    ok_td, rec = td_screen_sweep(d, kp)
    out = dict(td_ok=bool(ok_td), td_tail_rms_urad=rec["tail_rms_urad"], td_clipped=rec["clipped_samples"],
               cascade_ok=True, cascade_S_gate=None)
    if d["mode"] != "linear":
        cn, _, _ = controller_df_numeric(d, kp, ge.f)
        ctrl = np.where(ge.f <= FS / 4, cn, kp * ge.fm.controller(d))
        s = ge.smax(ctrl)
        out["cascade_S_gate"] = s
        out["cascade_ok"] = bool(s <= S_LIMIT and ge.stable(ctrl))
    out["ok"] = bool(ok_td and out["cascade_ok"])
    return out


def design_report(ctx, d, kp):
    a, _ = ctx.analyze(d, kp, cascade=False)
    td_rec, _ = td_metrics(lambda: Controller(d, kp))
    keep = ("S_max", "S_max_freq_hz", "fc_hz", "fc_last_hz", "pm_deg", "pm_min_deg", "gm_up_db", "gm_low_db", "T_max",
            "nyquist_stable", "S_max_worst_period", "old_gate_S_max_96_models", "old_gate_S_max_worst_period_6_extra",
            "old_gate_models_nyquist_stable", "old_gate_pass")
    return dict({k: a[k] for k in keep}, params=d, kp=kp, tuning=tuning_fields(d, kp),
                corners_hz={k: (v / (2 * np.pi) if v else None) for k, v in corners(d).items()}, time_domain=td_rec)


def sub_index(f):
    """Search grid: stride 2 below 600 Hz, stride 15 above (the S peak sits at 80-400 Hz)."""
    return np.concatenate([np.where(f <= 600)[0][::2], np.where(f > 600)[0][::15]])


def cross_starts(best, gate, mode, g0_designs):
    """Starts for a HIGS mode built from the linear (and, for 'both', the LP) design of the same gate with the HIGS corner
    ratios of the mode's G0 optimum, so the search does not have to find the linear region from a poor local optimum."""
    out = []
    if mode == "linear" or (gate, "linear") not in best:
        return out
    g0 = g0_designs[mode]
    lin = best[(gate, "linear")]
    out.append(dict(lin, mode=mode, wc_lp_ratio=g0["wc_lp_ratio"], wc_i_ratio=g0["wc_i_ratio"]))
    if mode == "both" and (gate, "LP") in best:
        out.append(dict(best[(gate, "LP")], mode="both", wc_i_ratio=g0["wc_i_ratio"]))
    return out


def gate_sweep(args, log):
    t0 = time.time()
    ctx = Context(1)
    rng = np.random.default_rng(1)
    prev = json.loads((ROOT / "simulations/results/fig89_robustness.json").read_text())
    g0_designs = {m: dict(prev["scenarios"]["nominal_delay1"]["best_designs"]["screened"][m]["params"]) for m in MODES}
    tuning, refs = ctx.reference_designs()          # last-resort starts: the repo's 8 Hz design family (passes the repo gate)
    lin8 = refs["ref8_linear"]
    safe = {"linear": lin8, "LP": dict(lin8, mode="LP", wc_lp_ratio=20. / lin8["fc"]),
            "I": dict(lin8, mode="I", wc_i_ratio=tuning["higs_i_corner_hz"] / lin8["fc"]), "both": refs["ref8_both_HIGS_current"]}
    idx_sub, idx_full = sub_index(ctx.f), np.arange(len(ctx.f))
    gates = list(MAIN_GATES) + ([] if args.no_ablations else [g for g in GATE_SPECS if g.startswith("X_")])
    res = dict(setup=dict(
        S_limit=S_LIMIT, band_hz=list(F_BAND), extra_delay_nominal_measured=1, nominal_model_delay_samples=2,
        search=f"per (gate, mode): starts = designs of neighbouring gates (shrink crossover until the gate passes), "
               f"{N_PERTURB} log-normal perturbations (sigma {SIGMA_PERTURB}) of each, {N_REFINE_STARTS} best distinct starts that pass the "
               f"time-domain screen refined by coordinate + random two-parameter pattern search on a decimated grid "
               f"({len(idx_sub)} of {len(ctx.f)} points), then 2 fine steps on the full grid (every accepted design passes the "
               "time-domain screen: 80 mA clamp, no divergence, 0.2 s tail <= 50 urad or decaying (td_screen_sweep), round trip and load step); then the "
               "numeric DF of the whole cascade must meet the gate (S limit tightened by 0.05 per failure, up to 4 times). "
               "Gates are nested (G0 > G1 > ... > G5), so a backward pass G4..G1 restarts each gate from the stricter gates' optima",
        gates={g: GATE_SPECS[g] for g in gates}, crossover="first |L|=1 crossing of the nominal measured loop (G8 + 1 sample, DF controller)",
        bounds={k: list(v) for k, v in SWEEP_BOUNDS.items()}, seed=1), gates={})
    out_path = args.output / "fig89_gate_sweep.json"
    best = {}          # (gate, mode) -> design
    grids = {}

    def grid(gate):
        if gate not in grids:
            grids[gate] = (GateEval(ctx, gate, idx_sub), GateEval(ctx, gate, idx_full))
        return grids[gate]

    def solve(gate, mode, starts, **kw):
        ge_s, ge_f = grid(gate)
        t1, note, limit = time.time(), "", S_LIMIT
        for attempt in range(5):
            d, r = optimise_gate(ge_s, ge_f, starts, limit, rng, **kw)
            ver = verify_design(ge_f, d, r["kp"])
            if ver["ok"]:
                break
            note += f"attempt {attempt}: td_ok={ver['td_ok']} cascade_ok={ver['cascade_ok']} (limit {limit:.2f}); "
            limit = round(limit - 0.05, 2)
            starts = [d]
        return d, r, ver, note, limit, t1

    def record(gate, mode, d, r, ver, note, limit, t1, **extra):
        ge_f = grid(gate)[1]
        rep = design_report(ctx, d, r["kp"])
        ctrl = r["kp"] * ge_f.fm.controller(d)
        rec = dict(fc_hz=r["fc"], S_gate_max=r["s"], S_groups=ge_f.smax_groups(ctrl), verify=ver, note=note, final_limit=limit,
                   seconds=time.time() - t1, margins=rep, grid_edge_flags=[
                       f"{k} at edge" for k in sweep_keys(d)
                       if d[k] <= SWEEP_BOUNDS[k][0] * 1.001 or d[k] >= SWEEP_BOUNDS[k][1] * 0.999], **extra)
        res["gates"].setdefault(gate, {})[mode] = rec
        best[(gate, mode)] = d
        log(f"  {gate} {mode:6s} fc {r['fc']:6.2f} Hz  S_gate {r['s']:.3f}  pm {rep['pm_deg']:.1f}  td_ok {ver['td_ok']} "
            f"casc_ok {ver['cascade_ok']}  ({time.time() - t1:.0f}s) {note}")

    for gate in gates:
        ge_f = grid(gate)[1]
        log(f"gate {gate}: {GATE_SPECS[gate]['label']}  ({len(ge_f.P)} plants)")
        for mode in MODES:
            if gate == "G0":
                t1 = time.time()
                d = g0_designs[mode]
                r = ge_f.evaluate(d)
                res["setup"].setdefault("G0_reused_fc_hz", {})[mode] = r["fc"]
                record(gate, mode, d, r, verify_design(ge_f, d, r["kp"]), "reused screened optimum of fig89_robustness.json",
                       S_LIMIT, t1)
                continue
            if gate in MAIN_GATES:
                prior = [best[(g, mode)] for g in reversed(MAIN_GATES[:MAIN_GATES.index(gate)])]
                starts = [prior[0], prior[-1]] if len(prior) > 1 else prior
            else:
                starts = [best[("G5", mode)], best[("G0", mode)]]
            starts = starts + [safe[mode]] + cross_starts(best, gate, mode, g0_designs)
            record(gate, mode, *solve(gate, mode, starts))
        if gate == "G5":
            # backward pass: stricter-gate optima are feasible for the looser gates
            for gate_b in reversed(MAIN_GATES[1:-1]):
                log(f"backward pass: gate {gate_b}")
                for mode in MODES:
                    nxt = MAIN_GATES[MAIN_GATES.index(gate_b) + 1]
                    starts = [best[(gate_b, mode)], best[(nxt, mode)], best[("G5", mode)], safe[mode]]
                    starts += cross_starts(best, gate_b, mode, g0_designs)
                    fc_fwd = res["gates"][gate_b][mode]["fc_hz"]
                    out = solve(gate_b, mode, starts)
                    if out[1]["fc"] > fc_fwd:
                        record(gate_b, mode, *out, fc_forward_pass_hz=fc_fwd)
                    else:
                        log(f"  {gate_b} {mode}: backward pass {out[1]['fc']:.2f} <= forward {fc_fwd:.2f}, kept")
        out_path.write_text(json.dumps(jsonable(res), indent=1, allow_nan=False) + "\n")

    def consolidate_all(tag):
        """Gates are nested or nearly so; in any case a design found for one gate may pass another: re-evaluate the best
        design of the same mode from every gate on every gate and keep the best verified one."""
        log(f"consolidation ({tag})")
        for gate_c in gates:
            ge_c = grid(gate_c)[1]
            for mode in MODES:
                cur = res["gates"][gate_c][mode]["fc_hz"]
                cand = []
                for g2 in gates:
                    r2 = ge_c.evaluate(best[(g2, mode)]) if g2 != gate_c else None
                    if r2 is not None and r2["fc"] > cur * 1.0005:
                        cand.append((r2["fc"], g2, best[(g2, mode)], r2))
                for fc2, g2, d2, r2 in sorted(cand, key=lambda x: -x[0]):
                    t1 = time.time()
                    ver = verify_design(ge_c, d2, r2["kp"])
                    if ver["ok"]:
                        record(gate_c, mode, d2, r2, ver, f"consolidated from {g2}", S_LIMIT, t1, fc_before_consolidation_hz=cur)
                        break

    consolidate_all("best design of the same mode from any gate, re-evaluated on every gate")
    log("polish pass: local re-search (sigma 0.15) from the gate's own and the two best other-gate designs")
    for gate in gates:
        for mode in MODES:
            cur = res["gates"][gate][mode]["fc_hz"]
            others = sorted((res["gates"][g2][mode]["fc_hz"], g2) for g2 in gates if g2 != gate)[::-1][:2]
            starts = [best[(gate, mode)]] + [best[(g2, mode)] for _, g2 in others]
            out = solve(gate, mode, starts, sigma=0.15, n_perturb=100)
            if out[1]["fc"] > cur * 1.0005:
                record(gate, mode, *out, fc_before_polish_hz=cur)
        out_path.write_text(json.dumps(jsonable(res), indent=1, allow_nan=False) + "\n")
    consolidate_all("after polish")
    res["summary"] = gate_summary(res)
    res["runtime_s"] = time.time() - t0
    out_path.write_text(json.dumps(jsonable(res), indent=1, allow_nan=False) + "\n")
    plot_gate_sweep(args.output, res)
    log("saved", out_path)


def gate_summary(res):
    g = res["gates"]
    table = {gate: {m: g[gate][m]["fc_hz"] for m in MODES if m in g[gate]} for gate in g}
    gain = {gate: 100 * (v["both"] / v["linear"] - 1) for gate, v in table.items() if "both" in v and "linear" in v}
    steps = {}
    for a, b in zip(MAIN_GATES[:-1], MAIN_GATES[1:]):
        if a in table and b in table:
            steps[f"{a}->{b}"] = {m: table[b][m] - table[a][m] for m in MODES if m in table[a] and m in table[b]}
    abl = {gate: {m: table[gate][m] - table["G0"][m] for m in MODES if m in table[gate]} for gate in table
           if gate.startswith("X_") and "G0" in table}
    return dict(fc_hz=table, both_vs_linear_gain_pct=gain, fc_change_per_step_hz=steps, ablation_fc_change_vs_G0_hz=abl)


def plot_gate_sweep(out, res):
    plt = style()
    gates = [g for g in MAIN_GATES if g in res["gates"]]
    fig, ax = plt.subplots(1, 2, figsize=(12, 4.6), constrained_layout=True, gridspec_kw=dict(width_ratios=[3, 2]))
    x = np.arange(len(gates))
    label = {"linear": "Linear", "I": "I-HIGS", "LP": "LP-HIGS", "both": "Both HIGS"}
    for m in MODES:
        y = [res["gates"][g][m]["fc_hz"] for g in gates]
        ax[0].plot(x, y, "-o", color=COLOR[m], lw=1.5, ms=4, label=label[m])
        ax[0].text(x[-1] + 0.08, y[-1], f"{y[-1]:.1f}", color=COLOR[m], fontsize=7, va="center")
        ax[0].text(x[0] - 0.08, y[0], f"{y[0]:.0f}", color=COLOR[m], fontsize=7, va="center", ha="right")
    short = {"G0": "nominal FRF", "G1": "+ worst period", "G2": "+ Jm/Jl/K 10 %", "G3": "+ Jm/Jl/K 20 %", "G4": "+ delay 1/2/4",
             "G5": "+ C,B, delay 8,\nperiod +6 (repo)"}
    ax[0].set(xticks=x, xticklabels=[f"{g}\n{short[g]}" for g in gates],
              ylabel="max crossover fc [Hz] at max|S| <= 2", yscale="log", xlim=(-0.5, len(gates) - 0.3),
              title="Achievable crossover vs gate strictness (numeric DF, measured FRF)")
    ax[0].tick_params(axis="x", labelsize=7)
    ax[0].set_yticks([25, 30, 40, 50, 60, 75])
    ax[0].yaxis.set_major_formatter(lambda v, _: f"{v:g}")
    ax[0].yaxis.set_minor_formatter(lambda v, _: "")
    ax[0].legend(fontsize=8)
    gain = res["summary"]["both_vs_linear_gain_pct"]
    ax[1].bar(x, [gain[g] for g in gates], color=COLOR["both"], width=0.6)
    for xi, g in zip(x, gates):
        ax[1].text(xi, gain[g] + 1, f"{gain[g]:.0f}%", ha="center", fontsize=8)
    ax[1].set(xticks=x, xticklabels=gates, ylabel="gain of both-HIGS over linear [%]", title="Both-HIGS vs linear bandwidth")
    fig.savefig(out / "fig89_gate_sweep.png", dpi=150)
    plt.close(fig)


# ------------------------------------------------------------------ follow-up (--followup)
OLD_SHAPE = dict(lp_hz=100., lead_ratio=3., r_i=4.)       # repo 8 Hz design: LPF 100 Hz, lead 3 centred at fc, PI at fc/4


def gate_row(ge, d):
    """Gate evaluation of design d (kp = kp_scale * unity-gain kp): S per plant group, Nyquist, first crossover."""
    kp = d["kp_scale"] * ge.fm.kp_for_unity(d)
    ctrl = kp * ge.fm.controller(d)
    groups = ge.smax_groups(ctrl)
    return dict(kp=float(kp), fc_hz=first_crossover(ge.f, ctrl * ge.fm.G), S_gate=max(groups.values()), S_groups=groups,
                nyquist_stable=ge.stable(ctrl))


def repo_gate_numbers(crossover_hz, lead_ratio=3.):
    """The repo's own computation (higs_two_inertia.main, summary.json bandwidth_comparison) for make_design(crossover_hz, lead_ratio):
    worst |S| over 96 models x delay 1/4/8 (linear_metrics, 0.01-3999 Hz grid, repo kp) and worst measured period + 6 samples."""
    n = base.NOMINAL
    cand, _, tuning = base.make_design(crossover_hz=crossover_hz, lead_ratio=lead_ratio)
    worst = 0.0
    for jm, jl, k, c, b, delay in itertools.product([.8, 1.2], [.8, 1.2], [.8, 1.2], [.5, 1.5], [.5, 1.5], [1, 4, 8]):
        model = n | dict(jm=n["jm"] * jm, jl=n["jl"] * jl, stiffness=n["stiffness"] * k, damping=n["damping"] * c,
                         bm=n["bm"] * b, bl=n["bl"] * b)
        worst = max(worst, base.linear_metrics(cand, delay, model)["peak_sensitivity"])
    return dict(S_96_models_repo_code=worst, S_worst_period_plus6_repo_code=base.measured_linear_metrics(cand)["worst_period_with_extra_delay"],
                repo_kp=tuning["kp"], repo_integral_hz=tuning["integral_hz"], repo_lead_zero_hz=tuning["lead_zero_hz"],
                repo_lead_pole_hz=tuning["lead_pole_hz"])


def random_starts(ge, base_d, keys, rng, n=15000, n_top=3):
    """Log-uniform samples over the bounds of `keys`; the n_top best distinct (>0.5 % in fc) gate-feasible designs."""
    found = []
    for _ in range(n):
        q = dict(base_d)
        for k in keys:
            lo, hi = SWEEP_BOUNDS[k]
            q[k] = float(np.exp(rng.uniform(np.log(lo), np.log(hi))))
        r = ge.evaluate(q)
        if r is not None:
            found.append((r["fc"], q))
    found.sort(key=lambda x: -x[0])
    out = []
    for fc, q in found:
        if all(abs(fc / x - 1) > 5e-3 for x, _ in out):
            out.append((fc, q))
        if len(out) >= n_top:
            break
    return [q for _, q in out], len(found)


def td_summary(d, kp, **kw):
    rec, _ = td_metrics(lambda: Controller(d, kp), **kw)
    keep = ("diverged", "clipped_samples", "move_rms_mrad", "settle_rms_urad", "dist_iae_mrad_s", "peak_current_ma",
            "twist_200_400hz_rms_urad", "tail_rms_urad", "dist_diverged", "dist_clipped", "dist_tail_rms_urad")
    return {k: rec[k] for k in keep if k in rec}


def design_record(name, d, kp, ge, **extra):
    row = gate_row(ge, d)
    return dict(name=name, params=d, kp=float(kp), tuning=tuning_fields(d, kp), fc_hz=row["fc_hz"], S_gate=row["S_gate"],
                edge_flags=[f"{k} at edge" for k in sweep_keys(d) if d[k] <= SWEEP_BOUNDS[k][0] * 1.001 or d[k] >= SWEEP_BOUNDS[k][1] * 0.999],
                S_groups=row["S_groups"], nyquist_stable=row["nyquist_stable"], time_domain=td_summary(d, kp), **extra)


def followup_q1(ctx, ge_s, ge_f, rng, log):
    out = {}
    # (a) the repo designs under G5, with the repo's own code path for comparison with summary.json
    ev = {}
    for fc, ri, label in ((8., 4., "repo_8Hz"), (10., 5., "repo_10Hz_PI2Hz"), (10., 4., "10Hz_PI_fc_over_4")):
        d = design_params("linear", fc, 1.0, ri, 3., 100.)
        row = gate_row(ge_f, d)
        row["params"] = d
        row["kp_repo_basis"] = base.make_design(crossover_hz=fc, lead_ratio=3., integral_hz=fc / ri)[2]["kp"]
        if label.startswith("repo"):
            row["repo_code"] = repo_gate_numbers(fc)
        ev[label] = row
        log(f"  {label}: S_gate {row['S_gate']:.3f}  groups { {k[:9]: round(v, 3) for k, v in row['S_groups'].items()} }  "
            f"kp {row['kp']:.4f} (repo {row['kp_repo_basis']:.4f})  repo code {row.get('repo_code', {}).get('S_96_models_repo_code')}")
    out["repo_designs_under_G5"] = ev

    cache = {}

    def td_ok(q, kp):
        key = tuple(q.values())
        if key not in cache:
            cache[key] = td_screen_sweep(q, kp)[0]
        return cache[key]

    def record(name, d, r, keys):
        row = design_record(name, d, r["kp"], ge_f, free_keys=keys)
        row["td_ok"] = bool(td_ok(d, r["kp"]))
        log(f"  {name}: fc {row['fc_hz']:.2f} Hz  S {row['S_gate']:.3f}  td_ok {row['td_ok']}  "
            f"fc_design {d['fc']:.2f} kp_scale {d['kp_scale']:.3f} r_i {d['r_i']:.2f} lead {d['lead_ratio']:.2f} lp {d['lp_hz']:.0f}  {row['edge_flags']}")
        return row

    # (b) shape fixed in ABSOLUTE Hz at the repo 8 Hz design (zero 2.667, pole 24, PI 2, LPF 100): only kp free
    fixed = design_params("linear", 8., 1.0, 4., 3., 100.)
    best, feas = None, []
    for ks in np.geomspace(0.05, 5., 4000):
        d = dict(fixed, kp_scale=float(ks))
        r = ge_f.evaluate(d)
        if r is not None and td_ok(d, r["kp"]):
            feas.append((ks, r))
            if best is None or r["fc"] > best[1]["fc"]:
                best = (d, r)
    rows = {}
    if best:
        rows["kp_only_absolute_8Hz_shape"] = record("kp_only_absolute_8Hz_shape", best[0], best[1], ["kp_scale"])
        rows["kp_only_absolute_8Hz_shape"]["feasible_kp_range"] = [float(feas[0][1]["kp"]), float(feas[-1][1]["kp"])]
    else:
        rows["kp_only_absolute_8Hz_shape"] = None
        log("  kp_only_absolute_8Hz_shape: no feasible kp")

    # (b2) the repo's family: kp_scale = 1 (lead centred at the crossover), only fc free; PI at fc/4 or fixed at 2 Hz
    for name, ri_of in (("fc_only_kp1_PI_fc_over_4", lambda fc: 4.), ("fc_only_kp1_PI_2Hz", lambda fc: fc / 2.)):
        best = None
        for fc in np.geomspace(2., 60., 600):
            d = design_params("linear", fc, 1.0, ri_of(fc), 3., 100.)
            r = ge_f.evaluate(d)
            if r is not None and td_ok(d, r["kp"]) and (best is None or r["fc"] > best[1]["fc"]):
                best = (d, r)
        rows[name] = record(name, best[0], best[1], ["fc"]) if best else None
        if not best:
            log(f"  {name}: no feasible fc")

    # (c) ratios fixed (LPF 100, lead 3 centred at fc, PI fc/4): fc and kp free; then one / two / all shape parameters freed
    plans = [("fc_kp_old_ratios", ["fc", "kp_scale"]),
             ("free_lp_hz", ["fc", "kp_scale", "lp_hz"]), ("free_lead_ratio", ["fc", "kp_scale", "lead_ratio"]),
             ("free_r_i", ["fc", "kp_scale", "r_i"]),
             ("free_lp_hz_lead_ratio", ["fc", "kp_scale", "lp_hz", "lead_ratio"]), ("free_lp_hz_r_i", ["fc", "kp_scale", "lp_hz", "r_i"]),
             ("free_lead_ratio_r_i", ["fc", "kp_scale", "lead_ratio", "r_i"]),
             ("free_all_shape", ["fc", "kp_scale", "lp_hz", "lead_ratio", "r_i"])]
    start_d = design_params("linear", 8., 1.0, 4., 3., 100.)
    for name, keys in plans:
        t1 = time.time()
        starts, n_feas = random_starts(ge_s, start_d, keys, rng, n=3000 if len(keys) < 5 else 8000)
        if not starts:
            log(f"  {name}: no feasible random start")
            rows[name] = None
            continue
        d, r = optimise_gate(ge_s, ge_f, starts, S_LIMIT, rng, keys=keys)
        rows[name] = record(name, d, r, keys)
        rows[name]["seconds"] = time.time() - t1
    out["max_crossover_G5"] = rows
    return out


def optimise_rms(ge, starts, rng, limit=S_LIMIT, sigma=0.3, n_perturb=150, n_refine=3, max_evals=1500,
                 steps=(0.2, 0.1, 0.05, 0.025, 0.0125)):
    """Minimise the round-trip move RMS error of the time-domain model over the design parameters subject to the gate
    (|S| <= limit on all gate plants with the DF controller, Nyquist) and the time-domain screen (td_screen_sweep)."""
    cache = {}

    def cost(q):
        key = tuple(q.values())
        if key not in cache:
            r = ge.evaluate(q, limit)
            res = None
            if r is not None:
                ok, rec = td_screen_sweep(q, r["kp"])
                if ok:
                    res = (rec["move_rms_mrad"], r)
            cache[key] = res
        return cache[key]

    pool = []
    for s in starts:
        d0, _ = make_feasible(ge, s, limit, lambda q, kp: cost(q) is not None)
        if d0 is None:
            continue
        pool.append((cost(d0)[0], d0))
        for _ in range(n_perturb):
            q = perturb(d0, rng, sigma)
            c = cost(q)
            if c is not None:
                pool.append((c[0], q))
    pool.sort(key=lambda x: x[0])
    chosen = []
    for c, q in pool:
        if all(abs(c / x - 1) > 1e-3 for x, _ in chosen):
            chosen.append((c, q))
        if len(chosen) >= n_refine:
            break
    best = None
    for _, d in chosen:
        c, n = cost(d), 0
        keys = sweep_keys(d)
        for step in steps:
            improved = True
            while improved and n < max_evals:
                improved = False
                for k in keys:
                    for sgn in (1 + step, 1 / (1 + step)):
                        q = dict(d)
                        q[k] = float(np.clip(d[k] * sgn, *SWEEP_BOUNDS[k]))
                        if q[k] == d[k]:
                            continue
                        n += 1
                        cq = cost(q)
                        if cq is not None and cq[0] < c[0] * (1 - 1e-4):
                            d, c, improved = q, cq, True
            if step <= 0.1:
                for _ in range(60):
                    a, b = rng.choice(len(keys), 2, replace=False)
                    q = dict(d)
                    for i in (a, b):
                        q[keys[i]] = float(np.clip(d[keys[i]] * (1 + step * rng.uniform(-1.5, 1.5)), *SWEEP_BOUNDS[keys[i]]))
                    cq = cost(q)
                    if cq is not None and cq[0] < c[0] * (1 - 1e-4):
                        d, c = q, cq
        if best is None or c[0] < best[1][0]:
            best = (d, c)
    return best[0], best[1][1], best[1][0]


def followup_q2(ctx, gate_json, rng, log):
    idx_full = np.arange(len(ctx.f))
    rows, designs = {}, {}
    for gate in ("G5", "G1"):
        ge = GateEval(ctx, gate, idx_full)
        for mode in ("linear", "both"):
            t1 = time.time()
            ref = gate_json["gates"][gate][mode]["margins"]
            fc_d, kp_d = dict(ref["params"]), ref["kp"]
            starts = [fc_d]
            if mode == "both":
                lin = designs[(gate, "linear")]
                starts.append(dict(lin, mode="both", wc_lp_ratio=fc_d["wc_lp_ratio"], wc_i_ratio=fc_d["wc_i_ratio"]))
            limit = S_LIMIT
            for attempt in range(5):
                d, r, rms = optimise_rms(ge, starts, rng, limit=limit)
                ver = verify_design(ge, d, r["kp"])
                if ver["ok"]:
                    break
                limit = round(limit - 0.05, 2)
                starts = [d]
            designs[(gate, mode)] = d
            name = f"{gate}_{mode}_error_optimal"
            rows[name] = design_record(name, d, r["kp"], ge, gate=gate, objective="min move RMS", verify=ver, final_limit=limit,
                                       seconds=time.time() - t1)
            name_m = f"{gate}_{mode}_max_fc"
            rows[name_m] = design_record(name_m, fc_d, kp_d, ge, gate=gate, objective="max crossover (gate_sweep)")
            log(f"  {name}: fc {rows[name]['fc_hz']:.2f} Hz  move RMS {rms:.4f} mrad (max-fc design: fc {rows[name_m]['fc_hz']:.2f}, "
                f"RMS {rows[name_m]['time_domain']['move_rms_mrad']:.4f})  S {r['s']:.3f}  ver_ok {ver['ok']}  ({time.time() - t1:.0f}s)")
            if gate == "G5":     # quantization: 1.6 mA current, 20-bit (as requested) and 23-bit (repo default) angle
                for nm, dd, kk in ((name, d, r["kp"]), (name_m, fc_d, kp_d)):
                    rows[nm]["quantized_20bit"] = td_summary(dd, kk, quantized=True, angle_counts=2**20)
                    rows[nm]["quantized_23bit"] = td_summary(dd, kk, quantized=True, angle_counts=2**23)
    return rows


def followup(args, log):
    out_path = args.output / "fig89_followup.json"
    res = json.loads(out_path.read_text()) if out_path.exists() else {}
    gate_json = json.loads((args.output / "fig89_gate_sweep.json").read_text())
    ctx = Context(1)
    idx_sub = sub_index(ctx.f)
    t0 = time.time()
    if args.followup in ("q1", "all"):
        log("Q1: old-shape linear under G5")
        res["q1"] = followup_q1(ctx, GateEval(ctx, "G5", idx_sub), GateEval(ctx, "G5", np.arange(len(ctx.f))), np.random.default_rng(1), log)
        out_path.write_text(json.dumps(jsonable(res), indent=1, allow_nan=False) + "\n")
    if args.followup in ("q2", "all"):
        log("Q2: error-optimal designs")
        res["q2"] = followup_q2(ctx, gate_json, np.random.default_rng(2), log)
        out_path.write_text(json.dumps(jsonable(res), indent=1, allow_nan=False) + "\n")
    # Q3: parameter table (MATLAB exp05_Higs tuning fields) of every reported design
    table = {}
    for gate, modes in gate_json["gates"].items():
        for mode, rec in modes.items():
            m = rec["margins"]
            table[f"{gate}_{mode}_max_fc"] = dict(fc_hz=rec["fc_hz"], params=m["params"], tuning=tuning_fields(m["params"], m["kp"]))
    for name, row in res.get("q1", {}).get("max_crossover_G5", {}).items():
        if row:
            table[f"Q1_{name}"] = dict(fc_hz=row["fc_hz"], params=row["params"], tuning=row["tuning"])
    for name, row in res.get("q2", {}).items():
        table[f"Q2_{name}"] = dict(fc_hz=row["fc_hz"], params=row["params"], tuning=row["tuning"])
    res["parameter_table"] = table
    rob = args.output / "fig89_robustness.json"
    if rob.exists():
        matched = json.loads(rob.read_text())["scenarios"]["nominal_delay1"]["matched_designs"]
        res["matched_G0"] = {m: dict(corners_hz=v["corners_hz"], tuning=v["tuning"], params=v["params"]) for m, v in matched.items()}
    res["runtime_s_last_run"] = time.time() - t0
    out_path.write_text(json.dumps(jsonable(res), indent=1, allow_nan=False) + "\n")
    log("saved", out_path)


# ------------------------------------------------------------------ plots
COLOR = {"linear": "#2a78d6", "I": "#eb6834", "LP": "#1baf7a", "both": "#6250d6", "old": "#888780"}
INK, INK2, SURF = "#0b0b0b", "#52514e", "#fcfcfb"
PRETTY = {"ref8_linear": "8 Hz linear", "ref8_LP_HIGS_20Hz_previous": "8 Hz LP-HIGS 20 Hz (prev.)",
          "ref8_both_HIGS_current": "8 Hz both HIGS (current)",
          "scr_linear": "linear (retuned)",
          "matched_I": "I-HIGS matched", "scr_I": "I-HIGS retuned", "matched_LP": "LP-HIGS matched", "scr_LP": "LP-HIGS retuned",
          "matched_both": "both matched", "scr_both": "both retuned",
          "df_I": "I-HIGS DF-only", "df_LP": "LP-HIGS DF-only", "df_both": "both DF-only"}


def style():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams.update({"font.size": 9, "axes.spines.top": False, "axes.spines.right": False,
                         "axes.facecolor": SURF, "figure.facecolor": SURF, "text.color": INK,
                         "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2,
                         "axes.grid": True, "grid.color": "#e4e3de", "grid.linewidth": 0.6})
    return plt


def mode_of(name):
    return "old" if name.startswith("ref") else name.split("_", 1)[1]


def plot_all(out, ctx, loops, td, traces, suffix, extra_delay):
    plt = style()
    f = ctx.f
    label = {"linear": "Linear", "I": "Integrator HIGS", "LP": "Low-pass HIGS", "both": "Both HIGS"}
    fig, ax = plt.subplots(2, 4, figsize=(15, 7), constrained_layout=True)
    th = np.linspace(0, 2 * np.pi, 400)
    s_old = 20 * np.log10(abs(1 / (1 + loops["ref8_linear"])))
    for j, mode in enumerate(MODES):
        a, b = ax[0, j], ax[1, j]
        for nm, lw, ls, lab in ((f"df_{mode}", 0.9, "--", "DF-only best"), (f"scr_{mode}", 1.6, "-", "time-domain-gated best")):
            if nm not in loops:
                continue
            L = loops[nm]
            a.plot(L.real, L.imag, color=COLOR[mode], lw=lw, ls=ls)
            b.semilogx(f, 20 * np.log10(abs(1 / (1 + L))), color=COLOR[mode], lw=lw, ls=ls, label=f"{label[mode]}, {lab}")
        a.plot(np.cos(th), np.sin(th), color=INK2, lw=0.7, ls=":")
        a.plot(-1 + 0.5 * np.cos(th), 0.5 * np.sin(th), color="#d03b3b", lw=1.0, ls="--")
        a.plot([-1], [0], "+", color=INK, ms=8)
        a.set(xlim=(-2.5, 1.5), ylim=(-2, 2), aspect="equal", title=f"{label[mode]}: L(jw), w > 0", xlabel="Re L", ylabel="Im L")
        b.semilogx(f, s_old, color=COLOR["old"], lw=1.0, label="old 8 Hz linear")
        b.axhline(20 * np.log10(S_LIMIT), color="#d03b3b", ls="--", lw=0.9, label="6.02 dB limit")
        b.set(xlabel="Frequency [Hz]", ylabel="|S| [dB]", xlim=(1, 2000), ylim=(-40, 10))
        b.legend(fontsize=6.5, loc="lower right")
    fig.suptitle(f"Best design per mode at max|S| <= 6 dB (numeric DF, measured FRF, 8 kHz hold + {extra_delay}-sample delay); red dashed: |S| = 2")
    fig.savefig(out / f"fig89_nyquist_S{suffix}.png", dpi=150)
    plt.close(fig)

    keys = [("move_rms_mrad", "Round-trip RMS error [mrad]"), ("settle_rms_urad", "Settle-window RMS [urad]"),
            ("dist_iae_mrad_s", "Load-step IAE [mrad s]"), ("peak_current_ma", "Peak current [mA]"),
            ("twist_200_400hz_rms_urad", "Twist RMS 200-400 Hz [urad]")]
    names = [n for n in PRETTY if n in td]
    fig, ax = plt.subplots(1, len(keys), figsize=(17, 5.2), constrained_layout=True, sharey=True)
    for a, (k, title) in zip(ax, keys):
        absolute = k.startswith("twist")          # linear twist is ~1e-3 urad: ratios are meaningless
        ref = td["scr_linear"][k]
        y = np.arange(len(names))[::-1]
        for yi, n in zip(y, names):
            v = np.nan if td[n].get("diverged") or k not in td[n] else td[n][k]
            r = v if absolute else 100 * v / ref
            r0 = 0 if not np.isfinite(r) else (r if absolute else min(r, 400))
            a.barh(yi, r0, color=COLOR[mode_of(n)], alpha=0.95 if n.startswith(("scr", "ref")) else 0.45,
                   hatch="///" if n.startswith("matched") else None, edgecolor=SURF, lw=0)
            a.text(r0 * (1.15 if absolute else 1) + (0 if absolute else 3), yi,
                   (f"{r:.3g}" if absolute else f"{r:.0f}") if np.isfinite(r) else "diverged", va="center", fontsize=7, color=INK)
        if absolute:
            a.set_xscale("log")
            a.set_xlim(1e-3, 1e4)
            a.set_xlabel("urad (absolute)")
            a.set_title(title, fontsize=9)
        else:
            a.axvline(100, color=INK2, lw=0.7)
            a.set_xlim(0, 480)
            a.set_xlabel("% of retuned linear (bar clipped at 400)")
            a.set_title(f"{title}\n(retuned linear = {ref:.3g})", fontsize=9)
        a.set_yticks(y)
        a.set_yticklabels([PRETTY[n] for n in names])
    fig.savefig(out / f"fig89_metrics_bars{suffix}.png", dpi=150)
    plt.close(fig)


    fig, ax = plt.subplots(1, 2, figsize=(13, 4.2), constrained_layout=True)
    for n, c, lw in (("ref8_linear", COLOR["old"], 1.0), ("scr_linear", COLOR["linear"], 1.2), ("scr_I", COLOR["I"], 1.2),
                     ("scr_LP", COLOR["LP"], 1.2), ("scr_both", COLOR["both"], 1.2)):
        tr = traces.get(n)
        if tr is None:
            continue
        ax[0].plot(tr["t"], 1e3 * tr["e"], color=c, lw=lw, label=PRETTY[n])
        if tr["e2"] is not None:
            ax[1].plot(tr["t2"], 1e3 * tr["e2"], color=c, lw=lw)
    ax[0].set(xlabel="Time [s]", ylabel="tracking error [mrad]", title=f"Round trip (no feedforward), designs for {extra_delay}-sample delay")
    ax[0].legend(fontsize=7)
    ax[1].set(xlabel="Time [s]", ylabel="load-angle error [mrad]", title="Load-torque step at 0.1 s", xlim=(0, 0.8))
    fig.savefig(out / f"fig89_time_traces{suffix}.png", dpi=150)
    plt.close(fig)


def plot_df(out, dfc):
    plt = style()
    fig, ax = plt.subplots(1, 2, figsize=(11, 4), constrained_layout=True)
    for c, colr in zip(dfc["cases"], ("#2a78d6", "#eb6834", "#1baf7a")):
        x = np.array(c["w_over_wh"])
        num = np.array(c["numeric_re"]) + 1j * np.array(c["numeric_im"])
        ax[0].semilogx(x, abs(num), "o", ms=3, color=colr, label=f"numeric, wc = {c['wc_hz']:g} Hz")
        ax[1].semilogx(x, np.degrees(np.angle(num)), "o", ms=3, color=colr)
    x = np.geomspace(0.01, 1e4, 400)
    n = df_analytic(x, 1.0)
    ax[0].semilogx(x, abs(n), color=INK, lw=1, label="analytic")
    ax[1].semilogx(x, np.degrees(np.angle(n)), color=INK, lw=1)
    ax[0].set(xlabel="w / wh", ylabel="|N|", xlim=(0.01, 1e4), yscale="log")
    ax[0].legend(fontsize=7)
    ax[1].set(xlabel="w / wh", ylabel="phase [deg]", xlim=(0.01, 1e4))
    fig.suptitle("HIGS describing function: discrete law (Ts = 125 us) vs analytic; deviation at high w/wh is sampling")
    fig.savefig(out / "fig89_df_check.png", dpi=150)
    plt.close(fig)


if __name__ == "__main__":
    main()
