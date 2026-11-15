#!/usr/bin/env python3
"""Chapter-8 bandwidth design and offline evaluation; no hardware.

Uses the coherence-qualified in-motion composite plant and separate sup norms in (8.13), finite-band
DF Nyquist, p198 separation and measured standstill command noise <=10mA.
Wi is tuned in case-b closed-loop replay for <=20Hz error with no saturation.
Run: python simulations/higs_book_design.py --iterations 90 --starts 8 --workers 4
Re-evaluate saved designs: python simulations/higs_book_design.py --evaluate
Dependencies: numpy, scipy, numba; Windows MSVC for the unmodified host.
"""
from __future__ import annotations
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ProcessPoolExecutor

ROOT = Path(__file__).resolve().parents[1]
_WORK = tempfile.TemporaryDirectory(prefix="higs_book_design_", ignore_cleanup_errors=True)
WORK = Path(_WORK.name)
os.environ.setdefault("NUMBA_CACHE_DIR", str(WORK / "numba"))
os.environ["TEMP"] = os.environ["TMP"] = str(WORK)
import numba as nb
import numpy as np
import scipy
from scipy import signal
from scipy.io import loadmat
from scipy.optimize import differential_evolution, minimize, least_squares

TS = 62.5e-6
FS = 1 / TS
SQ = np.sqrt(1 + 16 / np.pi**2)
TRAJECTORIES = ("a002m005", "a01m010", "a10m010", "r5m100", "r5m050")
OUT = ROOT / "simulations/hardware/designs"
MODEL = {}
DELAY = 0
MODEL_SOURCE = "E4: fixed FF rigid body plus measured in-motion resonance fit"
PLANT = {}
MS100 = {}


def encode(v):
    if isinstance(v,np.ndarray): return v.tolist()
    if isinstance(v,np.generic): return v.item()
    raise TypeError(type(v).__name__)

def save(path,value):
    Path(path).write_text(json.dumps(value,default=encode,indent=2,allow_nan=False)+"\n",encoding="utf-8")

def mismatch(predicted, measured):
    ratio = predicted / measured
    db, phase = 20*np.log10(abs(ratio)), np.degrees(np.angle(ratio))
    return dict(lines=len(ratio), median_db=float(np.median(db)), max_abs_db=float(np.max(abs(db))),
                median_phase_deg=float(np.median(phase)), max_abs_phase_deg=float(np.max(abs(phase))))


def rigid_response(f, j, b, delay=0.):
    s=2j*np.pi*np.asarray(f)
    return np.exp(-s*delay)/(j*s*s+b*s)


def two_inertia_response(f, model, delay=0.):
    s=2j*np.pi*np.asarray(f);jm,jl,b,k,c=[model[x] for x in ("jm","jl","bm","stiffness","damping")]
    return (c*s+k)/(jm*jl*s**4+((jm+jl)*c+jl*b)*s**3+((jm+jl)*k+b*c)*s*s+b*k*s)*np.exp(-s*delay)


def sampled_two_inertia_response(f,model,delay_samples):
    jm,jl,k,c,b=[model[x] for x in ("jm","jl","stiffness","damping","bm")]
    a=np.array([[0,1,0,0],[-k/jm,-(c+b)/jm,k/jm,c/jm],
                [0,0,0,1],[k/jl,c/jl,-k/jl,-c/jl]])
    bd=np.array([[0.],[1/jm],[0.],[0.]])
    ad,bd,*_=signal.cont2discrete((a,bd,np.eye(4),np.zeros((4,1))),TS)
    z=np.exp(2j*np.pi*np.asarray(f)*TS)
    return np.array([np.linalg.solve(zz*np.eye(4)-ad,bd[:,0])[2]*zz**(-delay_samples) for zz in z])


def load_frfs():
    """One design plant; ms100 is retained strictly for informational checks."""
    global MODEL,DELAY,PLANT,MS100
    source=ROOT/"simulations/hardware/frf/inmotion_ramp.npz"
    d=np.load(source);f=d["f"];p=d["linear_P"];coh=d["linear_coherence"]
    if np.any(np.diff(f)<=0) or not np.all(np.isfinite(p)) or not np.all(np.isfinite(coh)):
        raise ValueError("Invalid in-motion FRF")
    accepted=(f>=20)&(f<=400)&(coh>=.8)
    low=(f>=20)&(f<=50)&(coh>=.8)
    j,b,delay=1.134e-4,3.45e-4,0.
    original=mismatch(rigid_response(f[low],j,b),p[low]);fit=None
    if original["max_abs_db"]>3 or original["max_abs_phase_deg"]>20:
        use=(f>=20)&(f<=100)&(coh>=.8)
        def residual(q):
            ratio=rigid_response(f[use],np.exp(q[0]),np.exp(q[1]),q[2])/p[use]
            return np.r_[np.log(abs(ratio)),np.angle(ratio)]
        result=least_squares(residual,[np.log(j),np.log(b),0.],bounds=([np.log(1e-6),np.log(1e-8),0.],[np.log(.01),np.log(.1),.01]))
        j,b,delay=np.exp(result.x[0]),np.exp(result.x[1]),result.x[2]
        fit=dict(J=j,B=b,delay_s=delay,fit_band_hz=[20,100],mismatch=mismatch(rigid_response(f[use],j,b,delay),p[use]),
                 jacobian_condition_number=float(np.linalg.cond(result.jac)))
    low_f=np.geomspace(.1,19.999,120)
    high_f,high_p=d["ms100_f"],d["ms100_P"];high=high_f>400
    ff=np.r_[low_f,f[accepted],high_f[high]]
    pp=np.r_[rigid_response(low_f,j,b,delay),p[accepted],high_p[high]]
    MS100=dict(f=high_f,p=high_p,source_sha256=hashlib.sha256((ROOT/"simulations/hardware/frf/frf_ms100.mat").read_bytes()).hexdigest())
    # Preserve the FF rigid body and existing inertia split; fit only the
    # measured elastic mode and positive transport delay at100..400Hz.
    use=accepted&(f>=100)
    def physical(q):
        fr,zeta,tau=q;split=5.066/(5.066+3.982);jm,jl=j*split,j*(1-split);w=2*np.pi*fr
        return dict(jm=jm,jl=jl,bm=b,bl=0.,stiffness=w*w*jm*jl/j,damping=2*zeta*w*jm*jl/j,torque_constant=1.),tau
    def residual(q):
        model,tau=physical(q);ratio=two_inertia_response(f[use],model,tau)/p[use]
        return np.r_[np.log(abs(ratio)),np.angle(ratio)]
    fit_result=least_squares(residual,[313.,.015,.0002],bounds=([290.,.001,0.],[340.,.2,.001]),ftol=1e-11,xtol=1e-11,gtol=1e-11)
    MODEL,tau=physical(fit_result.x);DELAY=int(round(tau/TS))
    model_record=dict(parameters=MODEL,fit_band_hz=[100,400],delay_fit_s=tau,delay_samples=DELAY,
        delay_rounded_s=DELAY*TS,delay_rounding_error_s=DELAY*TS-tau,
        delay_rounding_max_phase_error_deg=float(360*400*abs(DELAY*TS-tau)),
        mass_split_identifiable=False,mass_split_source="Existing ms060 fit jm=5.066e-5,jl=3.982e-5; preserve ratio and scale total to FF J",jacobian_condition_number=float(np.linalg.cond(fit_result.jac)),
        note="Load-position FRF does not identify mass split; existing split is fixed and total J/B retained. Twist prediction depends on this split.",
        mismatch_100_400=mismatch(two_inertia_response(f[use],MODEL,DELAY*TS),p[use]),
        mismatch_100_400_unrounded_delay=mismatch(two_inertia_response(f[use],MODEL,tau),p[use]),
        mismatch_280_340=mismatch(two_inertia_response(f[accepted&(f>=280)&(f<=340)],MODEL,DELAY*TS),p[accepted&(f>=280)&(f<=340)]),
        mismatch_20_100=mismatch(two_inertia_response(f[accepted&(f<=100)],MODEL,DELAY*TS),p[accepted&(f<=100)]))
    model_record["sampled_response_definition"]="C(zI-Ad)^-1 Bd z^-DELAY, exact ZOH atTs; C=[0,0,1,0]; moving Coulomb increment zero; includes sample/hold phase"
    for lo,hi,label in ((20,100,"20_100"),(100,400,"100_400"),(280,340,"280_340")):
        selected=accepted&(f>=lo)&(f<=hi)
        model_record["sampled_mismatch_"+label]=mismatch(sampled_two_inertia_response(f[selected],MODEL,DELAY),p[selected])
    PLANT=dict(source=str(source.relative_to(ROOT)).replace("\\","/"),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        definition="Below20Hz FF rigid body; 20..400Hz linear ramp FRF at coherence>=.8 only; above400Hz standstill ms100",
        accepted_inmotion_lines=int(accepted.sum()),accepted_inmotion_range_hz=[float(f[accepted][0]),float(f[accepted][-1])],
        excluded_inmotion_lines=int(((f>=20)&(f<=400)&~accepted).sum()),coherence_min=.8,
        low_frequency_model=dict(J=j,B=b,delay_s=delay,original_ff_mismatch_20_50=original,refit=fit,
            mismatch_sign="model / measured; phase wrapped to [-180,180] degrees",threshold_rule="maximum absolute mismatch over coherence-qualified 20..50Hz lines: >3dB or >20deg"),
        transition="No accepted lines at20..29Hz; first accepted31Hz; constraints use only stated lines and log-frequency crossover interpolation between adjacent samples, including19.999..31Hz gap",
        constraint_grid_min_hz=.1,constraint_grid_max_hz=float(ff[-1]),simulation_fit=model_record)
    # Windows spawn copies the main-module dictionary; keep the host module view in sync.
    module=sys.modules[__name__];module.MODEL=MODEL;module.DELAY=DELAY
    return {"design":dict(f=ff,p=pp,source_sha256=PLANT["source_sha256"])}


def load_trials():
    result=[]
    for path in sorted((ROOT/"simulations/hardware/trials_book").glob("*.mat")):
        if not any(path.name.startswith(x+"_") for x in TRAJECTORIES): continue
        d=loadmat(path,simplify_cells=True)
        r,ff=np.asarray(d["REF"],float),np.asarray(d["FF"],float)
        v=np.gradient(r)/TS; a=np.gradient(v)/TS
        formula=.1*np.tanh(v/.05)+1e-4*a
        residual=float(np.max(abs(formula-ff)))
        e=np.asarray(d["raw"]["error"],float)
        if residual>1e-9 or not np.all(np.isfinite(np.r_[r,ff,e])):
            raise ValueError(f"Invalid trial / mismatched logged FF: {path}, {residual}")
        result.append(dict(name=path.stem,trajectory=path.stem.split("_")[0],reference=r,ff=formula,error=e,
                           motion=abs(v)>max(1e-8,.01*np.max(abs(v))),ff_residual_a=residual,
                           source_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    if set(t["trajectory"] for t in result)!=set(TRAJECTORIES): raise ValueError("Missing logged reference")
    return result

@nb.njit(cache=True)
def discrete_df(ff,hh):
    """Sampled HIGS fundamental, LS sine/cosine/DC including noninteger periods.

    >=768 samples above fs/4 resolve sample-phase effects without 1/f HF
    extrapolation. This is (2.43-44), kh=1, not the continuous-time DF.
    """
    out=np.empty((len(hh),len(ff)),np.complex128)
    for j in range(len(ff)):
        n=max(768,int(np.ceil(16*FS/ff[j])))
        skip=max(256,int(np.ceil(6*FS/ff[j])))
        gram=np.zeros((3,3));rhs=np.zeros((len(hh),3));state=np.zeros(len(hh));prev=0.
        for k in range(n):
            th=2*np.pi*ff[j]*k/FS+.317
            x=np.sin(th);v=np.array([x,np.cos(th),1.])
            if k>=skip: gram+=np.outer(v,v)
            for i in range(len(hh)):
                cand=state[i]+2*np.pi*hh[i]*TS*x
                inside=(0<=cand<=x) if x>=0 else (x<=cand<=0)
                same=(x>=0 and prev>=0) or (x<=0 and prev<=0)
                y=cand if inside else (x if same else 0.)
                state[i]=y
                if k>=skip: rhs[i]+=y*v
            prev=x
        for i in range(len(hh)):
            b=np.linalg.solve(gram,rhs[i]);out[i,j]=b[0]+1j*b[1]
    return out


def band_rms(x,low,high):
    spec=np.fft.rfft(x);f=np.fft.rfftfreq(len(x),TS);use=(f>low)&(f<=high)
    weights=np.full(len(f),2.);weights[0]=1.
    if len(x)%2==0: weights[-1]=1.
    return float(np.sqrt(np.sum(abs(spec[use])**2*weights[use]))/len(x))


def spectrum(x,mask):
    edges=np.flatnonzero(np.diff(np.r_[False,mask,False]));f=np.arange(0,FS/2+1,1.);power=np.zeros(len(f));weight=0;dc_energy=0.;raw_energy=0.
    for lo,hi in zip(edges[::2],edges[1::2]):
        xx=x[lo:hi]
        if len(xx)<32: continue
        dc_energy+=len(xx)*float(np.mean(xx))**2;raw_energy+=float(np.sum(xx*xx))
        ff,pp=signal.periodogram(xx,fs=FS,window="hann",nfft=max(16000,len(xx)),detrend=False,scaling="density")
        power+=np.interp(f,ff,pp)*len(xx);weight+=len(xx)
    if weight: power/=weight
    bands=np.r_[0,4,8,16,32,64,128,256,512,1024,2048,4000,8001]
    energy=np.array([np.sum(power[(f>=lo)&(f<hi)]) for lo,hi in zip(bands[:-1],bands[1:])]);j=int(np.argmax(energy))
    return dict(f=f,power=power,bands_hz=bands,energy=energy,dominant_band_hz=[float(bands[j]),float(bands[j+1])],peak_hz=float(f[1+np.argmax(power[1:])]),
                motion_interval_dc_energy_fraction=dc_energy/max(1e-300,raw_energy))


def input_spectra(host,t,trials,mode="both"):
    d=loaded_controller(t,mode);lp=[];ip=[];unweighted=[];details=[];max_lp_difference=0.;iderivative=[]
    for tr in trials:
        o=host.run(d,tr["error"],controller_only=True)
        max_lp_difference=max(max_lp_difference,float(np.max(abs(o[:,7]-tr["error"]))))
        l=spectrum(o[:,7],tr["motion"]);i=spectrum(o[:,11],tr["motion"])
        raw=signal.sosfilt(np.asarray(d["sos"])[1:2],o[:,8]);u=spectrum(raw,tr["motion"])
        lp.append(l["energy"]);ip.append(i["energy"]);unweighted.append(u["energy"])
        derivative=(2*np.pi*l["f"])**2*l["power"]
        dd=np.array([derivative[(l["f"]>=a)&(l["f"]<b)].sum() for a,b in zip(l["bands_hz"][:-1],l["bands_hz"][1:])])
        iv=(2*np.pi*i["f"])**2*i["power"]
        idd=np.array([iv[(i["f"]>=a)&(i["f"]<b)].sum() for a,b in zip(i["bands_hz"][:-1],i["bands_hz"][1:])]);iderivative.append(idd)
        command=o[:,4]+tr["ff"]
        details.append(dict(trial=tr["name"],controller_only_command_peak_a=float(np.max(abs(command))),
                            controller_only_command_hf_gt_1000hz_rms_a=band_rms(command,1000,FS/2),
                            controller_only_exceeds_2_71_a=bool(np.max(abs(command))>2.71),
                            lp_peak_hz=l["peak_hz"],lp_band_energy=l["energy"],i_peak_hz=i["peak_hz"],i_band_energy=i["energy"],
                            i_unweighted_band_energy=u["energy"],lp_derivative_band_energy=dd,i_derivative_band_energy=idd,motion_samples=int(tr["motion"].sum()),
                            lp_motion_dc_energy_fraction=l["motion_interval_dc_energy_fraction"],i_motion_dc_energy_fraction=i["motion_interval_dc_energy_fraction"]))
    bands=l["bands_hz"]
    normal=lambda a:np.mean(np.array(a)/np.maximum(1e-300,np.sum(a,axis=1))[:,None],axis=0)
    el,ei,eu=normal(lp),normal(ip),normal(unweighted);j=int(np.argmax(el))
    fmin=max(1.,float(np.sqrt(max(1.,bands[j])*bands[j+1])))
    ds=normal([r["lp_derivative_band_energy"] for r in details]);eligible=np.arange(len(ds))>j
    choices=np.flatnonzero(eligible&(ds>=.1));start=int(choices[0]) if len(choices) else int(np.argmax(np.where(eligible,ds,-1.)))
    return dict(omega_min_rad_s=2*np.pi*fmin,omega_start_rad_s=2*np.pi*bands[start],f_min_hz=fmin,f_start_hz=float(bands[start]),
        bands_hz=bands,lp_normalised_band_energy=el,i_normalised_band_energy=ei,
        i_unweighted_normalised_band_energy=eu,lp_derivative_normalised_band_energy=ds,i_derivative_normalised_band_energy=normal(iderivative),trials=details,
        lp_input_minus_logged_error_max_rad=max_lp_difference,
        controller_only_command_summary=dict(peak_a=max(r["controller_only_command_peak_a"] for r in details),
            hf_gt_1000hz_rms_max_a=max(r["controller_only_command_hf_gt_1000hz_rms_a"] for r in details),
            over_2_71_a_trials=[r["trial"] for r in details if r["controller_only_exceeds_2_71_a"]],
            interpretation="Logged-error controller-only replay plus the same logged FF; counterfactual command, not the new closed-loop tracking performance"),
        spectrum_detrend=False,
        replay_type="controller-only actual ControllerAlgorithm with A=B=0; reference input is each logged error; LP input equals error because lpPre has 0 sections",
        motion_rule="abs(gradient(reference)/Ts) > 1 percent of trajectory maximum (minimum 1e-8 rad/s)",
        selection_rule="equal trial weight; geometric centre of largest LP energy band gives fmin; first higher octave with >=10 percent derivative energy gives fstart; Wi is tuned separately by closed-loop case-b error")


def final_record(rec,mode,gate,spectra,host,trials):
    t=rec["tuning"];rec.pop("x",None);rec["constraint_record"]=gate.evaluate(t,mode,loaded=True)
    if not rec["constraint_record"]["passed"]: raise RuntimeError("Loaded-controller constraint failed")
    d=loaded_controller(t,mode);metrics=case_b_replays(host,t,mode,trials)
    own=input_spectra(host,t,trials,mode)
    own["proposed_selection"]={k:own[k] for k in ("f_min_hz","f_start_hz")}
    own.update(f_min_hz=gate.fmin,f_start_hz=gate.fstart,omega_min_rad_s=2*np.pi*gate.fmin,omega_start_rad_s=2*np.pi*gate.fstart,
               wi_pole_hz=t["wi_pole_hz"],wi_zero_hz=t["wi_zero_hz"])
    bw=rec["constraint_record"]["per_frf"]["design"]["bandwidth_hz"]
    rec["linear_counterpart_poles_zeros"]=controller_poles_zeros(t)
    rec["controller_filter_poles_zeros"]=controller_filter_poles_zeros(t,mode)
    rec.update(design_mode=mode,sample_time_s=TS,reference_amplitude_rad=.1,move_time_s=.1,dwell_time_s=.2,settle_time_s=.4,
        sensitivity_limit=2.,max_current_a=2.71,max_position_rad=.5,max_velocity_rad_s=5.,max_twist_rad=.05,bandwidth_hz=bw,omega_b_rad_s=2*np.pi*bw,
        loaded_controller=d,replay_spectra=own,weight_selection_spectra=spectra,offline_replays=metrics,
        offline_plant=dict(parameters=MODEL,source=MODEL_SOURCE,delay_samples=DELAY,discretisation="ZOH with 256 implicit Coulomb substeps per sample",friction=True,
            motor_coulomb_a=.116,motor_viscous_a_per_rad_s=MODEL["bm"],encoder_quantisation=False,
            current_limit_applied=True,current_limit_a=2.71,host="actual unmodified ControllerAlgorithm; scratch host extends only the offline plant with G case-b friction"),
        peak_command_trial=max((k for k in metrics if metrics[k]["completed"]),key=lambda k:metrics[k]["command_peak_a"],default=None),
        feedforward=dict(formula="inertia*a + coulomb_a*tanh(v/.05) + coulomb_slow_a*tanh(v/3) + viscous*v + quadratic*v*abs(v)",
            inertia=1.134e-4,coulomb_a=.068,coulomb_slow_a=.0625,viscous=.000345,quadratic=.0000541,derivative="gradient centred interior, one-sided endpoints"),
        provenance="true-notch fixed-bound independent bandwidth maximisation on coherence-qualified moving composite plant; separate sup norms; Wi tuned on case-b low-frequency error; no HIGS-win tuning",
        df_method="Search: log-interpolated sampled HIGS DF; final: direct sampled law at every measured line. LS sine/cosine/DC, phase=.317rad, n=max(768,ceil(16fs/f)), skip=max(256,ceil(6fs/f)); loaded unwarped-Tustin SOS for every LTI factor",
        source_sha256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in
                       (Path(__file__),ROOT/"ControllerCore/ControllerAlgorithm.cpp",ROOT/"ControllerCore/ControllerAlgorithm.h",ROOT/"simulations/higs_host.cpp")},
        execution_environment=dict(python=sys.version.split()[0],numpy=np.__version__,scipy=scipy.__version__,numba=nb.__version__,
            design_command="python simulations/higs_book_design.py --iterations "+str(rec["search"]["maxiter"])+" --starts "+str(rec["search"]["independent_starts"])+" --workers 4",
            evaluation_command="python simulations/higs_book_design.py --evaluate"),
        nyquist_assumptions="Composite .1..4999Hz with analytical rigid-body DC continuation; no RHP plant poles; rigid-body pole + controller integrator at DC; type-2 indentation; HF closure to zero inside unit disk; finite-grid DF Nyquist-type only",
        low_frequency_sensitivity=low_frequency_sensitivity(t,mode,gate),
        noise_replay=gate.noise.rms(t,mode,details=True),
        tustin_prewarp_hz=None,parameters_rad_s=dict(omega_i=2*np.pi*t["integral_hz"],omega_d=2*np.pi*t["lead_zero_hz"],omega_r=2*np.pi*4000,
            omega_lp=2*np.pi*t["lowpass_hz"],omega_h_lp=2*np.pi*t["higs_lp_corner_hz"]/SQ,omega_h_i=2*np.pi*t["higs_i_corner_hz"]/SQ))
    return rec


def low_frequency_sensitivity(t,mode,gate):
    f=np.array([5.,10.,20.]);c=controller_response(t,mode,f,gate.table,loaded=True)[0];rows={}
    for name,d in gate.frfs.items():
        p=np.interp(f,d["f"],d["p"].real)+1j*np.interp(f,d["f"],d["p"].imag)
        low=f<20;model=PLANT["low_frequency_model"]
        p[low]=rigid_response(f[low],model["J"],model["B"],model["delay_s"])
        rows[name]=abs(1/(1+c*p))
    return dict(frequency_hz=f,per_frf=rows,plant_interpolation="Composite design plant; exact rigid-body response below20Hz and real/imaginary interpolation above",
        additional_numeric_bound=None,low_frequency_requirement="integrator lies in the p198 separation band")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iterations",type=int,default=90)
    parser.add_argument("--starts",type=int,default=8)
    parser.add_argument("--workers",type=int,default=4)
    parser.add_argument("--evaluate",action="store_true")
    args=parser.parse_args()
    if args.starts<8: parser.error("The design requires at least eight independent starts")
    frfs=load_frfs();trials=load_trials();host=CaseBHost(sys.modules[__name__]);noise=NoiseReplay(sys.modules[__name__],host)
    table=DirectDF() if args.evaluate else DFTable();modes=notch_candidates(frfs);corners=modes["modes_hz"]
    old={name:json.loads((OUT/f"book_{name}.json").read_text()) for name in ("linear","both")}
    spectra=input_spectra(host,old["linear"]["tuning"],trials)
    save(WORK/"plant.json",PLANT)
    if not args.evaluate:
        save(WORK/"decision.json",dict(task="true-notch design pass",purpose="Compare feasible maximum first-crossing bandwidth under fixed in-motion plant and true-notch bounds; no HIGS-win tuning",
             existing_same_condition_results=False,reason="Existing adopted designs use skew zero/pole frequencies and allow lightly damped notch poles",plant=PLANT,
             search_plan=dict(starts=args.starts,iterations=args.iterations,seed_base=1001,objective="maximise first crossover",spread="all feasible starts and best four",wi="identity during bandwidth search; separate case-b LF error tuning in fixed Wi box")))
    records=json.loads((OUT/"book_design.json").read_text())["designs"] if args.evaluate else {}
    for label,mode in (("linear","linear"),("both","both")):
        gate=Gate(frfs,table,spectra["f_min_hz"],spectra["f_start_hz"],noise,current=CurrentReplay(host,trials,8))
        if not args.evaluate:
            seed_records=[old[mode]] if mode=="linear" else [records["linear"],old["both"]]
            try:
                rec=multi_start(gate,mode,corners,args.iterations,args.starts,args.workers,seed_records,label)
            except NoFeasibleDesign as error:
                failure=json.loads((WORK/f"{label}_failure.json").read_text())
                records[label]=dict(failure,design_mode=mode,design_plant=PLANT)
                for name in ("linear","both"):
                    save(OUT/f"book_{name}.json",records.get(name,dict(status="not_run",design_mode=name)))
                save(OUT/"book_design.json",dict(method="Chapter8 true-notch pass",status="no_feasible_found",design_plant=PLANT,designs=records))
                print(str(error),flush=True)
                return
            rec["tuning"],rec["wi_time_tuning"]=tune_wi(host,rec["tuning"],mode,trials,noise=noise)
            save(WORK/f"{label}_tuned.json",rec)
        else: rec=records[label]
        direct=Gate(frfs,DirectDF(),gate.fmin,gate.fstart,noise,current=CurrentReplay(host,trials,256))
        rec=final_record(rec,mode,direct,spectra,host,trials)
        record_convergence(rec,label,mode,direct,host,trials)
        comp=rec["wi_time_tuning"];unit=dict(rec["tuning"],wi_pole_hz=rec["tuning"]["integral_hz"],wi_zero_hz=rec["tuning"]["integral_hz"])
        comp["chosen"]=rec["offline_replays"];comp["wi_one"]=case_b_replays(host,unit,mode,trials)
        comp["chosen_pooled_error_le_20hz_rms_rad"]=_pooled_low_error(comp["chosen"])
        comp["wi_one_pooled_error_le_20hz_rms_rad"]=_pooled_low_error(comp["wi_one"])
        comp["chosen_noise_ac_rms_a"]=rec["noise_replay"]["command_ac_rms_a"]
        comp["wi_one_noise_ac_rms_a"]=noise.rms(unit,mode);comp.pop("history",None)
        if max(r["command_peak_a"] for r in comp["chosen"].values())>=2.71: raise RuntimeError("Chosen Wi saturates")
        updated=input_spectra(host,rec["tuning"],trials)
        if any(updated[k]!=spectra[k] for k in ("f_min_hz","f_start_hz")): raise RuntimeError("LP input spectrum changed")
        rec["resonance_detection"]=modes;rec["design_plant"]=PLANT
        rec["measured_frf_sources"]={k:dict(source_sha256=v["source_sha256"],points=len(v["f"]),band_hz=[v["f"][0],v["f"][-1]]) for k,v in frfs.items()}
        rec["design_label"]={"linear":"Linear","both":"HIGS, fixed project bounds"}[label]
        rec["hardware_candidate"]=True
        records[label]=rec;save(WORK/f"{label}_final.json",rec)
        print(label,rec["bandwidth_hz"],rec["search"]["top_feasible_spread_hz"],rec["linear_counterpart_poles_zeros"],flush=True)
    linear,box=records["linear"],records["both"]
    difference=box["bandwidth_hz"]-linear["bandwidth_hz"]
    comparison=dict(higs_minus_linear_hz=difference,
        all_feasible_spread_hz={k:r["search"]["all_feasible_spread_hz"] for k,r in records.items()},
        top_four_spread_hz={k:r["search"]["top_feasible_spread_hz"] for k,r in records.items()},
        interpretation="Best differences and finite-start ranges only; ranges are not statistical confidence intervals and global optimality is unproved")
    for label in ("linear","both"): save(OUT/f"book_{label}.json",records[label])
    save(OUT/"book_design.json",dict(method="Chapter8 Fig8.9 / eq8.11-8.14; true-notch pass",design_plant=PLANT,designs=records,bandwidth_comparison=comparison,deviations=[
        "W_S=.5 constant; linear lambda=0, HIGS lambda=.4 instead of final book piecewise weighting",
        "P-slot roll-off fixed4000Hz; omega_d/wb=.3..1; beta_lp=.1..1; one true notch per limiting resonance: shared zero/pole frequency within5percent of measured mode; beta_p=.2..1; beta_z=.005..beta_p/2; measured-peak gain<=-6dB; max gain=0dB",
        "Project HIGS search condition wh,lp/wb=1..2.5 and wh,i/wb=.3...7 is not a book claim",
        "Wi eq8.14 DC1 beta1, pole=wi/3..3wi, zero/pole1..10, separately time-tuned; omega_min/start from replayed LP input spectra",
        "10mA measured command-noise bound and2.71A case-b non-saturation are project choices",
        "16kHz sampled HIGS DF and unwarped Tustin rather than book5kHz; finite-grid DF Nyquist-type is not nonlinear stability proof",
        "Single coherence-qualified moving composite plant; rigid body plus fitted measured elastic mode for offline case-b replay; no hardware or MATLAB evaluation"]))


def search_vector(record,mode,corners):
    t=record["tuning"];bw=record.get("bandwidth_hz") or record["constraint_record"]["per_frf"]["design"]["bandwidth_hz"]
    vector=[bw,t["integral_hz"]/bw,t["lead_zero_hz"]/bw,t["lowpass_hz"]/bw,t["lowpass_beta"]]
    for corner in corners:
        n=min(t["notches"],key=lambda n:abs(n["zero_hz"]-corner));bp=np.clip(n["pole_beta"],.2,1.)
        fraction=1+np.clip((n["zero_beta"]-.005)/(bp/2-.005),0,1)
        vector.extend((n["zero_hz"]/corner,bp,fraction))
    if mode=="both":
        h=np.array([t["higs_lp_corner_hz"],t["higs_i_corner_hz"]])/SQ
        if record.get("design_mode")=="linear":h=np.array([1.75,.5])*bw
        vector.extend(h/bw)
    return np.log(vector)


def _start_worker(job):
    label,index,mode,corners,iterations,initial,fmin,fstart=job
    host=CaseBHost(sys.modules[__name__]);noise=NoiseReplay(sys.modules[__name__],host)
    gate=Gate(load_frfs(),DFTable(),fmin,fstart,noise,current=CurrentReplay(host,load_trials(),8))
    rec=optimise(gate,mode,corners,iterations,1001+100*({"linear":0,"both":1}[label])+index,initial)
    if rec is not None:
        try: exact_polish(rec,mode,gate)
        except RuntimeError as error: rec["direct_failure"]=str(error)
    save(WORK/f"{label}_start_{index}.json",rec)
    return rec


class NoFeasibleDesign(RuntimeError):
    pass


def multi_start(gate,mode,corners,iterations,starts,workers,seed_records,label):
    initial=[search_vector(r,mode,corners) for r in seed_records]
    jobs=[(label,k,mode,corners,iterations,initial[k] if k<len(initial) else None,gate.fmin,gate.fstart) for k in range(starts)]
    with ProcessPoolExecutor(max_workers=workers) as pool: records=list(pool.map(_start_worker,jobs))
    feasible=[r for r in records if r and "direct_failure" not in r and r["constraint_record"]["passed"]]
    feasible.sort(key=lambda r:r["constraint_record"]["per_frf"]["design"]["bandwidth_hz"],reverse=True)
    if not feasible:
        failure=dict(status="no_feasible_found",design=label,independent_starts=starts,iterations=iterations,
                     reason="No endpoint passed direct DF and all fixed bounds; this finite search does not prove infeasibility")
        save(WORK/f"{label}_failure.json",failure)
        raise NoFeasibleDesign(failure["reason"]+": "+label)
    best=feasible[0];top=feasible[:4]
    values=[r["constraint_record"]["per_frf"]["design"]["bandwidth_hz"] for r in top]
    best["search"].update(independent_starts=starts,feasible_starts=len(feasible),
        initial_sources=["linear optimum" if mode=="both" and k==0 else "previous design" if k<len(initial) else "independent Latin hypercube population" for k in range(starts)],
        top_start_rule="Best four directly feasible independent starts, declared before search; Wi identity during bandwidth search",top_feasible_spread_hz=[min(values),max(values)],
        all_start_results=[dict(seed=1001+100*({"linear":0,"both":1}[label])+i,
            feasible=bool(r and "direct_failure" not in r and r["constraint_record"]["passed"]),
            bandwidth_hz=r["constraint_record"]["per_frf"]["design"]["bandwidth_hz"] if r else None) for i,r in enumerate(records)],
        start_endpoints=[dict(tuning=r["tuning"],search={key:r["search"].get(key)
            for key in ("seed","initial_vector_log")}) if r else None for r in records])
    save(WORK/f"{label}_search.json",best)
    return best


def record_convergence(rec,label,mode,gate,host,trials):
    """Screen each independent bandwidth-search endpoint at its own Wi=1."""
    results=[];endpoints=[]
    for k in range(rec["search"]["independent_starts"]):
        path=WORK/f"{label}_start_{k}.json"
        saved=rec["search"].get("start_endpoints",[])
        endpoint=json.loads(path.read_text()) if path.exists() else saved[k] if k<len(saved) else None
        endpoints.append(dict(tuning=endpoint["tuning"],search={key:endpoint["search"].get(key)
            for key in ("seed","initial_vector_log")}) if endpoint else None)
        if not endpoint:
            results.append(dict(start=k,seed=1001+100*({"linear":0,"both":1}[label])+k,
                feasible=False,bandwidth_hz=None));continue
        t=endpoint["tuning"]
        check=gate.evaluate(t,mode,loaded=True)
        replay=case_b_replays(host,t,mode,trials)
        peak=max(r["command_peak_a"] for r in replay.values())
        passed=bool(check["passed"] and all(r["completed"] for r in replay.values()) and peak<2.71)
        results.append(dict(start=k,seed=endpoint["search"]["seed"],feasible=passed,
            bandwidth_hz=check["per_frf"]["design"]["bandwidth_hz"],command_peak_a=peak,
            noise_rms_a=check["noise"]["command_ac_rms_a"]))
    values=sorted((r["bandwidth_hz"] for r in results if r["feasible"]),reverse=True)[:4]
    if not values: raise RuntimeError("No feasible convergence endpoints at selected Wi")
    rec["search"].update(all_start_results=results,feasible_starts=sum(r["feasible"] for r in results),
        top_start_rule="Up to best four feasible independent endpoints after direct DF, Wi=1 bandwidth-search condition, measured noise, and all five case-b non-saturation checks; declared before search",
        top_feasible_spread_hz=[min(values),max(values)],
        all_feasible_spread_hz=[min(r["bandwidth_hz"] for r in results if r["feasible"]),max(r["bandwidth_hz"] for r in results if r["feasible"])],
        start_endpoints=endpoints,
        convergence_wi_identity=True)


class DFTable:
    def __init__(self):
        path=WORK/"discrete_df.npz"
        if path.exists():
            d=np.load(path);self.f,self.h,self.d=d["f"],d["h"],d["d"]
        else:
            self.f=np.unique(np.r_[np.geomspace(.25,3500,150),np.linspace(3501,7990,110)])
            self.h=np.geomspace(.1,1/(2*np.pi*TS),120)
            self.d=discrete_df(self.f,self.h)
            np.savez(path,f=self.f,h=self.h,d=self.d)
    def __call__(self,h,f):
        j=int(np.clip(np.searchsorted(self.h,h)-1,0,len(self.h)-2))
        a=np.log(h/self.h[j])/np.log(self.h[j+1]/self.h[j])
        row=self.d[j]*(1-a)+self.d[j+1]*a
        return np.interp(np.log(f),np.log(self.f),row.real)+1j*np.interp(np.log(f),np.log(self.f),row.imag)


class DirectDF:
    """Final constraint uses the sampled law at EVERY measured FRF frequency."""
    def __init__(self): self.cache={}
    def __call__(self,h,f):
        ff=np.ascontiguousarray(f,dtype=float);key=(float(h),ff.tobytes())
        if key not in self.cache: self.cache[key]=discrete_df(ff,np.array([h]))[0]
        return self.cache[key]


def exact_polish(rec,mode,gate):
    """Remove interpolation error using the identical acceptance constraint.

    Frequencies and shape stay fixed; maximise the bandwidth over the local
    scalar gain interval with the direct sampled DF, never a tracking screen.
    """
    direct=Gate(gate.frfs,DirectDF(),gate.fmin,gate.fstart,gate.noise,current=gate.current)
    t=rec["tuning"].copy();initial=float(t["kp"]);best=None
    # The first crossover can jump over a local FRF dip. A feasible gain
    # interval can then be much narrower than the mesh: retain scale=1.
    for scale in np.unique(np.r_[np.linspace(.85,1.08,150),1.]):
        candidate=dict(t,kp=initial*scale);r=direct.evaluate(candidate,mode,loaded=True)
        if r["passed"] and (best is None or r["per_frf"]["design"]["bandwidth_hz"]>best[1]):
            best=(candidate,r["per_frf"]["design"]["bandwidth_hz"],r)
    if best is None: raise RuntimeError("Direct sampled DF found no feasible gain near the interpolated design")
    lo=best[0]["kp"];hi=lo+initial*.23/149
    for _ in range(24):
        mid=(lo+hi)/2;candidate=dict(t,kp=mid);r=direct.evaluate(candidate,mode,loaded=True)
        if r["passed"]:lo=mid;best=(candidate,r["per_frf"]["design"]["bandwidth_hz"],r)
        else:hi=mid
    rec["tuning"]=best[0];rec["constraint_record"]=direct.evaluate(rec["tuning"],mode,loaded=True)
    if not rec["constraint_record"]["passed"]:
        raise RuntimeError("Direct loaded SOS failed the same design conditions")
    rec["search"]["direct_df_gain_polish"]=dict(kp_before=initial,kp_after=rec["tuning"]["kp"],interval_scale=[.85,1.08],all_measured_lines=True)
    return direct

def quad(w,b): return [1.,2*b*w,w*w]
def tustin(num,den):
    b,a=signal.bilinear(num,den,fs=FS)
    return signal.tf2sos(b,a)

def loaded_controller(t,mode):
    """kp in lpPost, PD roll-off only in P, exact Wi inverse only in iPost."""
    wl,wi,wd,wr,cl,ci=2*np.pi*np.array([t["lowpass_hz"],t["integral_hz"],t["lead_zero_hz"],4000.,t["higs_lp_corner_hz"],t["higs_i_corner_hz"]])
    wz,wp=2*np.pi*np.array([t["wi_zero_hz"],t["wi_pole_hz"]])
    hl=tustin([cl],[1,cl]);lp=tustin(t["kp"]*wl*wl/cl*np.array([1.,cl]),quad(wl,t["lowpass_beta"]))
    pd=tustin([wr/wd,wr],[1,wr]);pre=tustin((wp/wz)**2*np.array(quad(wz,1.)),quad(wp,1.));hi=tustin([ci],[1,ci])
    z=np.r_[-ci,np.roots(quad(wp,1.))];p=np.r_[0.,np.roots(quad(wz,1.))]
    zd,pp,k=signal.bilinear_zpk(z,p,wi/ci*(wz/wp)**2,FS)
    ip=signal.zpk2sos(zd,pp,k)
    post=np.vstack([tustin(quad(2*np.pi*n["zero_hz"],n["zero_beta"]),quad(2*np.pi*n["zero_hz"],n["pole_beta"])) for n in t["notches"]]) if t["notches"] else np.zeros((0,6))
    sos=np.vstack([hl,lp,pd,pre,hi,ip,post])
    if len(sos)>10: raise ValueError("Controller bank exceeds ten SOS slots")
    if not (0<cl/SQ*TS<=1 and 0<ci/SQ*TS<=1): raise ValueError("HIGS sampled frequency violates 0 < omega_h Ts <= kh")
    return dict(sos=sos,section_counts=[0,len(lp),len(pd),len(pre),len(ip),len(post)],higs_lp_enabled=mode=="both",higs_i_enabled=mode=="both",
                higs_lp_gain=1.,higs_i_gain=1.,higs_lp_omega_ts=cl/SQ*TS,higs_i_omega_ts=ci/SQ*TS)

def sosfr(sos,f): return signal.sosfreqz(sos,worN=2*np.pi*np.asarray(f)*TS)[1]

def controller_response(t,mode,f,table,loaded=False):
    f=np.asarray(f);s=1j*2*FS*np.tan(np.pi*f/FS)
    wl,wi,wd,wr,cl,ci=2*np.pi*np.array([t["lowpass_hz"],t["integral_hz"],t["lead_zero_hz"],4000.,t["higs_lp_corner_hz"],t["higs_i_corner_hz"]])
    lp=wl*wl/(s*s+2*t["lowpass_beta"]*wl*s+wl*wl)
    hl,hi=cl/(s+cl),ci/(s+ci)
    dl=table(cl/(2*np.pi*SQ),f) if mode=="both" else hl
    di=(table(ci/(2*np.pi*SQ),f) if mode=="both" else hi)*wi*(s+ci)/(ci*s)
    vlp=lp/hl;pd=(1+s/wd)/(1+s/wr);nn=np.ones(len(f),complex)
    for n in t["notches"]:
        wn=2*np.pi*n["zero_hz"]
        nn*=(s*s+2*n["zero_beta"]*wn*s+wn*wn)/(s*s+2*n["pole_beta"]*wn*s+wn*wn)
    c=t["kp"]*dl*vlp*(pd+di)*nn
    wa=t["kp"]*(1+di+s/wd)/(1+s/wr)*vlp
    if loaded:
        sos=loaded_controller(t,mode)["sos"]
        a,b,p,w,h,v=[sosfr(sos[i:j],f) for i,j in ((0,1),(1,2),(2,3),(3,4),(4,5),(5,7))]
        nn=sosfr(sos[7:],f) if len(sos)>7 else 1.
        if mode=="both": a=dl;h=table(ci/(2*np.pi*SQ),f)
        dd=w*h*v;cc=a*b*(p+dd)*nn
        if np.max(abs(cc-c)/np.maximum(1e-9,abs(c)))>1e-5: raise AssertionError("Packed SOS / design mismatch")
        c=cc;wa=b*(1+dd+s/wd)/(1+s/wr)
    return c,wa,dl

def first_crossover(f,loop):
    a=np.log(abs(loop));cross=np.flatnonzero(a[:-1]*a[1:]<=0)
    if not len(cross): return 0.
    j=cross[0];x=a[j]/(a[j]-a[j+1])
    return float(np.exp(np.log(f[j])*(1-x)+np.log(f[j+1])*x))

def nyquist(loop):
    """Type-2 DC indentation, measured positive branch, unit-disk HF closure.

    Assumes no RHP plant poles and no unmeasured encirclement. Raw measurement
    does not identify DC or Nyquist-frequency dynamics; report these limits.
    """
    phase=np.unwrap(np.angle(1+loop))
    if phase[0]>np.pi/2: phase-=2*np.pi
    winding=int(np.rint(phase[-1]/(2*np.pi)))
    return dict(stable=bool(winding==0 and abs(loop[-1])<1),winding=winding,start_phase_deg=float(np.degrees(phase[0])),
                end_phase_deg=float(np.degrees(phase[-1])),end_loop_magnitude=float(abs(loop[-1])),min_distance_to_minus_one=float(np.min(abs(1+loop))))

def notch_metrics(n):
    """Shared frequency and beta_z<=beta_p make the exact supremum one."""
    return float(n["zero_beta"]/n["pole_beta"]),1.


def notch_gain(n,f,loaded=False):
    s=1j*(2*FS*np.tan(np.pi*f/FS) if loaded else 2*np.pi*f);wn=2*np.pi*n["zero_hz"]
    return float(abs((s*s+2*n["zero_beta"]*wn*s+wn*wn)/(s*s+2*n["pole_beta"]*wn*s+wn*wn)))


def controller_poles_zeros(t):
    """Minimal complete linear counterpart; Wi and H inverses cancel."""
    wl,wi,wd,wr=2*np.pi*np.array([t["lowpass_hz"],t["integral_hz"],t["lead_zero_hz"],4000.])
    def roots(w,beta):
        delta=w*np.sqrt(complex(beta*beta-1));return [-beta*w+delta,-beta*w-delta]
    poles=roots(wl,t["lowpass_beta"])+[0.,-wr]
    zeros=list(np.roots([wr/wd,wr+wi,wi*wr]))
    for n in t["notches"]:
        poles.extend(roots(2*np.pi*n["zero_hz"],n["pole_beta"]))
        zeros.extend(roots(2*np.pi*n["zero_hz"],n["zero_beta"]))
    def split(values):
        real=sorted(float(np.real(x)) for x in values if abs(np.imag(x))<=1e-6)
        complex_=[[float(np.real(x)),float(np.imag(x))] for x in values if abs(np.imag(x))>1e-6]
        return real,complex_
    rp,cp=split(poles);rz,cz=split(zeros)
    return dict(real_poles_rad_s=rp,real_zeros_rad_s=rz,complex_poles_rad_s=cp,complex_zeros_rad_s=cz,
        poles=[root_record(x) for x in poles],zeros=[root_record(x) for x in zeros],
        interpretation="Unwarped-Tustin continuous-time equivalent of minimal full C(s)=kp*LP*(PD+wi/s)*N; H/Wi cancellation removed; multiplicities retained")


def root_record(value):
    value=complex(value);frequency=abs(value)
    return dict(real_rad_s=float(value.real),imag_rad_s=float(value.imag),natural_frequency_hz=float(frequency/(2*np.pi)),
                damping=float(-value.real/frequency) if frequency else None,inherent_integrator=bool(frequency==0))


def controller_filter_poles_zeros(t,mode):
    """All active LTI factors before branch combination/cancellation."""
    wl,wd,wr,cl,ci,wp,wz=2*np.pi*np.array([t["lowpass_hz"],t["lead_zero_hz"],4000.,
        t["higs_lp_corner_hz"],t["higs_i_corner_hz"],t["wi_pole_hz"],t["wi_zero_hz"]])
    def roots(w,beta):
        delta=w*np.sqrt(complex(beta*beta-1));return [-beta*w+delta,-beta*w-delta]
    def factor(poles,zeros):return dict(poles=[root_record(x) for x in poles],zeros=[root_record(x) for x in zeros])
    factors=dict(lp_post=factor(roots(wl,t["lowpass_beta"]),[-cl]),p=factor([-wr],[-wd]),
        i_pre_Wi=factor([-wp,-wp],[-wz,-wz]),i_post=factor([0.,-wz,-wz],[-ci,-wp,-wp]))
    for k,n in enumerate(t["notches"]):
        wn=2*np.pi*n["zero_hz"]
        factors[f"notch_{k}"]=factor(roots(wn,n["pole_beta"]),roots(wn,n["zero_beta"]))
    if mode=="linear":
        factors.update(lp_linear_H=factor([-cl],[]),i_linear_H=factor([-ci],[]))
    low=[dict(factor=name,**p) for name,f in factors.items() for p in f["poles"] if abs(p["imag_rad_s"])>1e-6 and p["damping"]<.2-1e-12]
    return dict(factors=factors,low_damping_complex_poles=low,no_unintended_low_damping_poles=not low,
        interpretation="Unwarped-Tustin continuous-time roots with multiplicities; finite zeros only. HIGS states are nonlinear and have no LTI poles; origin is the inherent I structure.")


class Gate:
    def __init__(self,frfs,table,fmin,fstart,noise=None,*,current=None):
        self.frfs,self.table,self.fmin,self.fstart=frfs,table,float(fmin),float(fstart)
        self.noise,self.current=noise,current
        self.peaks=notch_candidates(frfs)["per_frf"]
    def add_noise(self,record,t,mode):
        value=self.noise.rms(t,mode) if self.noise is not None else None
        record["noise"]=dict(command_ac_rms_a=value,limit_a=.010,passed=bool(value is not None and value<=.010),
            interpretation="40 demeaned standstill segments; .2s head exclusion; last of5 periodic cycles; sample-pooled AC RMS")
        record["passed"]=bool(record["passed"] and record["noise"]["passed"])
        return record
    def add_current(self,record,t,mode):
        if self.current is not None:
            record["case_b_current"]=self.current.evaluate(t,mode)
            record["passed"]=bool(record["passed"] and record["case_b_current"]["passed"])
        return record
    def evaluate(self,t,mode,loaded=False,include_noise=True,include_current=True):
        lam=.4 if mode=="both" else 0.
        def row(d):
            f,p=d["f"],d["p"];c,w,dl=controller_response(t,mode,f,self.table,loaded=loaded)
            loop=c*p;ss=1/(1+loop);ws=.5*abs(ss)
            delta=np.where(f>=self.fstart,self.table(t["higs_lp_corner_hz"]/SQ,np.array([self.fmin]))[0]-dl,0.) if mode=="both" else np.zeros(len(f))
            un=abs(delta*w*ss*p);test=nyquist(loop)
            return dict(ws_norm=float(np.max(ws)),wa_sp_norm=float(np.max(un)),sum=float(np.max(ws)+lam*np.max(un)),
                max_abs_s=float(np.max(abs(ss))),ws_peak_hz=float(f[np.argmax(ws)]),wa_sp_peak_hz=float(f[np.argmax(un)]),
                bandwidth_hz=first_crossover(f,loop),stable=test["stable"],nyquist=test)
        design=row(self.frfs["design"]);bw=design["bandwidth_hz"];den=max(1e-30,bw)
        fi,fl,fd=t["integral_hz"],t["lowpass_hz"],t["lead_zero_hz"]
        hl,hi=t["higs_lp_corner_hz"]/SQ,t["higs_i_corner_hz"]/SQ
        wi_pole,wi_ratio=t["wi_pole_hz"],t["wi_zero_hz"]/t["wi_pole_hz"]
        values=dict(integral_to_bandwidth=fi/den,lead_zero_to_bandwidth=fd/den,lowpass_to_bandwidth=fl/den,lowpass_beta=t["lowpass_beta"],
            wi_pole_to_integral=wi_pole/fi,wi_zero_to_pole=wi_ratio)
        ranges=dict(integral_to_bandwidth=[1/3,.5],lead_zero_to_bandwidth=[.3,1.],lowpass_to_bandwidth=[2.,4.],lowpass_beta=[.1,1.],
            wi_pole_to_integral=[1/3,3.],wi_zero_to_pole=[1.,10.])
        if mode=="both":
            values.update(omega_h_lp_to_bandwidth=hl/den,omega_h_i_to_bandwidth=hi/den)
            ranges.update(omega_h_lp_to_bandwidth=[1.,2.5],omega_h_i_to_bandwidth=[.3,.7])
        tolerance=1e-10
        bounds=dict(passed=bool(t["kp"]>0 and abs(t["lead_pole_hz"]-4000)<1e-9 and t["higs_lp_gain"]==1 and t["higs_i_gain"]==1 and
            t["wi_pole_beta"]==1 and t["wi_zero_beta"]==1 and all(lo-tolerance<=values[k]<=hi_+tolerance for k,(lo,hi_) in ranges.items())),
            parameters={k:dict(value=v,range=ranges[k],active=bool(min(abs(v-ranges[k][0]),abs(v-ranges[k][1]))<1e-4)) for k,v in values.items()},
            kp_positive=t["kp"]>0,omega_r_hz=4000.,kh=1.,wi_beta=1.)
        separation=dict(bandwidth_member="design",integral_to_bandwidth=fi/den,lowpass_to_bandwidth=fl/den,
            higs_lp_to_bandwidth=hl/den if mode=="both" else None,passed=bool(1/3-tolerance<=fi/den<=.5+tolerance and 2-tolerance<=fl/den<=4+tolerance))
        box=dict(required=mode=="both",passed=bool(mode!="both" or (1-tolerance<=hl/den<=2.5+tolerance and .3-tolerance<=hi/den<=.7+tolerance)),
            omega_h_lp_to_bandwidth=hl/den if mode=="both" else None,omega_h_i_to_bandwidth=hi/den if mode=="both" else None,
            project_search_condition="Fixed project bounds, not a book claim",lp_range=[1.,2.5],i_range=[.3,.7])
        peak=self.peaks["design"]["peaks_hz"][0];placements=[]
        for n in t["notches"]:
            ratio=n["pole_hz"]/n["zero_hz"];at_zero,maximum=notch_metrics(n);bz,bp=n["zero_beta"],n["pole_beta"]
            at_peak=notch_gain(n,peak);at_peak_loaded=notch_gain(n,peak,loaded=True)
            values={"frequency_to_peak":n["zero_hz"]/peak,"zero_beta":bz,"pole_beta":bp}
            ranges={"frequency_to_peak":[.95,1.05],"zero_beta":[.005,bp/2],"pole_beta":[.2,1.]}
            placements.append(dict(measured_member="design",peak_hz=peak,zero_hz=n["zero_hz"],pole_to_zero=ratio,zero_beta=bz,pole_beta=bp,
                gain_at_zero=at_zero,gain_at_zero_db=float(20*np.log10(at_zero)),max_gain=maximum,max_gain_db=float(20*np.log10(maximum)),
                gain_at_peak=at_peak,gain_at_peak_db=float(20*np.log10(at_peak)),gain_at_peak_loaded=at_peak_loaded,
                gain_at_peak_loaded_db=float(20*np.log10(at_peak_loaded)),
                parameters={k:dict(value=v,range=ranges[k],active=bool(min(abs(v-ranges[k][0]),abs(v-ranges[k][1]))<1e-4)) for k,v in values.items()},
                passed=bool(.95*peak<=n["zero_hz"]<=1.05*peak and n["pole_hz"]==n["zero_hz"] and .2<=bp<=1 and .005<=bz<=bp/2 and
                    max(at_zero,at_peak,at_peak_loaded)<=10**(-6/20) and maximum<=10**(.1/20))))
        notch=dict(passed=bool(len(placements)==1 and all(n["passed"] for n in placements)),placements=placements,
            rule="One true notch per limiting resonance; shared zero/pole frequency within5percent of measured peak; beta_p .2..1; beta_z .005..beta_p/2; at centre and measured peak (continuous and loaded Tustin)<=-6dB; exact continuous-frequency max=0dB")
        record=dict(**{"lambda":lam},W_S=.5,passed=bool(bounds["passed"] and design["sum"]<=1 and design["stable"] and bw>0 and notch["passed"]),
            per_frf={"design":design},bounds=bounds,separation=separation,higs_regime_box=box,notch_shape=notch)
        if loaded: record["informational_ms100"]=row(MS100)
        if include_current: self.add_current(record,t,mode)
        return self.add_noise(record,t,mode) if include_noise else record


def notch_candidates(frfs):
    d=frfs["design"];use=(d["f"]>=150)&(d["f"]<=400);f=d["f"][use];mag=abs(d["p"][use])
    peaks,_=signal.find_peaks(mag);main=peaks[np.argmax(mag[peaks])]
    row=dict(peaks_hz=[float(f[main])],peak_magnitude_rad_per_a=float(mag[main]))
    return dict(per_frf={"design":row},modes_hz=row["peaks_hz"],rule="Largest coherence-qualified in-motion load-position peak in150..400Hz; one notch per limiting elastic resonance")


def unpack(x,mode,corners):
    q=np.exp(x);fc,ri,rd,rl,beta=q[:5];idx=5
    t=dict(kp=1.,integral_hz=fc*ri,lead_zero_hz=fc*rd,lead_pole_hz=4000.,lowpass_hz=fc*rl,lowpass_beta=beta,
        higs_lp_corner_hz=150*SQ,higs_i_corner_hz=20*SQ,higs_lp_gain=1.,higs_i_gain=1.,
        wi_pole_hz=fc*ri,wi_zero_hz=fc*ri,wi_pole_beta=1.,wi_zero_beta=1.,notches=[])
    for peak in corners:
        ratio,bp,fraction=q[idx:idx+3];idx+=3;f=peak*ratio
        bz=.005+(fraction-1)*(bp/2-.005)
        t["notches"].append(dict(zero_hz=f,pole_hz=f,zero_beta=bz,pole_beta=bp))
    if mode=="both":
        h=q[idx:idx+2]*fc*SQ;t["higs_lp_corner_hz"],t["higs_i_corner_hz"]=h
    return fc,t


def optimise(gate,mode,corners,iterations=90,seed=1001,initial=None):
    limits=[(1.,600.),(1/3,1/2),(.3,1.),(2.,4.),(.1,1.)]
    for f in corners: limits += [(.95,1.05),(.2,1.),(1.,2.)]
    if mode=="both": limits += [(1.,2.5),(.3,.7)]
    bounds=np.log(limits);f=gate.frfs["design"]["f"];p=gate.frfs["design"]["p"]
    initial_vector=None if initial is None else np.clip(np.asarray(initial),bounds[:,0],bounds[:,1])
    counter=0;best=[None,-np.inf]
    def trial(x):
        nonlocal counter
        fc,t=unpack(x,mode,corners)
        pp=np.interp(fc,f,p.real)+1j*np.interp(fc,f,p.imag)
        c=controller_response(t,mode,np.array([fc]),gate.table)[0][0];t["kp"]=float(1/abs(c*pp))
        r=gate.evaluate(t,mode,include_noise=False,include_current=False);bw=r["per_frf"]["design"]["bandwidth_hz"]
        violation=max(0,r["per_frf"]["design"]["sum"]-.9995)
        violation+=sum(max(0,max(n["gain_at_zero"],n["gain_at_peak"],n["gain_at_peak_loaded"])/10**(-6/20)-.9995) for n in r["notch_shape"]["placements"])
        for item in r["bounds"]["parameters"].values():
            lo,hi=item["range"];v=item["value"];violation+=max(0,lo-v)+max(0,v-hi)
        unstable=not r["per_frf"]["design"]["stable"];counter+=1
        if not unstable and violation<.03:
            gate.add_current(r,t,mode);current=r["case_b_current"]
            violation+=max(0,np.log(max(1.,current["command_peak_a"]/2.71)))
            if current["passed"]:
                gate.add_noise(r,t,mode);violation+=max(0,r["noise"]["command_ac_rms_a"]/.010-.9995)
        else:r["passed"]=False
        if r["passed"] and bw>best[1]:best[:]=[dict(tuning=t,constraint_record=r,x=x.copy()),bw]
        return -np.log(max(.01,bw))+50*violation+200*unstable
    started=time.time()
    res=differential_evolution(trial,bounds,popsize=8,maxiter=iterations,tol=.002,seed=seed,polish=False,x0=initial_vector)
    minimize(trial,res.x,method="Nelder-Mead",bounds=bounds,options=dict(maxiter=1400,xatol=2e-5,fatol=1e-7))
    print(f"{mode} seed={seed}: {best[1]:.6f}Hz, {counter} evaluations, {time.time()-started:.1f}s",flush=True)
    if best[0] is None:return None
    out=best[0];out["search"]=dict(objective="maximise first composite-design-plant DF crossover under fixed adopted bounds and the true-notch rule, separate sup norms, noise and case-b non-saturation",seed=seed,bounds_log=bounds,evaluations=counter,
        initial_vector_log=initial_vector,search_windows_are_not_acceptance_constraints=True,
        variable_order=["target_bandwidth_hz","integral_to_target_bandwidth","lead_zero_to_target_bandwidth","lowpass_to_target_bandwidth","lowpass_beta"]+
            [f"notch_{j}_{k}" for j in range(len(corners)) for k in ("frequency_to_peak","pole_beta","depth_fraction_plus_one")]+(["higs_lp_wh_to_target_bw","higs_i_wh_to_target_bw"] if mode=="both" else []),
        elapsed_s=time.time()-started,global_optimality_proved=False,notch_count=len(corners),maxiter=iterations,popsize=8,tol=.002,
        nelder_mead=dict(maxiter=1400,xatol=2e-5,fatol=1e-7))
    return out


_NOISE_SOURCE = r'''
extern "C" int noise_ac_variances(
    const double* input, unsigned segments, const unsigned* sizes,
    const double* coefficients, unsigned sections, const unsigned* counts,
    int lp_enabled, double lp_gain, double lp_omega_ts,
    int i_enabled, double i_gain, double i_omega_ts, double* result)
{
    controllercore::ControllerAlgorithm controller;
    const controllercore::ControllerAlgorithm::SectionCounts layout = {
        counts[0], counts[1], counts[2], counts[3], counts[4], counts[5]};
    const controllercore::ControllerAlgorithm::HigsParameters lp = {
        lp_enabled != 0, lp_gain, lp_omega_ts};
    const controllercore::ControllerAlgorithm::HigsParameters integral = {
        i_enabled != 0, i_gain, i_omega_ts};
    if (!controller.ApplyParameters(coefficients, sections, 1, layout, lp, integral)) return -1;
    unsigned offset = 0;
    for (unsigned segment = 0; segment < segments; ++segment) {
        controller.Reset();
        const unsigned n = sizes[segment];
        double mean = 0.0, m2 = 0.0;
        for (unsigned repeat = 0; repeat < 5; ++repeat) {
            for (unsigned k = 0; k < n; ++k) {
                const double command = controller.Step(input[offset + k], 0.0, 0.0);
                if (!std::isfinite(command)) return static_cast<int>(segment) + 1;
                if (repeat == 4) {
                    const double delta = command - mean;
                    mean += delta / static_cast<double>(k + 1);
                    m2 += delta * (command - mean);
                }
            }
        }
        result[segment] = m2 / n;
        offset += n;
    }
    return 0;
}
'''


def _host_source(core):
    source = (core.ROOT / "simulations/higs_host.cpp").read_text(encoding="utf-8")
    source = source.replace(
        "const double* initial_state, double* output)",
        "const double* initial_state, double* output, int substeps, double coulomb)")
    old = '''        double next[4] = {};
        for (int i = 0; i < 4; ++i) {
            next[i] = b[i] * delayed;
            for (int j = 0; j < 4; ++j) next[i] += a[4 * i + j] * state[j];
            if (!std::isfinite(next[i]) || std::abs(next[i]) > 1e6) return k + 1;
        }
        std::copy(next, next + 4, state);'''
    new = '''        for (int sub = 0; sub < substeps; ++sub) {
            double next[4] = {};
            for (int i = 0; i < 4; ++i) {
                next[i] = b[i] * delayed;
                for (int j = 0; j < 4; ++j) next[i] += a[4 * i + j] * state[j];
            }
            if (coulomb > 0.0) {
                const double force = std::max(-coulomb, std::min(coulomb, next[1]/b[1]));
                for (int i = 0; i < 4; ++i) next[i] -= b[i]*force;
            }
            for (int i = 0; i < 4; ++i)
                if (!std::isfinite(next[i]) || std::abs(next[i]) > 1e6) return k + 1;
            std::copy(next, next + 4, state);
        }'''
    if source.count(old) != 1:
        raise RuntimeError("Offline harness source no longer matches the case-b patch")
    return source.replace(old, new) + _NOISE_SOURCE


class CaseBHost:
    """Unchanged controller core, G's implicit motor friction and saturation."""
    def __init__(self, core):
        self.core = core
        work = core.WORK
        work.mkdir(parents=True, exist_ok=True)
        source_path = work / "case_b_host.cpp"
        source = _host_source(core)
        if not source_path.exists() or source_path.read_text(encoding="utf-8") != source:
            source_path.write_text(source, encoding="utf-8")
        dll = work / "case_b_host.dll"
        inputs = [source_path, core.ROOT / "ControllerCore/ControllerAlgorithm.cpp",
                  core.ROOT / "ControllerCore/ControllerAlgorithm.h"]
        if not dll.exists() or dll.stat().st_mtime < max(p.stat().st_mtime for p in inputs):
            vs = Path(os.environ.get("VSINSTALLDIR", r"C:\Program Files\Microsoft Visual Studio\2022\Community"))
            command = work / "build_case_b.cmd"
            command.write_text('@echo off\nset "TEMP=%~dp0"\nset "TMP=%~dp0"\ncall "' +
                str(vs / "VC/Auxiliary/Build/vcvars64.bat") + '" >nul\nif errorlevel 1 exit /b %errorlevel%\n' +
                'cl.exe /nologo /std:c++17 /O2 /EHsc /LD /I "' + str(core.ROOT / "ControllerCore") +
                '" "' + str(inputs[1]) + '" "' + str(source_path) + '" /link /OUT:"' + str(dll) +
                '" /EXPORT:simulate_higs /EXPORT:noise_ac_variances\n', encoding="utf-8")
            subprocess.run(["cmd.exe", "/d", "/c", str(command)], cwd=work,
                           check=True, capture_output=True)
        self.lib = ctypes.CDLL(str(dll))
        pointer = np.ctypeslib.ndpointer(dtype=np.float64, flags="C_CONTIGUOUS")
        counts = np.ctypeslib.ndpointer(dtype=np.uint32, flags="C_CONTIGUOUS")
        self.fn = self.lib.simulate_higs
        self.fn.argtypes = [ctypes.c_int] + [pointer] * 6 + [ctypes.c_uint, counts,
            ctypes.c_int, ctypes.c_double, ctypes.c_double, ctypes.c_int, ctypes.c_double,
            ctypes.c_double, ctypes.c_int, ctypes.c_double, ctypes.c_double, ctypes.c_double,
            pointer, pointer, ctypes.c_int, ctypes.c_double]
        self.fn.restype = ctypes.c_int
        self.noise_fn = self.lib.noise_ac_variances
        self.noise_fn.argtypes = [pointer, ctypes.c_uint, counts, pointer, ctypes.c_uint, counts,
            ctypes.c_int, ctypes.c_double, ctypes.c_double, ctypes.c_int, ctypes.c_double,
            ctypes.c_double, pointer]
        self.noise_fn.restype = ctypes.c_int
        self._matrices = {}

    def matrices(self, substeps=256):
        key = substeps
        if key not in self._matrices:
            p = self.core.MODEL
            jm, jl, k, c = p["jm"], p["jl"], p["stiffness"], p["damping"]
            viscous = p["bm"]
            a = np.array([[0, 1, 0, 0], [-k/jm, -(c+viscous)/jm, k/jm, c/jm],
                          [0, 0, 0, 1], [k/jl, c/jl, -k/jl, -c/jl]])
            b = np.array([[0.], [1/jm], [0.], [0.]])
            ad, bd, *_ = signal.cont2discrete((a, b, np.eye(4), np.zeros((4, 1))),
                                             self.core.TS/substeps)
            self._matrices[key] = (ad, bd.ravel())
        return self._matrices[key]

    def run(self, controller, reference, ff=None, controller_only=False, *,
            substeps=256, limit=2.71, noise=None, friction=True):
        n = len(reference)
        if controller_only:
            a, b, substeps, delay, coulomb, limit = np.zeros((4, 4)), np.zeros(4), 1, 0, 0., 1e100
        else:
            a, b = self.matrices(substeps)
            delay, coulomb = self.core.DELAY, .116 if friction else 0.
        arr = lambda x: np.ascontiguousarray(x, dtype=np.float64)
        out = np.zeros((n, 14))
        d = controller
        code = self.fn(n, arr(reference), arr(np.zeros(n) if ff is None else ff),
            arr(np.zeros(n) if noise is None else noise), arr(a), arr(b),
            arr(np.asarray(d["sos"])[:, [0, 1, 2, 4, 5]]), len(d["sos"]),
            np.ascontiguousarray(d["section_counts"], dtype=np.uint32),
            d["higs_lp_enabled"], d["higs_lp_gain"], d["higs_lp_omega_ts"],
            d["higs_i_enabled"], d["higs_i_gain"], d["higs_i_omega_ts"],
            delay, limit, 0., 0., arr(np.zeros(4)), out, substeps, coulomb)
        if code:
            raise RuntimeError(f"Case-b controller/plant rejected parameters or diverged: {code}")
        return out


def load_standstill(core):
    segments = []
    for path in sorted((core.ROOT / "simulations/hardware/trials_book").glob("*.mat")):
        d = loadmat(path, simplify_cells=True)
        if "REF" not in d or "raw" not in d or "load_position" not in d["raw"]:
            continue
        reference, position = np.asarray(d["REF"], float), np.asarray(d["raw"]["load_position"], float)
        edges = np.r_[0, np.flatnonzero(np.diff(reference) != 0)+1, len(reference)]
        for run, (lo, hi) in enumerate(zip(edges[:-1], edges[1:])):
            lo += round(.2*core.FS)
            if hi-lo < round(.1*core.FS):
                continue
            x = position[lo:hi]-np.mean(position[lo:hi])
            if not np.all(np.isfinite(x)):
                raise ValueError(f"Nonfinite standstill samples in {path}")
            segments.append(dict(trial=path.stem, run=run, start_sample=int(lo),
                                 stop_sample=int(hi), samples=len(x), x=x))
    if len(segments) != 40 or sum(s["samples"] for s in segments) != 128036:
        raise ValueError("Standstill segment selection differs from G question 5")
    return segments


class NoiseReplay:
    """G q5 noise, with only the latest unit-kp result per mode cached."""
    def __init__(self, core, host, segments=None):
        self.core, self.host = core, host
        self.segments = load_standstill(core) if segments is None else segments
        self.input = np.ascontiguousarray(np.concatenate([s["x"] for s in self.segments]), dtype=np.float64)
        self.sizes = np.ascontiguousarray([s["samples"] for s in self.segments], dtype=np.uint32)
        self.cache = {}
        self.calls = 0

    def variances(self, controller):
        d = controller
        result = np.zeros(len(self.segments))
        code = self.host.noise_fn(self.input, len(self.segments), self.sizes,
            np.ascontiguousarray(np.asarray(d["sos"])[:, [0, 1, 2, 4, 5]], dtype=np.float64),
            len(d["sos"]), np.ascontiguousarray(d["section_counts"], dtype=np.uint32),
            d["higs_lp_enabled"], d["higs_lp_gain"], d["higs_lp_omega_ts"],
            d["higs_i_enabled"], d["higs_i_gain"], d["higs_i_omega_ts"], result)
        if code:
            raise RuntimeError(f"Noise controller replay failed: {code}")
        self.calls += 1
        return result

    def rms(self, tuning, mode, details=False):
        unit = dict(tuning, kp=1.)
        key = json.dumps(unit, sort_keys=True, default=self.core.encode)
        old = self.cache.get(mode)
        if old is None or old[0] != key:
            variance = self.variances(self.core.loaded_controller(unit, mode))
            self.cache[mode] = (key, variance)
        else:
            variance = old[1]
        variance = variance * tuning["kp"]**2
        pooled = float(np.sqrt(np.sum(variance*self.sizes)/np.sum(self.sizes)))
        if not details:
            return pooled
        return dict(command_ac_rms_a=pooled, limit_a=.01, passed=pooled <= .01,
            segments=len(self.segments), trials=len({s["trial"] for s in self.segments}),
            samples=int(np.sum(self.sizes)), duration_s=float(np.sum(self.sizes)*self.core.TS),
            method="exactly constant REF; head .2s excluded, retain >=.1s; demean position; reset each segment; replay 5 periods and measure last command AC RMS; duration-pooled",
            rig_choice="10mA is approximately 0.4 percent of 2.71A, chosen for this rig; not a book value",
            caveat="recorded standstill position includes mechanical motion and drift",
            per_segment=[{k: v for k, v in s.items() if k != "x"} | {"command_ac_rms_a": float(np.sqrt(v))}
                         for s, v in zip(self.segments, variance)])


def low_frequency_rms(core, x):
    f = np.fft.rfftfreq(len(x), core.TS)
    spec = np.fft.rfft(x)
    weights = np.full(len(f), 2.)
    weights[0] = 1.
    if len(x) % 2 == 0:
        weights[-1] = 1.
    use = f <= 20.
    return float(np.sqrt(np.sum(abs(spec[use])**2*weights[use]))/len(x))


def identified_ff(core, reference):
    v = np.gradient(reference)/core.TS
    a = np.gradient(v)/core.TS
    return 1.134e-4*a + .068*np.tanh(v/.05) + .0625*np.tanh(v/3.) + .000345*v + .0000541*v*abs(v)


class CurrentReplay:
    """Existing non-saturation condition, evaluated during bandwidth search.

    Eight friction substeps guide the search; final acceptance uses 256.
    Check the long motion first, since unstable designs can pass a short move.
    """
    def __init__(self,host,trials,substeps):
        self.host,self.substeps=host,substeps
        order=("r5m100","a002m005","a01m010","a10m010","r5m050")
        self.inputs=[]
        for name in order:
            tr=next(t for t in trials if t["trajectory"]==name)
            self.inputs.append((name,tr["reference"],identified_ff(host.core,tr["reference"])))
    def evaluate(self,t,mode):
        controller=self.host.core.loaded_controller(t,mode);peaks={}
        for name,reference,ff in self.inputs:
            try:
                out=self.host.run(controller,reference,ff,substeps=self.substeps)
            except RuntimeError as error:
                return dict(passed=False,command_peak_a=1e6,limit_a=2.71,per_trajectory_peak_a=peaks,friction_substeps=self.substeps,failure=str(error))
            peaks[name]=float(np.max(abs(out[:,4]+ff)))
            if peaks[name]>=2.71: break
        peak=max(peaks.values())
        return dict(passed=bool(peak<2.71),command_peak_a=peak,limit_a=2.71,per_trajectory_peak_a=peaks,
            friction_substeps=self.substeps,interpretation="Existing case-b non-saturation condition; reject on first clipped trajectory")


def case_b_replays(host, tuning, mode, trials, substeps=256):
    core = host.core
    controller = core.loaded_controller(tuning, mode)
    result = {}
    for name in core.TRAJECTORIES:
        tr = next(t for t in trials if t["trajectory"] == name)
        reference = tr["reference"]
        ff = identified_ff(core, reference)
        out = host.run(controller, reference, ff, substeps=substeps)
        error = reference-out[:, 2]
        demand = out[:, 4]+ff
        applied = np.clip(demand, -2.71, 2.71)
        result[name] = dict(completed=True, reference_trial=tr["name"], source_sha256=tr["source_sha256"],
            samples=len(reference), error_rms_rad=float(np.sqrt(np.mean(error**2))),
            error_peak_rad=float(np.max(abs(error))), error_le_20hz_rms_rad=low_frequency_rms(core, error),
            command_peak_a=float(np.max(abs(demand))), command_hf_gt_1000hz_rms_a=core.band_rms(demand, 1000., core.FS/2),
            applied_peak_a=float(np.max(abs(applied))), applied_hf_gt_1000hz_rms_a=core.band_rms(applied, 1000., core.FS/2),
            twist_200_400hz_rms_rad=core.band_rms(out[:, 0]-out[:, 2], 200., 400.),
            clipped_samples=int(np.sum(abs(demand) > 2.71)), exceeds_2_71_a=bool(np.max(abs(demand)) >= 2.71),
            metric_interval="entire logged reference; rectangular DFT including edges",
            friction_substeps=substeps)
    return result


def _pooled_low_error(rows):
    return float(np.sqrt(sum(v["samples"]*v["error_le_20hz_rms_rad"]**2 for v in rows.values()) /
                         sum(v["samples"] for v in rows.values())))


def tune_wi(host, tuning, mode, trials, *, noise=None, iterations=10, seed=814):
    """Time-domain LF tuning, ratio<=10; final candidates evaluated at 256 steps."""
    baseline = dict(tuning, wi_pole_hz=tuning["integral_hz"], wi_zero_hz=tuning["integral_hz"], wi_pole_beta=1., wi_zero_beta=1.)
    one = case_b_replays(host, baseline, mode, trials)
    evaluations = []
    if mode == "linear":
        return baseline, dict(chosen=one, wi_one=one, chosen_pooled_error_le_20hz_rms_rad=_pooled_low_error(one),
            wi_one_pooled_error_le_20hz_rms_rad=_pooled_low_error(one),
            reason="Wi cancels algebraically in the linear controller; choose identity", search_evaluations=0)

    def evaluate(x, substeps):
        pole, ratio = float(np.exp(x[0])), float(np.exp(x[1]))
        t = dict(tuning, wi_pole_hz=pole, wi_zero_hz=pole*ratio, wi_pole_beta=1., wi_zero_beta=1.)
        rows = case_b_replays(host, t, mode, trials, substeps)
        rms = _pooled_low_error(rows)
        peak = max(v["command_peak_a"] for v in rows.values())
        n = 0. if noise is None else noise.rms(t, mode)
        feasible = peak < 2.71 and n <= .01
        value = np.log(max(rms, 1e-15)) + 100*max(0., peak/2.71-1.) + 100*max(0., n/.01-1.)
        evaluations.append(dict(pole_hz=pole, ratio=ratio, objective_rms_rad=rms,
                                command_peak_a=peak, noise_rms_a=n, feasible=feasible,
                                substeps=substeps, x=np.asarray(x).copy()))
        return value, t, rows, feasible

    pole_bounds = [tuning["integral_hz"]/3.,3*tuning["integral_hz"]]
    candidates = [(np.log([baseline["wi_pole_hz"],1.]),baseline,one,
                   max(v["command_peak_a"] for v in one.values())<2.71 and (noise is None or noise.rms(baseline,mode)<=.01))]
    bounds=[(np.log(pole_bounds[0]),np.log(pole_bounds[1])),(0.,np.log(10.))]
    objective=lambda x:evaluate(x,32)[0]
    result=differential_evolution(objective,bounds,maxiter=iterations,popsize=5,seed=seed,polish=False,tol=1e-4,x0=candidates[0][0])
    local=minimize(objective,result.x,method="Nelder-Mead",bounds=bounds,options=dict(maxiter=65,xatol=.002,fatol=1e-6))
    feasible=sorted((r for r in evaluations if r["substeps"]==32 and r["feasible"]),key=lambda r:r["objective_rms_rad"])
    for row in feasible[:5]+[dict(x=local.x)]:
        _,t,replay,passed=evaluate(row["x"],256);candidates.append((row["x"],t,replay,passed))
    final=sorted((r for r in candidates if r[3]),key=lambda r:_pooled_low_error(r[2]))
    if not final:raise RuntimeError("No Wi candidate meets fixed pole/ratio, case-b peak and noise bounds")
    best=final[0]
    _, chosen, replays, _ = best
    serial = [{k: v for k, v in row.items() if k != "x"} for row in evaluations]
    return chosen, dict(chosen=replays, wi_one=one,
        chosen_pooled_error_le_20hz_rms_rad=_pooled_low_error(replays),
        wi_one_pooled_error_le_20hz_rms_rad=_pooled_low_error(one),
        objective="minimise duration-pooled error RMS at DC..20Hz over all five trajectories",
        constraints="Wi DC gain1, beta1, omega_i/3<=pole<=3omega_i, 1<=zero/pole<=10; each unsaturated demand peak<2.71A; inherited noise bound",
        numerical_pole_search_hz=pole_bounds, ratio_search=[1., 10.],
        search_evaluations=len(evaluations), global_optimality_proved=False,
        coarse_friction_substeps=32, final_friction_substeps=256, history=serial)


if __name__=="__main__": main()
