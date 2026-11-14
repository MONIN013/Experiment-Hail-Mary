#!/usr/bin/env python3
"""Linear and HIGS controllers (Fig. 8.9) for the real two-inertia rig, designed on today's hardware FRF.

Python: numpy, scipy, matplotlib. No MATLAB, TwinCAT or ADS. Reuses higs_fig89_robustness (HIGS law, describing
function, FreqModel, optimisers) with a new plant set, gate and time-domain plant.

Data: simulations/data/hardware/frf_ms030.mat, frf_ms015.mat (random-odd multisine, peak 0.30 / 0.15 A, 8 kHz, open
loop). Hl = load position / commanded current is the loop plant G. The FRF runs from the logged command at sample k to
the logged position at sample k, so it already contains ZOH, EtherCAT and the drive current loop; the controller output
is computed in the same cycle from the same logged position, hence nominal extra delay = 0 samples.

Models (4-state two-inertia of higs_two_inertia.plant_matrices, Kt = 1)
  Sampled response Gd(e^jwT) = (1 - e^-jwT)/T * sum_k P(s_k)/s_k, s_k = j(w + k ws), P = two-inertia * exp(-s tau)
  [/(1 + s/wcl)] (aliased 8 kHz ZOH sum).
  free fit (task 1): jm, jl, bm, bl, k, c, tau (+ wcl) free, Hm and Hl together on 70..1500 Hz, per amplitude. Its bm, bl
    absorb Coulomb friction and differ between amplitudes, so it is not a sliding model.
  design model: bm = bl = 0, tau held at the free fit, jm, jl, k, c fitted on 100..700 Hz (Hm and Hl), per amplitude.
    Above 700 Hz the measured Hm has an unmodelled mode and Hl is noise-limited; 70..150 Hz contains friction lead.
    It is the sliding (frictionless) plant used below 70 Hz, for the variants and for the time domain.

Gate "HW" (every member: max|S| <= 2 with the describing-function controller)
  measured members (4): for ms030 and ms015, G = measured Hl for f >= 70 Hz (lines up to 2499 Hz, design model of that
    amplitude on 2499..3990 Hz) and the design model on a dense log grid 0.5..70 Hz; extra delay 0 and +1 sample. Sparse
    lines: |S| only (no winding check).
  model members (12, dense log grid 0.5..3990 Hz, |S| and Nyquist winding): design model of ms030 and of ms015, and
    the ms030 model with jl x {0.8, 1.2} and k x {0.8, 1.2}; each with extra delay 0 and +1 sample. The nominal model
    members at the same delay are the stability reference of the spliced members.
  Crossover fc of a design = first |L| = 1 crossing of the nominal member (ms030 spliced, delay 0); kp = kp_scale /
  |C G| at the design fc (as in higs_fig89_robustness).

Time domain (secondary to the gate): design model of ms030, integer delay = round(tau), current limit 0.5 A, encoder
quantisation 2^20 counts/rev in the quantised column only (no current quantisation), reference, load step and metrics
as in higs_fig89_robustness.td_metrics (its 0.2 s tail windows are fixed at 1600 samples). Friction columns (approximate,
not used for the optimisation): motor-side friction F(v) = (Fc + (Fs - Fc) exp(-(v/0.02)^2)) tanh(v/0.005), Fc = 0.10 A,
Fs = 0.13 A, linearised-implicit sub-stepping, with the trial feedforward u += Fc*tanh(v_ref/0.05) + 1e-4*a_ref (Fc = 0.10 A)
and without it.

Sample time: --ts (s) or the scalar Ts of the FRF files, else 1/8000; FRF files from --frf-dir (frf_ms030.mat, frf_ms015.mat).
set_sample_time() overrides TS/FS in higs_two_inertia and higs_fig89_robustness before any model or DF table is built.
"""
from __future__ import annotations
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import time

import numpy as np
import scipy.io as sio
from scipy import linalg
from scipy.optimize import least_squares

import higs_fig89_robustness as R

base = R.base
ROOT = R.ROOT
TS, FS = R.TS, R.FS                  # reset by set_sample_time() before anything is evaluated
DATA = ROOT / "simulations/data/hardware"   # --frf-dir
F_MAX = 3990.                        # highest evaluated frequency: 0.9975 * Nyquist
OUT = ROOT / "simulations/results"
CURRENT_LIMIT = 0.5
ENC_COUNTS = 2**20
FRICTION_A, STICTION_A = 0.10, 0.13       # Coulomb and static (peak) friction, motor side
FRICTION_V0, STRIBECK_V = 0.005, 0.02      # tanh smoothing and Stribeck velocity [rad/s]
FF_V0, FF_INERTIA = 0.05, 1e-4             # trial feedforward: Fc*tanh(v_ref/0.05) + 1e-4*a_ref
FIT_BAND = (70., 1500.)
SPLICE_HZ = 70.
KEYS = list(base.NOMINAL)          # jm jl bm bl stiffness damping torque_constant
AMPS = {"ms030": 0.30, "ms015": 0.15}


# ------------------------------------------------------------------ data and model frequency response
def set_sample_time(ts):
    """Override the sample time everywhere it is a module global (this script, higs_two_inertia, higs_fig89_robustness: Tustin
    sections, HIGS discretisation, DF tables, plant discretisation, reference profile, metrics windows)."""
    global TS, FS, F_MAX
    TS, FS, F_MAX = float(ts), 1 / float(ts), 0.9975 * 0.5 / float(ts)
    base.TS = R.TS = TS
    R.FS = FS
    R.F_BAND = (1.0, F_MAX)


def load_frf(name):
    d = sio.loadmat(DATA / f"frf_{name}.mat")
    out = {k: np.asarray(d[k]).squeeze() for k in ("f", "Hm", "Hl", "Ha", "sm")} | {"f": np.asarray(d["f"]).squeeze().astype(float)}
    out["Ts"] = float(np.asarray(d["Ts"]).squeeze()) if "Ts" in d else None
    return out


def pdict(jm, jl, bm, bl, k, c):
    return dict(zip(KEYS, (jm, jl, bm, bl, k, c, 1.0)))


def two_inertia(s, p):
    """Motor and load position per current of the continuous two-inertia model (same equations as plant_matrices)."""
    jm, jl, bm, bl, k, c, kt = (p[x] for x in KEYS)
    z = c * s + k
    a = jm * s**2 + bm * s + z
    b = jl * s**2 + bl * s + z
    den = a * b - z**2
    return kt * b / den, kt * z / den


def plant_frf(f, p, tau, wcl=None, K=12):
    """Sampled (8 kHz ZOH) frequency response of two_inertia * exp(-s tau) / (1 + s/wcl); returns (Hm, Hl)."""
    f = np.atleast_1d(np.asarray(f, float))
    ws, w = 2 * np.pi * FS, 2 * np.pi * f
    hm = np.zeros(len(f), complex)
    hl = np.zeros(len(f), complex)
    for k in range(-K, K + 1):
        s = 1j * (w + k * ws)
        m, l = two_inertia(s, p)
        e = np.exp(-s * tau) / (1 + s / wcl) if wcl else np.exp(-s * tau)
        hm += m * e / s
        hl += l * e / s
    fac = (1 - np.exp(-1j * w * TS)) / TS
    return fac * hm, fac * hl


def band_errors(f, Hmodel, Hmeas, bands=((70, 150), (150, 250), (250, 400), (400, 700), (700, 1000), (1000, 1500))):
    out = {}
    for lo, hi in bands:
        s = (f >= lo) & (f < hi)
        e = np.abs(Hmodel[s] / Hmeas[s] - 1)
        ph = np.degrees(np.angle(Hmodel[s] / Hmeas[s]))
        out[f"{lo}-{hi}"] = dict(rel_rms=float(np.sqrt(np.mean(e**2))), rel_median=float(np.median(e)),
                                 phase_err_median_deg=float(np.median(ph)), n=int(s.sum()))
    return out


# ------------------------------------------------------------------ fits
def free_fit(D, use_lag, tau0s=(1., 2., 3.)):
    """Task 1: free jm, jl, bm, bl, k, c, tau (+ wcl); Hm and Hl on 70..1500 Hz, residual log(Hmodel/Hmeas)."""
    sel = (D["f"] >= FIT_BAND[0]) & (D["f"] <= FIT_BAND[1])
    f = D["f"][sel]

    def unpack(x):
        return pdict(*np.exp(x[:6])), x[6] * TS, (np.exp(x[7]) if use_lag else None)

    def res(x):
        p, tau, wcl = unpack(x)
        m, l = plant_frf(f, p, tau, wcl, K=8)
        r = np.r_[np.log(m / D["Hm"][sel]), np.log(l / D["Hl"][sel])]
        return np.r_[r.real, r.imag]

    best = None
    for tau0, wcl0 in itertools.product(tau0s, (2 * np.pi * 700, 2 * np.pi * 2000) if use_lag else (None,)):
        jl0 = 4e-5
        x0 = np.r_[np.log([4e-5, jl0, 3e-3, 3e-3, jl0 * (2 * np.pi * 235)**2, 1e-3]), tau0]
        x0 = np.r_[x0, np.log(wcl0)] if use_lag else x0
        r = least_squares(res, x0, max_nfev=400)
        if best is None or r.cost < best.cost:
            best = r
    p, tau, wcl = unpack(best.x)
    return dict(params=p, tau_samples=tau / TS, wcl_hz=None if wcl is None else wcl / (2 * np.pi), cost=float(best.cost),
                rms_log_error=float(np.sqrt(2 * best.cost / len(best.fun) * 2)))




DESIGN_FIT_BAND = (100., 700.)


def frictionless_fit(D, tau_samples, band=DESIGN_FIT_BAND):
    """Design model: bm = bl = 0, tau held at the free fit, jm, jl, k, c free (Hm and Hl on `band`)."""
    sel = (D["f"] >= band[0]) & (D["f"] <= band[1])
    f = D["f"][sel]

    def res(x):
        m, l = plant_frf(f, pdict(np.exp(x[0]), np.exp(x[1]), 0., 0., np.exp(x[2]), np.exp(x[3])), tau_samples * TS, None, K=8)
        r = np.r_[np.log(m / D["Hm"][sel]), np.log(l / D["Hl"][sel])]
        return np.r_[r.real, r.imag]

    best = None
    for c0, jl0 in itertools.product((1e-3, 3e-2, 0.3), (3e-5, 5e-5)):
        r = least_squares(res, np.log([4e-5, jl0, jl0 * (2 * np.pi * 235)**2, c0]), max_nfev=400)
        if best is None or r.cost < best.cost:
            best = r
    jm, jl, k, c = np.exp(best.x)
    return dict(params=pdict(jm, jl, 0., 0., k, c), tau_samples=tau_samples, band_hz=list(band), cost=float(best.cost))


def fmt_p(p):
    return {k: float(f"{v:.4g}") for k, v in p.items() if k != "torque_constant"}


def fit_all(log):
    """Free fit (task 1) and design model for both amplitudes."""
    out = {}
    for name in AMPS:
        D = load_frf(name)
        rec = {}
        for lag in (False, True):
            fr = free_fit(D, lag)
            wcl = None if fr["wcl_hz"] is None else 2 * np.pi * fr["wcl_hz"]
            m, l = plant_frf(D["f"], fr["params"], fr["tau_samples"] * TS, wcl)
            fr["band_errors_Hl"] = band_errors(D["f"], l, D["Hl"])
            fr["band_errors_Hm"] = band_errors(D["f"], m, D["Hm"])
            rec["free_lag" if lag else "free"] = fr
        # the first-order lag is kept only if it lowers the cost by > 3 % and has a corner below 4 kHz
        lagfit = rec["free_lag"]
        rec["lag_used"] = bool(lagfit["wcl_hz"] and lagfit["wcl_hz"] < 4000 and lagfit["cost"] < 0.97 * rec["free"]["cost"])
        fd = frictionless_fit(D, rec["free"]["tau_samples"])
        m, l = plant_frf(D["f"], fd["params"], fd["tau_samples"] * TS, None)
        fd["band_errors_Hl"] = band_errors(D["f"], l, D["Hl"])
        fd["band_errors_Hm"] = band_errors(D["f"], m, D["Hm"])
        fd["model_phase_lags_meas_70_150_Hl"] = bool(fd["band_errors_Hl"]["70-150"]["phase_err_median_deg"] < 0)
        rec["design"] = fd
        out[name] = rec
        log(f"fit {name}: free {fmt_p(rec['free']['params'])} tau {rec['free']['tau_samples']:.2f} smp, lag used {rec['lag_used']}; "
            f"design {fmt_p(fd['params'])}")
    return out


# ------------------------------------------------------------------ plant set and gate
def freq_grids(D):
    """S grid: dense 0.5..70 Hz | measured lines 70 Hz..last line | dense above the last line up to F_MAX.  M grid: dense 0.5..F_MAX."""
    lo = np.geomspace(0.5, SPLICE_HZ, 100, endpoint=False)
    lines = D["f"][D["f"] >= SPLICE_HZ]
    hi = np.geomspace(D["f"][-1] * 1.001, F_MAX, 40) if D["f"][-1] * 1.001 < F_MAX else np.array([])
    fs = np.concatenate([lo, lines, hi])
    fm = np.unique(np.concatenate([np.geomspace(0.5, F_MAX, 450), np.linspace(100., 700., 240)]))
    return fs, fm


def delayed(f, G, n):
    return G * np.exp(-2j * np.pi * f * TS * n)


def cascade_df(d, kp, n_max=1000, n_pts=36, periods=5, keep=2):
    """First harmonic of the whole nonlinear controller (as R.controller_df_numeric, fewer points/periods for speed) on
    n = 4..n_max samples per period, i.e. f >= FS/n_max (8 Hz at 8 kHz); below that the product of DFs is used."""
    n_list = np.unique(np.round(np.geomspace(4, n_max, n_pts)).astype(int))
    vals = []
    for n in n_list:
        ctrl = R.Controller(d, kp)
        th = 2 * np.pi * np.arange(periods * n) / n + 0.3
        y = np.array([ctrl.step(float(v)) for v in 1e-3 * np.sin(th)])
        sl = slice((periods - keep) * n, periods * n)
        thk = th[sl] % (2 * np.pi)
        vals.append(2 / (keep * n) * (np.sum(y[sl] * np.sin(thk)) + 1j * np.sum(y[sl] * np.cos(thk))) / 1e-3)
    fg = FS / n_list
    order = np.argsort(fg)
    return fg[order], np.array(vals)[order]


class HwGate:
    """Gate HW. Two frequency grids: `S` (measured lines spliced with the design model; |S| only) and `M` (dense model
    members; |S| and winding). Row 0 of S is the nominal plant (ms030, delay 0). evaluate() returns dict(kp, fc, s) like
    R.GateEval.evaluate."""

    def __init__(self, S, M, idx_s=None, idx_m=None):
        self.full = (S, M)
        self.grids = {}
        for key, (f, P), idx in (("S", S, idx_s), ("M", M, idx_m)):
            idx = np.arange(len(f)) if idx is None else idx
            self.grids[key] = dict(f=f[idx], P=P[:, idx], fm=R.FreqModel(f[idx], P[0][idx], extra_delay=0), check=(key == "M"))
        self.nominal = self.grids["S"]

    def subset(self, idx_s, idx_m):
        return HwGate(*self.full, idx_s, idx_m)

    def controllers(self, d, kp):
        out = {}
        for k, g in self.grids.items():
            fm = g["fm"]
            if len(fm._df) > 400:
                fm._df.clear()
            out[k] = kp * fm.controller(d)
        return out

    def evaluate(self, d, limit=R.S_LIMIT):
        kp = d["kp_scale"] * self.nominal["fm"].kp_for_unity(d)
        ctrl = self.controllers(d, kp)
        s = 0.
        for k, g in self.grids.items():
            s = max(s, float(1 / np.min(np.abs(1 + ctrl[k][None, :] * g["P"]))))
            if s > limit:
                return None
        if not bool(np.all(R.nyquist_stable_many(ctrl["M"][None, :] * self.grids["M"]["P"]))):
            return None
        fc = R.first_crossover(self.nominal["f"], ctrl["S"] * self.nominal["P"][0])
        return None if fc is None else dict(kp=kp, fc=fc, s=s)

    def report(self, d, kp, names_s, names_m):
        """|S| per member, stability of the model members, crossover and phase margin of the nominal member."""
        ctrl = self.controllers(d, kp)
        rep = {}
        for k, names in (("S", names_s), ("M", names_m)):
            g = self.grids[k]
            L = ctrl[k][None, :] * g["P"]
            sm = 1 / np.min(np.abs(1 + L), axis=1)
            fpk = g["f"][np.argmin(np.abs(1 + L), axis=1)]
            for i, n in enumerate(names):
                rep[n] = dict(S_max=float(sm[i]), S_max_freq_hz=float(fpk[i]))
                if g["check"]:
                    rep[n]["nyquist_stable"] = bool(R.nyquist_stable_many(L[i:i + 1])[0])
        mt = R.loop_metrics(self.nominal["f"], ctrl["S"] * self.nominal["P"][0])
        return rep, dict(fc_hz=mt["fc_hz"], pm_deg=mt["pm_deg"], pm_min_deg=mt["pm_min_deg"], gm_up_db=mt["gm_up_db"],
                         gm_low_db=mt["gm_low_db"], S_max_nominal=mt["S_max"])

    def cascade_ok(self, d, kp, limit=R.S_LIMIT):
        """Numeric DF of the whole HIGS cascade replaces the product of DFs on both grids; returns (ok, S_max)."""
        fg, vals = cascade_df(d, kp)
        smax, ok = 0., True
        for g in self.grids.values():
            cn = np.interp(np.log(g["f"]), np.log(fg), vals.real) + 1j * np.interp(np.log(g["f"]), np.log(fg), vals.imag)
            prod = kp * g["fm"].controller(d)
            ctrl = np.where((g["f"] <= FS / 4) & (g["f"] >= fg[0]), cn, prod)
            L = ctrl[None, :] * g["P"]
            smax = max(smax, float(1 / np.min(np.abs(1 + L))))
            if g["check"]:
                ok = ok and bool(np.all(R.nyquist_stable_many(L)))
        return bool(ok and smax <= limit), smax


def build_gate(fits, Ds):
    """Rows: S = [ms030 d0, ms030 d1, ms015 d0, ms015 d1]; M = [030 nominal d0/d1, 015 nominal d0/d1, 030 variants (jl, k) d0/d1]."""
    fs, fm_grid = freq_grids(Ds["ms030"])
    rows_s, names_s, rows_m, names_m = [], [], [], []
    for amp in AMPS:
        D, fd = Ds[amp], fits[amp]["design"]
        mdl = plant_frf(fs, fd["params"], fd["tau_samples"] * TS)[1]
        meas = np.interp(fs, D["f"], D["Hl"].real) + 1j * np.interp(fs, D["f"], D["Hl"].imag)     # used only on the lines
        G = np.where((fs >= SPLICE_HZ) & (fs <= D["f"][-1]), meas, mdl)
        for n in (0, 1):
            rows_s.append(delayed(fs, G, n))
            names_s.append(f"{amp}_measured_spliced_d{n}")
    for amp in AMPS:
        fd = fits[amp]["design"]
        g = plant_frf(fm_grid, fd["params"], fd["tau_samples"] * TS)[1]
        for n in (0, 1):
            rows_m.append(delayed(fm_grid, g, n))
            names_m.append(f"{amp}_model_nominal_d{n}")
    fd = fits["ms030"]["design"]
    for sjl, sk in itertools.product((0.8, 1.2), (0.8, 1.2)):
        p = dict(fd["params"], jl=fd["params"]["jl"] * sjl, stiffness=fd["params"]["stiffness"] * sk)
        g = plant_frf(fm_grid, p, fd["tau_samples"] * TS)[1]
        for n in (0, 1):
            rows_m.append(delayed(fm_grid, g, n))
            names_m.append(f"ms030_model_jl{sjl:g}_k{sk:g}_d{n}")
    return (fs, np.array(rows_s)), (fm_grid, np.array(rows_m)), names_s, names_m


def sub_idx(f):
    """Search grid: every 2nd point below 600 Hz, every 12th above."""
    return np.concatenate([np.where(f <= 600)[0][::2], np.where(f > 600)[0][::12]])


# ------------------------------------------------------------------ time-domain plant (replaces R.simulate)
class TdModel:
    p = None
    delay = 2
    friction = 0.0       # Coulomb level Fc [A] on the motor inertia (0: frictionless)
    stiction = 0.0       # static (peak) level Fs [A] >= Fc
    ff = 0.0             # friction feedforward gain Fc_ff [A]: u += Fc_ff*tanh(v_ref/FF_V0) + FF_INERTIA*a_ref


def set_td_model(p, delay):
    TdModel.p, TdModel.delay = p, delay


def _substep_matrices(p, n_sub):
    dt = TS / n_sub
    jm, jl, bm, bl, k, c, kt = (p[x] for x in KEYS)
    a = np.array([[0, 1, 0, 0], [-k / jm, -(bm + c) / jm, k / jm, c / jm], [0, 0, 0, 1], [k / jl, c / jl, -k / jl, -(bl + c) / jl]])
    bcols = np.array([[0, 0], [kt / jm, 0], [0, 0], [0, 1 / jl]])
    m = np.zeros((6, 6))
    m[:4, :4], m[:4, 4:] = a, bcols
    e = linalg.expm(m * dt)
    return e[:4, :4], e[:4, 4], e[:4, 5], jm


def friction_force(v, fc, fs):
    """F(v) = (Fc + (Fs - Fc) exp(-(v/vs)^2)) tanh(v/v0) and dF/dv."""
    e = np.exp(-(v / STRIBECK_V) ** 2)
    amp = fc + (fs - fc) * e
    t = np.tanh(v / FRICTION_V0)
    damp = -(fs - fc) * 2 * v / STRIBECK_V**2 * e
    return amp * t, damp * t + amp * (1 - t * t) / FRICTION_V0


def simulate_hw(ctrl, reference, load_torque=None, *, delay=None, quantized=False, current_limit=CURRENT_LIMIT,
                angle_counts=ENC_COUNTS):
    """Same contract as R.simulate (out columns theta_m, w_m, theta_l, w_l, command, applied; clipped; diverged) on the
    design model with integer delay and the 0.5 A limit; quantized = encoder quantisation only. TdModel.friction > 0 adds
    motor-side friction F(v) (Coulomb Fc, Stribeck peak Fs, tanh smoothing), linearised-implicit in 8 sub-steps per sample;
    TdModel.ff > 0 adds the trial feedforward u += ff*tanh(v_ref/0.05) + 1e-4*a_ref (v_ref, a_ref from the reference samples).
    The feedforward is part of the command (counted in clipping and peak current)."""
    delay = TdModel.delay if delay is None else delay
    n = len(reference)
    out = np.zeros((n, 6))
    queue = [0.0] * (delay + 1)
    eq = 2 * np.pi / angle_counts if quantized else 0.0
    clipped = 0
    r_list = reference.tolist()
    d_arr = load_torque if load_torque is not None else np.zeros(n)
    if TdModel.ff:
        v_ref = np.gradient(reference, TS)
        ff_list = (TdModel.ff * np.tanh(v_ref / FF_V0) + FF_INERTIA * np.gradient(v_ref, TS)).tolist()
    else:
        ff_list = [0.0] * n
    fc, fs = TdModel.friction, max(TdModel.stiction, TdModel.friction)
    if fc:
        n_sub = 8
        ad, bm_, bd_, jm = _substep_matrices(TdModel.p, n_sub)
        h = TS / n_sub / jm
        x = np.zeros(4)
    else:
        ad, bm_, bd_ = (v.tolist() for v in R.discrete_plant(TdModel.p))
        d_list = d_arr.tolist()
        x = [0.0] * 4
    for k in range(n):
        y = x[2]
        if eq:
            y = np.floor(y / eq + 0.5) * eq
        cmd = ctrl.step(r_list[k] - y) + ff_list[k]
        app = max(-current_limit, min(current_limit, cmd))
        clipped += abs(cmd) > current_limit
        queue[k % (delay + 1)] = app
        dl = queue[(k - delay) % (delay + 1)] if k >= delay else 0.0
        out[k] = (x[0], x[1], x[2], x[3], cmd, dl)
        if fc:
            dk = float(d_arr[k])
            for _ in range(n_sub):
                x = ad @ x + bm_ * dl + bd_ * dk
                f0, df = friction_force(x[1], fc, fs)
                x[1] -= h * f0 / max(1 + h * df, 0.1)
        else:
            dk = d_list[k]
            x = [ad[i][0] * x[0] + ad[i][1] * x[1] + ad[i][2] * x[2] + ad[i][3] * x[3] + bm_[i] * dl + bd_[i] * dk for i in range(4)]
        if abs(x[0]) > 1e3:
            out[k + 1:] = np.nan
            return out, int(clipped), True
    return out, int(clipped), False


TD_KEEP = ("diverged", "clipped_samples", "move_rms_mrad", "peak_error_mrad", "settle_rms_urad", "dist_iae_mrad_s", "dist_peak_mrad",
           "peak_current_ma", "twist_200_400hz_rms_urad", "tail_rms_urad", "dist_tail_rms_urad", "dist_diverged", "dist_clipped")


def td_record(d, kp, friction=0.0, stiction=0.0, ff=0.0, quantized=False):
    TdModel.friction, TdModel.stiction, TdModel.ff = friction, stiction, ff
    try:
        rec, _ = R.td_metrics(lambda: R.Controller(d, kp), quantized=quantized, angle_counts=ENC_COUNTS)
    finally:
        TdModel.friction = TdModel.stiction = TdModel.ff = 0.0
    return {k: rec[k] for k in TD_KEEP if k in rec}


# ------------------------------------------------------------------ design search
HIGS_START = dict(LP=dict(wc_lp_ratio=1.0), I=dict(wc_i_ratio=0.1), both=dict(wc_lp_ratio=1.0, wc_i_ratio=0.1))


def start_design(mode):
    return R.design_params(mode, 20., 1., 4., 3., 300., **HIGS_START.get(mode, {}))


_SCREEN = dict(orig=R.td_screen_sweep, gate=None, cache={})


def screen_with_cascade(d, kp):
    """R.td_screen_sweep plus, for HIGS modes, the numeric-cascade gate (the product of DFs misjudges the two-HIGS cascade
    by up to 40 % / 18 deg at 10..60 Hz when the HIGS corners are far below the frequency). Cached per design."""
    ok, rec = _SCREEN["orig"](d, kp)
    if ok and d["mode"] != "linear":
        key = tuple(d.values())
        if key not in _SCREEN["cache"]:
            _SCREEN["cache"][key] = _SCREEN["gate"].cascade_ok(d, kp, R.S_LIMIT)[0]
        ok = _SCREEN["cache"][key]
    return ok, rec


def verify(ge, d, kp, limit):
    """Time-domain screen (no divergence/clipping/limit cycle) and, for HIGS modes, the numeric DF of the whole cascade."""
    ok_td, rec = R.td_screen_sweep(d, kp)
    out = dict(td_ok=bool(ok_td), td_tail_rms_urad=rec["tail_rms_urad"], cascade_ok=True, cascade_S=None)
    if d["mode"] != "linear":
        out["cascade_ok"], out["cascade_S"] = ge.cascade_ok(d, kp, R.S_LIMIT)
    out["ok"] = bool(out["td_ok"] and out["cascade_ok"])
    return out


def solve(ge_s, ge_f, mode, rng, extra_starts, objective, log, n_random, n_top, restarts):
    """objective 'fc' (max crossover, optimise_gate) or 'rms' (min round-trip RMS, optimise_rms). `restarts` independent random
    start sets per attempt, best kept. The gate limit is tightened by 0.05 (up to 4 times) until the full-grid verification
    (time domain, HIGS cascade DF) passes."""
    base_d = start_design(mode)
    keys = R.sweep_keys(base_d)
    limit, carried = R.S_LIMIT, []
    for attempt in range(5):
        best = None
        for i in range(1 if carried else restarts):
            rs, n_found = R.random_starts(ge_s, base_d, keys, rng, n=n_random, n_top=n_top)
            starts = carried + rs + extra_starts
            if objective == "fc":
                d, r = R.optimise_gate(ge_s, ge_f, starts, limit, rng, n_perturb=300, keys=keys)
                val = -r["fc"]
            else:
                heavy = mode != "linear"          # HIGS: every candidate also costs a cascade DF (~0.06 s)
                d, r, val = R.optimise_rms(ge_f, starts, rng, limit=limit, n_perturb=100 if heavy else 150,
                                           n_refine=3 if heavy else 4, max_evals=1500 if heavy else 2500)
            log(f"    {mode}/{objective} attempt {attempt} restart {i}: {len(rs)} random starts ({n_found} feasible of {n_random}), "
                f"fc {r['fc']:.2f} Hz, {'RMS %.4f mrad' % val if objective == 'rms' else 'S %.3f' % r['s']}")
            if best is None or val < best[2]:
                best = (d, r, val)
        d, r, val = best
        ver = verify(ge_f, d, r["kp"], limit)
        if ver["ok"]:
            break
        log(f"    {mode}/{objective}: verification failed ({ver}), limit {limit:.2f} -> {limit - 0.05:.2f}")
        limit = round(limit - 0.05, 2)
        carried = [d]
    return d, r, ver, limit, (-val if objective == "fc" else val)


def design_record(name, d, kp, ge, names_s, names_m, **extra):
    rep, mt = ge.report(d, kp, names_s, names_m)
    return dict(name=name, design=d, kp=float(kp), crossover_hz=mt["fc_hz"], margins_nominal=mt,
                S_max_worst_member=max(v["S_max"] for v in rep.values()), S_max_members=rep,
                all_model_members_nyquist_stable=all(v.get("nyquist_stable", True) for v in rep.values()),
                edge_flags=[f"{k} at edge" for k in R.sweep_keys(d)
                            if d[k] <= R.SWEEP_BOUNDS[k][0] * 1.001 or d[k] >= R.SWEEP_BOUNDS[k][1] * 0.999],
                time_domain_nominal=td_record(d, kp), time_domain_encoder_2e20=td_record(d, kp, quantized=True),
                time_domain_friction_FF_approx=td_record(d, kp, friction=FRICTION_A, stiction=STICTION_A, ff=FRICTION_A),
                time_domain_friction_noFF_approx=td_record(d, kp, friction=FRICTION_A, stiction=STICTION_A),
                tuning=R.tuning_fields(d, kp),
                corners_hz={k: (v / (2 * np.pi) if v else None) for k, v in R.corners(d).items()}, **extra)


# ------------------------------------------------------------------ exp05 design files
def exp05_design(rec, kind):
    ref = json.loads((ROOT / "simulations/higs_design.json").read_text())
    t = rec["tuning"]
    d = dict(ref)
    d.update(sample_time_s=TS, sensitivity_limit=2, max_current_a=CURRENT_LIMIT, max_position_rad=0.5, max_velocity_rad_s=5,
             max_twist_rad=0.05)
    assert 2.1875 * d["reference_amplitude_rad"] / d["move_time_s"] < d["max_velocity_rad_s"] and d["reference_amplitude_rad"] < d["max_position_rad"]
    tuning = {k: t[k] for k in ("kp", "integral_hz", "lead_zero_hz", "lead_pole_hz", "lowpass_hz")}
    tuning["measured_crossover_target_hz"] = rec["design"]["fc"]
    tuning["gain_basis"] = ("Hardware load FRF frf_ms030.mat (Hl, f >= 70 Hz) spliced with the frictionless two-inertia fit below 70 Hz; "
                            "kp = kp_scale * 1/|C(j2 pi fc) G(j2 pi fc)| at the design crossover fc (delay 0 samples)")
    for k in ("higs_lp_corner_hz", "higs_i_corner_hz", "higs_lp_gain", "higs_i_gain"):
        tuning[k] = t[k]
    d["tuning"] = tuning
    d["provenance"] = (f"simulations/higs_hw_design.py, error-optimal {kind} design under gate HW from hardware FRF "
                       f"{DATA.relative_to(ROOT).as_posix() if DATA.is_relative_to(ROOT) else DATA.as_posix()}/frf_ms030.mat and frf_ms015.mat "
                       f"(random-odd multisine 0.30 / 0.15 A, {FS / 1000:g} kHz, open loop)")
    h = hashlib.sha256()
    for n in ("frf_ms030.mat", "frf_ms015.mat"):
        h.update((DATA / n).read_bytes())
    d["source_sha256"] = h.hexdigest()
    return d


# ------------------------------------------------------------------ plot
def plot(path, fits, Ds, recs, ge, ges_names):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(2, 2, figsize=(13, 8.5))
    for amp, col in zip(AMPS, ("#2a78d6", "#eb6834")):
        D, fd = Ds[amp], fits[amp]["design"]
        fr = fits[amp]["free"]
        f = D["f"]
        _, ld = plant_frf(f, fd["params"], fd["tau_samples"] * TS)
        _, lf = plant_frf(f, fr["params"], fr["tau_samples"] * TS)
        ax[0, 0].loglog(f, np.abs(D["Hl"]), ".", ms=2, color=col, label=f"{amp} measured")
        ax[0, 0].loglog(f, np.abs(ld), "-", lw=1.2, color=col, label=f"{amp} design model (no friction)")
        ax[0, 0].loglog(f, np.abs(lf), "--", lw=0.9, color=col, label=f"{amp} free fit")
        ax[1, 0].semilogx(f, np.degrees(np.angle(D["Hl"] / ld)), ".", ms=2, color=col, label=f"{amp} meas/design")
        ax[1, 0].semilogx(f, np.degrees(np.angle(D["Hl"] / lf)), "-", lw=0.8, color=col, label=f"{amp} meas/free")
    ax[0, 0].set_title("Load FRF Hl [rad/A]")
    ax[1, 0].set_title("phase(measured / model) [deg]")
    ax[1, 0].set_ylim(-60, 90)
    g = ge.grids["S"]
    f = g["f"]
    for name, rec in recs.items():
        d = rec["design"]
        kp = rec["kp"]
        ctrl = kp * g["fm"].controller(d)
        L = ctrl * g["P"][0]
        col = R.COLOR[d["mode"]]
        ls = "-" if name.endswith("error_opt") else "--"
        ax[0, 1].semilogx(f, np.abs(1 / (1 + L)), ls, color=col, lw=1.1, label=name)
        ax[1, 1].loglog(f, np.abs(L), ls, color=col, lw=1.1)
    ax[0, 1].axhline(2, color="#888780", lw=0.8)
    ax[0, 1].set_title("|S| of the nominal member (ms030, delay 0)")
    ax[1, 1].set_title("|L| nominal member")
    ax[1, 1].set_ylim(1e-3, 1e3)
    for a in ax.flat:
        a.grid(True, which="both", alpha=0.3)
        a.set_xlabel("Hz")
    ax[0, 0].legend(fontsize=7)
    ax[1, 0].legend(fontsize=7)
    ax[0, 1].legend(fontsize=7, ncol=2)
    fig.tight_layout()
    fig.savefig(path, dpi=110)


# ------------------------------------------------------------------ main
def main():
    global DATA
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--modes", default="linear,both,I,LP")
    ap.add_argument("--n-random", type=int, default=20000)
    ap.add_argument("--n-top", type=int, default=4)
    ap.add_argument("--restarts", type=int, default=3)
    ap.add_argument("--output", type=Path, default=OUT)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--frf-dir", type=Path, default=DATA, help="directory with frf_ms030.mat and frf_ms015.mat")
    ap.add_argument("--ts", type=float, default=None, help="sample time [s]; default: scalar Ts of the FRF file, else 1/8000")
    args = ap.parse_args()
    t0 = time.time()
    DATA = args.frf_dir

    def log(*a):
        print(f"[{time.time() - t0:6.0f}s]", *a, flush=True)

    modes = args.modes.split(",")
    rng = np.random.default_rng(args.seed)
    Ds = {n: load_frf(n) for n in AMPS}
    file_ts = {D["Ts"] for D in Ds.values()} - {None}
    assert len(file_ts) <= 1, f"FRF files disagree on Ts: {file_ts}"
    ts = args.ts or (file_ts.pop() if file_ts else 1 / 8000)
    set_sample_time(ts)
    log(f"sample time {ts:.6g} s ({1 / ts:.0f} Hz), FRF dir {DATA}, F_MAX {F_MAX:.0f} Hz")
    fits = fit_all(log)
    delay = int(round(fits["ms030"]["free"]["tau_samples"]))
    set_td_model(fits["ms030"]["design"]["params"], delay)
    R.simulate = simulate_hw                                  # td_metrics/td_screen_sweep use this module global
    R.SWEEP_BOUNDS.update(lp_hz=(60., 600.))                  # fc stays (1, 200); lead ratio, r_i, kp_scale, HIGS ratios as in R
    S, M, names_s, names_m = build_gate(fits, Ds)
    ge_f = HwGate(S, M)
    ge_s = ge_f.subset(sub_idx(S[0]), sub_idx(M[0]))
    _SCREEN["gate"] = ge_f
    R.td_screen_sweep = screen_with_cascade                   # used by optimise_gate / optimise_rms as accept test
    log(f"gate HW: {len(names_s)} measured + {len(names_m)} model members; grid S {len(S[0])} (search {len(ge_s.grids['S']['f'])}), "
        f"M {len(M[0])} (search {len(ge_s.grids['M']['f'])}); TD delay {delay} samples, design model {fmt_p(fits['ms030']['design']['params'])}")
    R.df_table()
    log("DF table ready")

    recs, best_lin = {}, None
    for mode in modes:
        t1 = time.time()
        extra = []
        if best_lin is not None and mode != "linear":
            extra.append(dict(best_lin, mode=mode, **{k: v for k, v in HIGS_START[mode].items()}))
        log(f"mode {mode}: max-crossover search")
        d, r, ver, lim, fc = solve(ge_s, ge_f, mode, rng, extra, "fc", log, args.n_random, args.n_top, args.restarts)
        recs[f"{mode}_max_fc"] = design_record(f"{mode}_max_fc", d, r["kp"], ge_f, names_s, names_m, objective="max crossover",
                                               verify=ver, final_limit=lim, seconds=time.time() - t1)
        log(f"  {mode} max-fc: fc {fc:.2f} Hz  S {r['s']:.3f}  limit {lim}  verify {ver['ok']}  {d}")
        if mode == "linear":
            best_lin = d
        t1 = time.time()
        log(f"mode {mode}: error-optimal search")
        d2, r2, ver2, lim2, rms = solve(ge_s, ge_f, mode, rng, [d] + extra, "rms", log, args.n_random // 2, args.n_top, args.restarts)
        recs[f"{mode}_error_opt"] = design_record(f"{mode}_error_opt", d2, r2["kp"], ge_f, names_s, names_m,
                                                  objective="min round-trip RMS", verify=ver2, final_limit=lim2, seconds=time.time() - t1)
        log(f"  {mode} error-opt: fc {r2['fc']:.2f} Hz  RMS {rms:.4f} mrad  S {r2['s']:.3f}  limit {lim2}  verify {ver2['ok']}  {d2}")
        args.output.mkdir(parents=True, exist_ok=True)

    fit_json = {n: dict(
        free=dict(params=fmt_full(fits[n]["free"]["params"]), tau_samples=fits[n]["free"]["tau_samples"], lag_corner_hz=fits[n]["free"]["wcl_hz"],
                  cost=fits[n]["free"]["cost"], rms_log_error=fits[n]["free"]["rms_log_error"],
                  band_errors_Hl=fits[n]["free"]["band_errors_Hl"], band_errors_Hm=fits[n]["free"]["band_errors_Hm"]),
        free_with_lag=dict(params=fmt_full(fits[n]["free_lag"]["params"]), tau_samples=fits[n]["free_lag"]["tau_samples"],
                           lag_corner_hz=fits[n]["free_lag"]["wcl_hz"], cost=fits[n]["free_lag"]["cost"]),
        lag_used=fits[n]["lag_used"],
        design=dict(params=fmt_full(fits[n]["design"]["params"]), tau_samples=fits[n]["design"]["tau_samples"],
                    band_hz=fits[n]["design"]["band_hz"], cost=fits[n]["design"]["cost"],
                    band_errors_Hl=fits[n]["design"]["band_errors_Hl"], band_errors_Hm=fits[n]["design"]["band_errors_Hm"],
                    model_phase_lags_meas_70_150_Hl=fits[n]["design"]["model_phase_lags_meas_70_150_Hl"]))
        for n in AMPS}
    res = dict(
        fits=fit_json,
        gate=dict(name="HW", S_limit=R.S_LIMIT, nominal="ms030_measured_spliced_d0 (crossover measured on it)",
                  measured_members=names_s, model_members=names_m,
                  description="max|S| <= 2 on every member with the DF controller; model members also Nyquist stable. Measured members: "
                              "Hl for f >= 70 Hz (lines up to 2499 Hz, design model above), frictionless design model on a dense log grid "
                              "0.5..70 Hz; extra delay 0 and +1 sample. Model members: design model (both amplitudes' fits) and the "
                              "ms030 model with jl x{0.8,1.2} and k x{0.8,1.2}, dense grid 0.5..3990 Hz, extra delay 0 and +1.",
                  grid_points=dict(S=len(S[0]), M=len(M[0]))),
        time_domain=dict(model="design model of ms030 (frictionless)", delay_samples=delay, current_limit_a=CURRENT_LIMIT,
                         encoder_counts_per_rev=ENC_COUNTS, friction_coulomb_a=FRICTION_A, friction_static_a=STICTION_A, friction_tanh_rad_s=FRICTION_V0,
                         stribeck_velocity_rad_s=STRIBECK_V, feedforward="u += Fc*tanh(v_ref/0.05) + 1e-4*a_ref, Fc = 0.10 A",
                         sample_time_s=TS),
        bounds={k: list(v) for k, v in R.SWEEP_BOUNDS.items()}, seed=args.seed, designs=recs, runtime_s=time.time() - t0)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "hw_design.json").write_text(json.dumps(R.jsonable(res), indent=1, allow_nan=False) + "\n")
    for mode in ("linear", "both"):
        if f"{mode}_error_opt" in recs:
            (args.output / f"hw_design_{mode}.json").write_text(
                json.dumps(R.jsonable(exp05_design(recs[f"{mode}_error_opt"], mode)), indent=2, allow_nan=False) + "\n")
    plot(args.output / "hw_design.png", fits, Ds, recs, ge_f, names_s)
    log("saved", args.output)


def fmt_full(p):
    return {k: float(v) for k, v in p.items()}


if __name__ == "__main__":
    main()
