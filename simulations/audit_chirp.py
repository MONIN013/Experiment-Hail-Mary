#!/usr/bin/env python3
"""Recompute the legacy FRF and refit from the original MAT; never relabel its Ts.

The estimator/fit objective follows identify_chirp.py. The saved design is only
checked on a ZOH-corrected legacy FRF, not approved for hardware operation.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from scipy.fft import rfft, rfftfreq
from scipy.io import loadmat
from scipy.optimize import least_squares
from scipy import signal

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_HASH = 'd882ff79015b8759f70110aaee2aebf039f4aa261c25994ee895e46800d8b4e4'


def response(p, f):
    a,r,km,cm,bm,bl = np.exp(p[:6]); s = 2j*np.pi*f
    coupling = km+cm*s
    dm,dl = s*s+bm*s+coupling, r*s*s+r*bl*s+coupling
    return a*np.stack([dl,coupling])/(dm*dl-coupling*coupling)*np.exp(-s*p[6]*1e-3)


def estimate(u, angles, ts, n):
    velocity = np.diff(angles,axis=1,prepend=angles[:,:1])/ts
    count = len(u)//n; periods = np.arange(2,count)
    U = rfft(u.reshape(count,n),axis=-1)[periods,1:]
    V = rfft(velocity.reshape(2,count,n),axis=-1)[:,periods,1:]
    f = rfftfreq(n,ts)[1:]; D = (1-np.exp(-2j*np.pi*f*ts))/ts
    suu = np.mean(abs(U)**2,axis=0)
    suy = np.mean(U[None].conj()*V,axis=1)
    syy = np.mean(abs(V)**2,axis=1)
    return f, suy/suu/D, abs(suy)**2/(suu*syy), V/U[None]/D


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--input',type=Path,required=True)
    ap.add_argument('--output',type=Path,default=ROOT/'simulations/audit')
    args = ap.parse_args(); args.output.mkdir(parents=True,exist_ok=True)
    digest = hashlib.sha256(args.input.read_bytes()).hexdigest()
    if digest != EXPECTED_HASH:
        raise ValueError('This audit is restricted to the recorded legacy file; do not reuse its units by filename.')
    data = loadmat(args.input)
    ts,cycle,tend = (float(data[k].item()) for k in ('Ts','Tcycle','Tend'))
    u = data['input'].ravel().astype(float)
    degrees = np.stack([data['motorpos'].ravel(),data['loadpos'].ravel()])
    n = round(cycle/ts)
    if (ts<=0 or n<=0 or u.size != round(tend/ts) or u.size%n
            or degrees.shape != (2,u.size) or not np.all(np.isfinite(degrees))
            or not np.all(np.isfinite(u))):
        raise ValueError('Invalid legacy signal dimensions or values')
    residual = float(np.max(abs(degrees/(360/2**20)-np.round(degrees/(360/2**20)))))
    if residual > 1e-6: raise ValueError('Legacy encoder grid does not match')
    f,h,coherence,period = estimate(u,degrees*np.pi/180,ts,n)
    ix = np.flatnonzero((f>=5)&(f<=700)&np.all(coherence>.85,axis=0))[::2]
    weight = np.sqrt(np.minimum(coherence[:,ix],.995)/np.maximum(1-coherence[:,ix],.03))/np.sqrt(f[ix])
    def error(p):
        e = (response(p,f[ix])/h[:,ix]-1)*weight
        return np.r_[e.real.ravel(),e.imag.ravel()]
    fit = least_squares(error,np.r_[np.log([25000,1,(2*np.pi*235)**2,3,100,250]),.25],
        bounds=(np.r_[np.log([100,.03,1e4,1e-5,1e-5,1e-5]),0.],
                np.r_[np.log([1e6,30,1e8,1e4,1e4,1e4]),1.]),
        loss='soft_l1',f_scale=.2,max_nfev=2000)
    if not fit.success: raise RuntimeError(fit.message)
    a,r,km,cm,bm,bl = np.exp(fit.x[:6])
    p = dict(jm=1/a,jl=r/a,ks=km/a,cs=cm/a,bm=bm/a,bl=bl*r/a,kt=1.,
             effective_delay_s_including_source_zoh=float(fit.x[6]*1e-3))
    A = np.array([[0,1,0,0],[-km,-cm-bm,km,cm],[0,0,0,1],[km/r,cm/r,-km/r,-cm/r-bl]])
    modes = np.linalg.eigvals(A); pole = modes[modes.imag>0][0]
    p['resonance_damped_Hz'] = float(pole.imag/(2*np.pi))
    p['resonance_zeta'] = float(-pole.real/abs(pole))
    saved = json.loads((ROOT/'simulations/data/identified_plant.json').read_text())['parameters']
    relative = {k:float(p[k]/saved[k]-1) for k in ('jm','jl','ks','cs','bm','bl')}
    band = (f>=5)&(f<=700)
    design = json.loads((ROOT/'simulations/higs_design.json').read_text())
    ts8 = design['sample_time_s']; band8 = (f>=1)&(f<=1000)
    fb = f[band8]
    correction = np.sinc(fb*ts8)/np.sinc(fb*ts)*np.exp(-1j*np.pi*fb*(ts8-ts))
    _,C = signal.sosfreqz(design['linear_sos'],worN=2*np.pi*fb*ts8)
    L = C*h[1,band8]*correction
    S = abs(1/(1+L))
    periods = period[1][:,band8]*correction
    extra = np.exp(-2j*np.pi*fb*6*ts8)
    check = dict(band_hz=[1.,1000.],source_Ts_s=ts,controller_Ts_s=ts8,
        peak_sensitivity=float(max(S)),peak_frequency_hz=float(fb[np.argmax(S)]),
        worst_period_sensitivity=float(np.max(abs(1/(1+C*periods)))),
        worst_period_with_six_extra_samples=float(np.max(abs(1/(1+C*periods*extra)))),
        additional_delay_s=6*ts8,
        note='Legacy measured frequency grid with approximate hold correction; not a new 8 kHz measurement or nonlinear stability certificate.')
    at10 = int(np.argmin(abs(f-10)))
    summary = dict(source_sha256=digest,source_Ts_s=ts,samples=len(u),cycle_s=cycle,
        retained_period_indices_one_based=list(range(3,len(u)//n+1)),
        source_angle_unit='degree',model_angle_unit='rad',input_unit='command_A',
        separate_actual_current_present=False,encoder_grid_residual=residual,
        refit_parameters=p,relative_change_from_saved=relative,
        relative_complex_rms_5_700Hz=np.sqrt(np.mean(abs(response(fit.x,f[band])/h[:,band]-1)**2,axis=1)).tolist(),
        model_phase_lead_at_10Hz_deg=np.angle(response(fit.x,f[at10:at10+1])/h[:,at10:at10+1],deg=True).ravel().tolist(),
        linear_legacy_frf_check=check,
        limitations='Same-record refit is a reproducibility check, not independent validation of model adequacy, hardware scaling or current-loop dynamics.')
    (args.output/'chirp_audit_summary.json').write_text(json.dumps(summary,indent=2,allow_nan=False)+'\n')
    np.savez_compressed(args.output/'chirp_audit_frf.npz',freq_hz=f,H_motor=h[0],H_load=h[1],
        coherence=coherence,source_Ts=ts,model_response=response(fit.x,f))
    print(json.dumps(summary,indent=2))
    if max(abs(x) for k,x in relative.items() if k!='bm')>1e-3:
        raise SystemExit('Refit differs materially from saved coefficients; do not silently replace design.')
    if check['worst_period_with_six_extra_samples']>design['sensitivity_limit']:
        raise SystemExit('Legacy linear FRF sensitivity gate failed.')

if __name__=='__main__': main()
