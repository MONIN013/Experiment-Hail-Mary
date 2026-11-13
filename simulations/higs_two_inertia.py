#!/usr/bin/env python3
"""Reproduce HIGS design using the identified legacy two-inertia response.

Python: numpy, scipy, matplotlib. C++: g++ (or set CXX). No MATLAB/TwinCAT needed.
The shared library is temporary; ControllerAlgorithm.cpp is compiled unmodified.
"""
from __future__ import annotations
import argparse
import ctypes
import hashlib
import itertools
import json
import os
from pathlib import Path
import subprocess
import tempfile

import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[1]
TS = 1 / 8000
IDENTIFIED = json.loads((ROOT / "simulations/data/identified_plant.json").read_text())


def normalized_model(p):
    # Kt=1 is a normalization. These are effective parameters divided by Kt,
    # not independently measured physical inertia, stiffness or damping.
    return dict(jm=p["jm"], jl=p["jl"], bm=p["bm"], bl=p["bl"],
                stiffness=p["ks"], damping=p["cs"], torque_constant=p["kt"])


NOMINAL = normalized_model(IDENTIFIED["parameters"])
RESONANCE_BAND_HZ = (250., 380.)


def measured_response():
    data = np.load(ROOT / "simulations/data/measured_frf.npz")
    f = data["freq_hz"]
    source_ts = float(data["source_Ts"])
    # Approximate held-input correction for OFFLINE design only; assumes no
    # important aliases and unchanged acquisition alignment/current dynamics.
    # Keep the source data's 16 kHz metadata. MATLAB requires fresh 8 kHz data.
    correction = np.sinc(f*TS)/np.sinc(f*source_ts) * np.exp(-1j*np.pi*f*(TS-source_ts))
    return f, data["H_load"]*correction, data["period_load"]*correction, source_ts


class Host:
    def __init__(self):
        self.directory = tempfile.TemporaryDirectory(prefix="higs-host-")
        library = Path(self.directory.name) / "higs_host.so"
        subprocess.run([os.environ.get("CXX", "g++"), "-std=c++17", "-O2", "-shared", "-fPIC",
                        "-Wall", "-Wextra", "-Werror", "-I" + str(ROOT / "ControllerCore"),
                        str(ROOT / "ControllerCore/ControllerAlgorithm.cpp"),
                        str(ROOT / "simulations/higs_host.cpp"), "-o", str(library)], check=True)
        self.library = ctypes.CDLL(str(library))
        self.function = self.library.simulate_higs
        pointer = np.ctypeslib.ndpointer(dtype=np.float64, flags="C_CONTIGUOUS")
        self.function.argtypes = [ctypes.c_int] + [pointer] * 6 + [ctypes.c_uint, ctypes.c_int,
            ctypes.c_double, ctypes.c_double, ctypes.c_uint, ctypes.c_int,
            ctypes.c_double, ctypes.c_double, ctypes.c_double, pointer, pointer]
        self.function.restype = ctypes.c_int

    def run(self, design, reference, disturbance=None, *, model=None, delay=2,
            quantized=True, noise=None, initial=None, current_limit=0.08, method="zoh",
            encoder_counts=8388608):
        n = len(reference)
        a, b = plant_matrices(model or NOMINAL, method=method)
        sos = np.asarray(design["sos"], dtype=float)
        coeff = np.ascontiguousarray(sos[:, [0, 1, 2, 4, 5]])
        output = np.zeros((n, 11))
        code = self.function(n, np.ascontiguousarray(reference, dtype=float),
            np.ascontiguousarray(disturbance if disturbance is not None else np.zeros(n), dtype=float),
            np.ascontiguousarray(noise if noise is not None else np.zeros(n), dtype=float),
            np.ascontiguousarray(a), np.ascontiguousarray(b.ravel()), coeff, len(sos),
            int(design.get("higs_enabled", False)), design.get("higs_gain", 1.),
            design.get("higs_omega_ts", 0.), design.get("higs_pre_section_count", 0), delay,
            current_limit, 0.0016 if quantized else 0., 2*np.pi/encoder_counts if quantized else 0.,
            np.ascontiguousarray(initial if initial is not None else np.zeros(4), dtype=float), output)
        if code:
            raise RuntimeError(f"Controller rejected parameters or plant diverged at sample {code}")
        return output


def plant_matrices(p, sample_time=TS, method="zoh"):
    jm, jl, bm, bl, k, c, kt = (p[x] for x in NOMINAL)
    a = np.array([[0, 1, 0, 0], [-k/jm, -(bm+c)/jm, k/jm, c/jm],
                  [0, 0, 0, 1], [k/jl, c/jl, -k/jl, -(bl+c)/jl]])
    b = np.array([[0], [kt/jm], [0], [0]])
    if method == "semi_implicit":
        # Same velocity-first Euler update as VirtualMotorAlgorithm.cpp.
        ad = np.eye(4)
        ad[[1, 3], :] += sample_time*a[[1, 3], :]
        ad[0, :] += sample_time*ad[1, :]
        ad[2, :] += sample_time*ad[3, :]
        bd = sample_time*b
        bd[0, :] = sample_time*bd[1, :]
        bd[2, :] = sample_time*bd[3, :]
    else:
        ad, bd, _, _, _ = signal.cont2discrete((a, b, np.eye(4), np.zeros((4, 1))), sample_time)
    return ad, bd


def section(num, den):
    b, a = signal.bilinear(num, den, fs=1/TS)
    return np.r_[np.pad(b, (0, 3-len(b))), np.pad(a, (0, 3-len(a)))]


def make_design(crossover_hz=8., lowpass_hz=100., shaping_hz=0., gain_scale=1., lead_ratio=3., higs_corner_hz=20.):
    wi, wz, wp, wl = 2*np.pi*np.array([2., crossover_hz/lead_ratio, crossover_hz*lead_ratio, lowpass_hz])
    wc = wl if higs_corner_hz is None else 2*np.pi*higs_corner_hz
    pi = section([1, wi], [1, 0])
    lead = section([wp/wz, wp], [1, wp])
    lp = section([wl*wl], [1, np.sqrt(2)*wl, wl*wl])
    v = section([wl*wl/wc, wl*wl], [1, np.sqrt(2)*wl, wl*wl])
    _, lti = signal.sosfreqz(np.vstack([pi, lead, lp]), worN=[2*np.pi*crossover_hz*TS])
    f, measured, _, _ = measured_response()
    magnitude = np.interp(crossover_hz, f, abs(measured))
    kp = gain_scale / (abs(lti[0])*magnitude)
    pi[:3] *= kp
    baseline = {"sos": np.vstack([pi, lead, lp]), "sample_time_s": TS}
    if shaping_hz > 0:
        ww = 2*np.pi*shaping_hz
        w = section([ww], [1, ww])
        # W^-1 V is proper (the two-pole target LPF supplies the relative degree).
        v = section(np.convolve([1, ww], [wl*wl/wc, wl*wl])/ww,
                    [1, np.sqrt(2)*wl, wl*wl])
        higs_sos = np.vstack([w, v, pi, lead])
        pre = 1
    else:
        higs_sos = np.vstack([v, pi, lead])
        pre = 0
    higs = {"sos": higs_sos, "sample_time_s": TS, "higs_enabled": True,
            "higs_gain": 1., "higs_omega_ts": wc*TS/np.sqrt(1+16/np.pi**2),
            "higs_pre_section_count": pre}
    return baseline, higs, dict(kp=kp, integral_hz=2., lead_zero_hz=crossover_hz/lead_ratio,
                lead_pole_hz=crossover_hz*lead_ratio, lowpass_hz=lowpass_hz,
                shaping_hz=shaping_hz, higs_corner_hz=wc/(2*np.pi), measured_crossover_target_hz=crossover_hz,
                gain_basis="Legacy measured load FRF with approximate hold correction")


def reference_profile(amplitude=.1, move=.1, dwell=.2, settle=.4):
    durations = np.rint(np.array([settle, move, dwell, move, settle])/TS).astype(int)
    q = np.arange(durations[1])/durations[1]
    smooth = 35*q**4 - 84*q**5 + 70*q**6 - 20*q**7
    return np.concatenate([np.zeros(durations[0]), amplitude*smooth,
        np.full(durations[2], amplitude), amplitude*(1-smooth), np.zeros(durations[4]+1)])


def metrics(reference, output, disturbance=None):
    e = reference-output[:, 2]
    tail = min(len(e), round(.2/TS))
    demand = output[:, 4] + (disturbance if disturbance is not None else 0.)
    frequency = np.fft.rfftfreq(len(e), TS)
    band = (frequency >= RESONANCE_BAND_HZ[0]) & (frequency <= RESONANCE_BAND_HZ[1])
    def band_rms(x):
        # Rectangular full-record DFT; this is a diagnostic, not a stationary PSD estimate.
        spectrum = np.fft.rfft(x)/len(x)
        return float(np.sqrt(2*np.sum(abs(spectrum[band])**2)))
    return dict(rms_rad=float(np.sqrt(np.mean(e*e))), peak_error_rad=float(max(abs(e))),
                final_rms_rad=float(np.sqrt(np.mean(e[-tail:]**2))),
                peak_feedback_a=float(max(abs(output[:, 4]))),
                peak_demand_a=float(max(abs(demand))), peak_applied_a=float(max(abs(output[:, 5]))),
                rms_applied_a=float(np.sqrt(np.mean(output[:, 5]**2))),
                peak_speed_rad_s=float(np.max(abs(output[:, [1, 3]]))),
                peak_position_rad=float(np.max(abs(output[:, [0, 2]]))),
                peak_twist_rad=float(max(abs(output[:, 0]-output[:, 2]))),
                resonance_current_rms_a=band_rms(output[:, 5]),
                resonance_twist_rms_rad=band_rms(output[:, 0]-output[:, 2]),
                clipped_samples=int(output[:, 10].sum()),
                mode_fraction={str(i):float(np.mean(output[:,9] == i)) for i in range(4)})


def linear_metrics(design, delay=2, model=None, method="zoh"):
    a, b = plant_matrices(model or NOMINAL, method=method)
    freq = np.geomspace(.01, 3999, 6000)
    z = np.exp(2j*np.pi*freq*TS)
    plant = np.linalg.solve(z[:, None, None]*np.eye(4)-a, np.broadcast_to(b, (len(freq),4,1)))[:,2,0]
    _, controller = signal.sosfreqz(np.asarray(design["sos"]), worN=2*np.pi*freq*TS)
    loop = plant*controller/z**delay
    sos = np.asarray(design["sos"])
    # Build the actual DF-II/plant/delay state transition; a small |S| alone
    # does not imply stability (an unstable loop can have a small FRF magnitude).
    size = 4 + 2*len(sos) + delay
    def advance(state):
        next_state = np.zeros(size)
        u = -state[2]
        for j, row in enumerate(sos):
            at = 4+2*j
            y = row[0]*u + state[at]
            next_state[at] = row[1]*u - row[4]*y + state[at+1]
            next_state[at+1] = row[2]*u - row[5]*y
            u = y
        applied = state[-delay] if delay else u
        next_state[:4] = a @ state[:4] + b[:, 0]*applied
        if delay:
            next_state[-delay:] = np.r_[state[-delay+1:] if delay > 1 else [], u]
        return next_state
    transition = np.column_stack([advance(row) for row in np.eye(size)])
    radius = float(max(abs(np.linalg.eigvals(transition))))
    return dict(peak_sensitivity=float(max(abs(1/(1+loop)))), spectral_radius=radius,
                stable=radius < 1., freq=freq, loop=loop)


def measured_linear_metrics(design):
    f, response, periods, source_ts = measured_response()
    keep = (f >= 1.) & (f <= 1000.)
    f, response, periods = f[keep], response[keep], periods[:, keep]
    _, controller = signal.sosfreqz(np.asarray(design["sos"]), worN=2*np.pi*f*TS)
    sensitivity = abs(1/(1+controller*response))
    # Six additional 8 kHz samples cover an unmeasured increase in new-target
    # timing. This is a design stress case, not a latency identification.
    extra_delay = np.exp(-2j*np.pi*f*6*TS)
    return dict(source_sample_time_s=source_ts,controller_sample_time_s=TS,
                band_hz=[float(f[0]),float(f[-1])],
                peak_sensitivity=float(max(sensitivity)),
                peak_frequency_hz=float(f[np.argmax(sensitivity)]),
                worst_period_sensitivity=float(np.max(abs(1/(1+controller*periods)))),
                extra_delay_s=6*TS,
                worst_period_with_extra_delay=float(np.max(abs(1/(1+controller*periods*extra_delay)))),
                note="Sampled legacy FRF with approximate ZOH correction; not an 8 kHz measurement or stability proof.")


def within_envelope(m):
    return (m["clipped_samples"] == 0 and m["peak_demand_a"] < .08 and
            m["peak_position_rad"] < .25 and m["peak_speed_rad_s"] < 10. and
            m["peak_twist_rad"] < .01)


def save_json(path, value):
    def convert(x):
        if isinstance(x, np.ndarray): return x.tolist()
        if isinstance(x, np.generic): return x.item()
        raise TypeError(type(x).__name__)
    path.write_text(json.dumps(value, indent=2, default=convert, allow_nan=False)+"\n")


def frequency_sweep(host, designs):
    resonance = IDENTIFIED["parameters"]["resonance_damped_Hz"]
    frequencies = np.unique(np.r_[np.geomspace(1, 600, 48), (resonance+np.array([-10,0,10]))/3])
    out = {name:[] for name in designs}
    for requested in frequencies:
        samples_per_period = round(1/(TS*requested))
        frequency = 1/(TS*samples_per_period)
        periods = max(16, int(np.ceil(2*frequency)))
        t = np.arange(periods*samples_per_period)*TS
        r = .01*np.sin(2*np.pi*frequency*t)
        count = 8*samples_per_period
        basis = np.exp(-2j*np.pi*frequency*t[-count:])
        for name, design in designs.items():
            trace = host.run(design, r, delay=2, quantized=False)
            error = r[-count:]-trace[-count:,2]
            fundamental = abs(2*np.mean(error*basis))/.01
            total = np.sqrt(np.mean(error**2))/(.01/np.sqrt(2))
            out[name].append(dict(hz=frequency, fundamental=float(fundamental), total_rms=float(total),
                                 clipped_samples=int(trace[:,10].sum())))
    return out


def plot_results(directory, reference, traces, summary, sweep):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    colors = {"linear":"#667085", "higs":"#147D92"}
    plt.rcParams.update({"font.size":10, "axes.spines.top":False, "axes.spines.right":False})
    t = np.arange(len(reference))*TS
    fig, axes = plt.subplots(3, 1, figsize=(9, 8), sharex=True, constrained_layout=True)
    axes[0].plot(t, reference, "k--", lw=1, label="Reference")
    for name, data in traces.items():
        axes[0].plot(t, data[:,2], color=colors[name], label=name.upper())
        axes[1].plot(t, (reference-data[:,2])*1000, color=colors[name])
        axes[2].plot(t, data[:,5]*1000, color=colors[name], alpha=.8)
    axes[0].set_ylabel("Load angle [rad]")
    axes[1].set_ylabel("Tracking error [mrad]")
    axes[2].set_ylabel("Plant input current [mA]")
    axes[2].set_xlabel("Time [s]")
    axes[0].legend(ncol=3)
    for ax in axes: ax.grid(alpha=.2)
    fig.suptitle("Identified two-inertia model: 8 kHz, 2-sample delay, quantized I/O")
    fig.savefig(directory/"tracking.png", dpi=170); plt.close(fig)

    fig, axes = plt.subplots(1,2,figsize=(11,5.5),constrained_layout=True)
    for name, values in sweep.items():
        f = [x["hz"] for x in values]
        axes[0].semilogx(f, 20*np.log10([x["fundamental"] for x in values]),
                        color=colors[name],label=name.upper()+" fundamental")
        if name == "higs":
            axes[0].semilogx(f,20*np.log10([x["total_rms"] for x in values]),
                            "--",color=colors[name],label="HIGS total RMS")
    axes[0].axhline(20*np.log10(2),color="#B54708",ls=":",label="6.02 dB reference")
    axes[0].set(xlabel="Reference frequency [Hz]",ylabel="Error / reference [dB]",
                title="Single-tone test, unquantized (not an H-infinity bound)")
    axes[0].legend(fontsize=8)
    cases = summary["cases"]
    selected = [x for x in cases if x["kind"] != "uncertainty"]
    ratios = [100*(1-x["higs"]["rms_rad"]/x["linear"]["rms_rad"]) for x in selected]
    axes[1].barh([x["name"] for x in selected], ratios,
                 color=["#147D92" if x>=0 else "#B54708" for x in ratios])
    axes[1].axvline(0,color="black",lw=.7)
    axes[1].set(xlabel="Error RMS reduction [%]",title="Separate validation conditions")
    for ax in axes: ax.grid(alpha=.2)
    fig.savefig(directory/"validation.png",dpi=170); plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT/"simulations/results")
    parser.add_argument("--write-design", action="store_true", help="Update the MATLAB experiment JSON")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    host = Host()
    baseline, higs, tuning = make_design()
    designs = dict(linear=baseline, higs=higs)
    design = dict(linear_sos=baseline["sos"],higs_sos=higs["sos"],
        pre_section_count=higs["higs_pre_section_count"],higs_gain=higs["higs_gain"],
        higs_omega_ts=higs["higs_omega_ts"],sample_time_s=TS,
        reference_amplitude_rad=.1,move_time_s=.1,dwell_time_s=.2,settle_time_s=.4,
        sensitivity_limit=2.,max_current_a=.08,max_position_rad=.25,
        max_velocity_rad_s=10.,max_twist_rad=.01,tuning=tuning,
        provenance="Legacy chirp_result.mat command-current/degree data, normalized 5-700 Hz fit; fresh 8 kHz identification required before use.",
        source_sha256=IDENTIFIED["source_sha256"])
    summary = dict(model=NOMINAL,design=design,cases=[],tuning_comparison=[],
        model_note=IDENTIFIED["normalization"],
        quantization_assumptions=dict(current_a=.0016,encoder_counts_per_rev=8388608,
            note="Current DriverAdapter defaults; actual hardware scaling must be checked."),
        resonance_band_hz=RESONANCE_BAND_HZ,
        controller_sha256=hashlib.sha256((ROOT/"ControllerCore/ControllerAlgorithm.cpp").read_bytes()).hexdigest())
    reference = reference_profile()
    nominal_traces = {}

    def evaluate(name, ref, disturbance=None, kind="validation", **options):
        options = {"delay":2, **options}
        record = dict(name=name,kind=kind,samples=len(ref),
                      options={k:v for k,v in options.items() if k!="noise"})
        for key, controller in designs.items():
            trace = host.run(controller, ref, disturbance, **options)
            record[key] = metrics(ref,trace,disturbance)
            record[key]["within_envelope"] = within_envelope(record[key])
            if name=="nominal": nominal_traces[key]=trace
        record["improvement_percent"] = 100*(1-record["higs"]["rms_rad"]/record["linear"]["rms_rad"])
        summary["cases"].append(record)
        return record

    evaluate("nominal",reference)
    evaluate("fast move",reference_profile(move=.05))
    evaluate("slow move",reference_profile(move=.2))
    evaluate("small 0.001 rad",reference_profile(amplitude=.001))
    evaluate("large 0.2 rad",reference_profile(amplitude=.2))
    evaluate("no quantization",reference,quantized=False)
    evaluate("semi-implicit Euler",reference,method="semi_implicit")
    evaluate("legacy 20-bit encoder",reference,encoder_counts=1048576)
    evaluate("delay 1 sample",reference,delay=1)
    evaluate("delay 4 samples",reference,delay=4)
    evaluate("delay 8 samples",reference,delay=8)
    evaluate("encoder noise",reference,noise=np.random.default_rng(728).normal(0,10*2*np.pi/8388608,len(reference)))
    t = np.arange(round(6/TS))*TS
    multi = .02*np.sin(2*np.pi*3*t)+.01*np.sin(2*np.pi*11*t)+.004*np.sin(2*np.pi*37*t)
    evaluate("multisine reference",multi)
    disturbance = .005*np.sin(2*np.pi*3*t)+.002*np.sin(2*np.pi*313*t)
    evaluate("two-tone disturbance",np.zeros_like(t),disturbance)
    evaluate("DC on/off",np.zeros_like(t),.005*((t>.5)&(t<3.5)))
    evaluate("initial displacement",np.zeros_like(t),initial=[.005,0,.005,0])
    for name, parameters in IDENTIFIED["fit_band_variants"].items():
        evaluate("fit "+name,reference,model=normalized_model(parameters))

    stability = linear_metrics(baseline)
    summary["linear_reference"] = {k:v for k,v in stability.items() if k not in ("freq","loop")}
    summary["measured_linear_reference"] = measured_linear_metrics(baseline)
    summary["worst_linear_sensitivity"] = stability["peak_sensitivity"]
    variant_checks = [linear_metrics(baseline,method="semi_implicit")]
    for parameters in IDENTIFIED["fit_band_variants"].values():
        variant_checks.append(linear_metrics(baseline,model=normalized_model(parameters)))
    summary["model_variant_linear_checks"] = [
        {k:v for k,v in x.items() if k not in ("freq","loop")} for x in variant_checks]
    summary["worst_linear_sensitivity"] = max(summary["worst_linear_sensitivity"],
        max(x["peak_sensitivity"] for x in variant_checks))
    uncertainty_models = []
    for jm,jl,k,c,b,delay in itertools.product([.8,1.2],[.8,1.2],[.8,1.2],[.5,1.5],[.5,1.5],[1,4,8]):
        model = NOMINAL | dict(jm=NOMINAL["jm"]*jm,jl=NOMINAL["jl"]*jl,
            stiffness=NOMINAL["stiffness"]*k,damping=NOMINAL["damping"]*c,
            bm=NOMINAL["bm"]*b,bl=NOMINAL["bl"]*b)
        rec = evaluate(f"Jm{jm}_Jl{jl}_K{k}_C{c}_B{b}_d{delay}",reference,
                       kind="uncertainty",model=model,delay=delay)
        linear = linear_metrics(baseline,delay,model)
        rec["linear_stable"] = linear["stable"]
        rec["linear_sensitivity"] = linear["peak_sensitivity"]
        summary["worst_linear_sensitivity"] = max(summary["worst_linear_sensitivity"],linear["peak_sensitivity"])
        uncertainty_models.append((model,delay))
    # Report why more aggressive linear starting points were not selected.
    # These are finite stress cases, not a robust-stability certificate.
    summary["bandwidth_comparison"] = []
    for crossover, ratio in [(8.,3.),(10.,3.),(15.,5.),(20.,5.)]:
        candidate, _, _ = make_design(crossover_hz=crossover,lead_ratio=ratio)
        worst = max(linear_metrics(candidate,delay,model)["peak_sensitivity"]
                    for model,delay in uncertainty_models)
        measured = measured_linear_metrics(candidate)
        summary["bandwidth_comparison"].append(dict(crossover_hz=crossover,lead_ratio=ratio,
            worst_model_sensitivity=worst,
            worst_measured_period_with_extra_delay=measured["worst_period_with_extra_delay"]))
    for corner, shaping in itertools.product([1.,5.,10.,20.,60.],[0.,20.]):
        _, candidate, _ = make_design(shaping_hz=shaping,higs_corner_hz=corner)
        trace = host.run(candidate,reference,delay=2)
        metric = metrics(reference,trace)
        summary["tuning_comparison"].append(dict(corner_hz=corner,shaping_hz=shaping,
            metrics=metric,within_envelope=within_envelope(metric)))
    uncertainties = [x for x in summary["cases"] if x["kind"]=="uncertainty"]
    summary["uncertainty_count"] = len(uncertainties)
    summary["uncertainty_improvement_range_percent"] = [
        min(x["improvement_percent"] for x in uncertainties),max(x["improvement_percent"] for x in uncertainties)]
    summary["envelope_pass"] = all(x[k]["within_envelope"] for x in summary["cases"] for k in designs)
    summary["linear_stability_pass"] = (stability["stable"] and all(x["linear_stable"] for x in uncertainties)
                                        and all(x["stable"] for x in variant_checks))
    summary["linear_sensitivity_pass"] = (summary["worst_linear_sensitivity"] <= design["sensitivity_limit"] and
        summary["measured_linear_reference"]["worst_period_with_extra_delay"] <= design["sensitivity_limit"])
    print(json.dumps({k:summary[k] for k in ("uncertainty_count","uncertainty_improvement_range_percent",
          "worst_linear_sensitivity","envelope_pass","linear_stability_pass","linear_sensitivity_pass")}),flush=True)
    sweep = frequency_sweep(host,designs)
    summary["single_tone_sweep"] = sweep
    save_json(args.output/"summary.json",summary)
    plot_results(args.output,reference,nominal_traces,summary,sweep)
    if not (summary["envelope_pass"] and summary["linear_stability_pass"] and summary["linear_sensitivity_pass"]):
        raise SystemExit("A validation case violated the motion/current, linear stability or sensitivity gate.")
    if any(x["clipped_samples"] for values in sweep.values() for x in values):
        raise SystemExit("Single-tone validation was current-limited; do not interpret it as an unsaturated response.")
    # Export an experiment bank only after every selected validation gate passes.
    if args.write_design: save_json(ROOT/"simulations/higs_design.json", design)
    print(f"Saved reproducible results to {args.output}",flush=True)


if __name__ == "__main__":
    main()
