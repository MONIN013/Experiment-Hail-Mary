#!/usr/bin/env python3
"""Identify a command-current to motor/load-angle model from the legacy MAT log.

Example:
  python simulations/identify_chirp.py --input /path/to/chirp_result.mat

Angles in this legacy file are degrees (the historic chirp_openloop.m states
this explicitly). The current repo logger uses radians and is a different
format. The fit is an effective, current-normalized passive two-inertia model,
not a measurement of the motor torque constant or a stability certificate.
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


def response(p, f):
    """p: logs of Kt/Jm, Jl/Jm, K/Jm, c/Jm, Bm/Jm, Bl/Jl; delay in ms."""
    a, r, km, cm, bm, bl = np.exp(p[:6])
    s = 2j * np.pi * f
    coupling = km + cm * s
    dm = s*s + bm*s + coupling
    dl = r*s*s + r*bl*s + coupling
    determinant = dm*dl - coupling*coupling
    return a * np.stack([dl, coupling]) / determinant * np.exp(-s*p[6]*1e-3)


def estimate_frf(u, angles, ts, cycle_samples, periods):
    # Backward difference belongs to the CURRENT angle sample, including cycle
    # boundaries. Its exact inverse restores AC position without ramp leakage.
    velocity = np.diff(angles, axis=1, prepend=angles[:, :1]) / ts
    count = u.size // cycle_samples
    U = rfft(u.reshape(count, cycle_samples), axis=-1)
    V = rfft(velocity.reshape(2, count, cycle_samples), axis=-1)
    f = rfftfreq(cycle_samples, ts)[1:]
    U, V = U[:, 1:], V[:, :, 1:]
    diff_operator = (1 - np.exp(-2j*np.pi*f*ts)) / ts
    suu = np.mean(abs(U[periods])**2, axis=0)
    suy = np.mean(U[None, periods].conj()*V[:, periods], axis=1)
    syy = np.mean(abs(V[:, periods])**2, axis=1)
    h = suy / suu / diff_operator
    coherence = abs(suy)**2 / (suu*syy)
    individual = V[:, periods] / U[None, periods] / diff_operator
    return f, h, coherence, individual


def fit_model(f, h, coherence, band=(5., 700.), start=None):
    good = (f >= band[0]) & (f <= band[1]) & np.all(coherence > .85, axis=0)
    # Every other line reduces compute; 0.2 Hz spacing resolves the ~314 Hz mode.
    ix = np.flatnonzero(good)[::2]
    weight = np.sqrt(np.minimum(coherence[:, ix], .995) /
                     np.maximum(1-coherence[:, ix], .03)) / np.sqrt(f[ix])
    if start is None:
        start = np.r_[np.log([25000, 1, (2*np.pi*235)**2, 3, 100, 250]), .25]
    lower = np.r_[np.log([100, .03, 1e4, 1e-5, 1e-5, 1e-5]), 0.]
    upper = np.r_[np.log([1e6, 30, 1e8, 1e4, 1e4, 1e4]), 1.]
    def residual(p):
        e = (response(p, f[ix])/h[:, ix]-1)*weight
        return np.r_[e.real.ravel(), e.imag.ravel()]
    result = least_squares(residual, start, bounds=(lower, upper),
                           loss='soft_l1', f_scale=.2, max_nfev=2000)
    if not result.success:
        raise RuntimeError(result.message)
    return result.x


def model_parameters(p):
    a, r, km, cm, bm, bl = np.exp(p[:6])
    A = np.array([[0,1,0,0],[-km,-cm-bm,km,cm],
                  [0,0,0,1],[km/r,cm/r,-km/r,-cm/r-bl]])
    modes = np.linalg.eigvals(A)
    mode = modes[np.imag(modes)>0][0]
    return dict(jm=1/a, jl=r/a, ks=km/a, cs=cm/a, bm=bm/a, bl=bl*r/a,
                kt=1., A=A.tolist(), B=[0,a,0,0],
                effective_delay_s_including_source_zoh=p[6]*1e-3,
                resonance_damped_Hz=mode.imag/(2*np.pi),
                resonance_natural_Hz=abs(mode)/(2*np.pi),
                resonance_zeta=-mode.real/abs(mode),
                motor_zero_natural_Hz=np.sqrt(km/r)/(2*np.pi))


def errors(f, h, p):
    table = {}
    for lo, hi in [(5,20),(20,50),(50,150),(150,250),(250,400),(400,700),(5,700)]:
        mask = (f >= lo) & (f <= hi)
        ratio = response(p, f[mask])/h[:, mask]
        table[f'{lo}-{hi}Hz'] = dict(
            relative_complex_rms=np.sqrt(np.mean(abs(ratio-1)**2, axis=1)).tolist(),
            gain_error_dB_p05_p95=np.percentile(20*np.log10(abs(ratio)), [5,95],axis=1).tolist(),
            phase_error_deg_p05_p95=np.percentile(np.angle(ratio,deg=True), [5,95],axis=1).tolist())
    return table


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--input', dest='mat', type=Path, required=True)
    ap.add_argument('--output', dest='out', type=Path, default=Path(__file__).resolve().parent/'data')
    ap.add_argument('--skip-periods', type=int, default=2)
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    data = loadmat(args.mat)
    ts = float(data['Ts'].item()); tc = float(data['Tcycle'].item())
    tend = float(data['Tend'].item())
    if not all(np.isfinite(x) and x > 0 for x in (ts,tc,tend)):
        raise ValueError('Ts, Tcycle and Tend must be positive finite scalars')
    n = round(tc/ts)
    u = data['input'].ravel().astype(float)
    angle_recorded = np.stack([data['motorpos'].ravel(),data['loadpos'].ravel()])
    if (abs(n*ts-tc) > 16*np.spacing(tc) or u.size != round(tend/ts) or u.size % n or
        angle_recorded.shape != (2,u.size) or
        not np.all(np.isfinite(u)) or not np.all(np.isfinite(angle_recorded))):
        raise ValueError('Sample count, periods, or finite-signal validation failed')
    count = u.size//n
    if not 0 <= args.skip_periods <= count-4:
        raise ValueError('Need at least four complete retained periods')
    quantum = 360/2**20
    quantum_residual = np.max(abs(angle_recorded/quantum-np.round(angle_recorded/quantum)))
    if quantum_residual > 1e-6 or np.any(np.ptp(angle_recorded,axis=1) <= quantum):
        raise ValueError('Expected nontrivial legacy degree angles on the 360/2**20 encoder grid')
    angles = angle_recorded*np.pi/180
    periods = np.arange(args.skip_periods, count)
    f,h,coherence,individual = estimate_frf(u, angles, ts, n, periods)
    p = fit_model(f,h,coherence)
    params = model_parameters(p)
    ratio_mask = (f >= 10) & (f <= 700) & np.all(coherence>.9, axis=0)
    ix = np.flatnonzero(ratio_mask)[::2]
    def ratio_response(logp):
        kl,cl,bl=np.exp(logp);s=2j*np.pi*f[ix]
        return (cl*s+kl)/(s*s+(cl+bl)*s+kl)
    weight=np.sqrt(np.minimum(coherence[:,ix].min(axis=0),.995)/
                   np.maximum(1-coherence[:,ix].min(axis=0),.02))/np.sqrt(f[ix])
    def ratio_residual(logp):
        e=(ratio_response(logp)/(h[1,ix]/h[0,ix])-1)*weight
        return np.r_[e.real,e.imag]
    fit_ratio=least_squares(ratio_residual,np.log([(2*np.pi*235)**2,1,2*np.pi*40]),
        bounds=(np.log([1e5,1e-5,1e-4]),np.log([1e8,1e4,1e4])),
        loss='soft_l1',f_scale=.2,max_nfev=1000)
    kl,cl,bl=np.exp(fit_ratio.x)
    # Train/validation split uses non-overlapping repetitions of the same chirp.
    # This tests repeatability, not unseen amplitudes or different excitation.
    split=len(periods)//2
    ft,ht,ct,_=estimate_frf(u,angles,ts,n,periods[:split])
    fv,hv,cv,_=estimate_frf(u,angles,ts,n,periods[split:])
    pt=fit_model(ft,ht,ct,start=p)
    heldout=errors(fv,hv,pt)
    variant_parameters={}
    for band in [(10.,700.),(20.,700.),(50.,700.)]:
        pv=fit_model(f,h,coherence,band,start=p)
        variant_parameters[f'{band[0]:g}-{band[1]:g}Hz']=model_parameters(pv)
    # Export the ORIGINAL 16 kHz measured response. Do not relabel source_Ts
    # as a new controller rate: a new rate requires a fresh hardware record.
    # Retain 0.1 Hz around feedback crossover, 0.2 Hz near the torsional mode,
    # and 1 Hz elsewhere. The remaining lines are reproducible from the source.
    lines=np.arange(1,len(f)+1)
    keep=(f<=4000)&((lines%10==0)|((f>=1)&(f<=100))|
                   ((f>=180)&(f<=360)&(lines%2==0)))
    payload=dict(freq_hz=f[keep],H_motor=h[0,keep],H_load=h[1,keep],
        coherence_motor=coherence[0,keep],coherence_load=coherence[1,keep],
        period_motor=individual[0,:,keep].T,period_load=individual[1,:,keep].T,
        source_Ts=ts,angle_unit='rad',input_unit='command_A')
    np.savez_compressed(args.out/'measured_frf.npz',**payload)
    metadata_coherence={}
    for lo,hi in [(0.1,5),(5,20),(20,50),(50,200),(200,700),(700,1000),(1000,2000),(2000,4000)]:
        mask=(f>=lo)&(f<hi)
        metadata_coherence[f'{lo:g}-{hi:g}Hz']=dict(median=np.median(coherence[:,mask],axis=1).tolist(),
            p05=np.quantile(coherence[:,mask],.05,axis=1).tolist(),
            fraction_over_0p9=np.mean(coherence[:,mask]>.9,axis=1).tolist())
    t=np.arange(n)*ts
    amplitude=float(np.max(abs(u)))
    early=128
    phase=np.arcsin(u[:early]/amplitude)/(2*np.pi)
    chirp_coeff=np.linalg.lstsq(np.column_stack([t[:early],t[:early]**2/2]),phase,rcond=None)[0]
    # Recover human-specified waveform settings, then check the ENTIRE cycle.
    # This rounding is only for provenance; the FRF uses the recorded samples.
    amplitude=round(amplitude,6)
    chirp_coeff=np.round(chirp_coeff,6)
    chirp_model=amplitude*np.sin(2*np.pi*(chirp_coeff[0]*t+chirp_coeff[1]*t*t/2))
    meta=dict(source_file=args.mat.name,source_sha256=hashlib.sha256(args.mat.read_bytes()).hexdigest(),
        source_Ts_s=ts,Tcycle_s=tc,Tend_s=tend,samples=u.size,periods=count,
        historic_source_url='https://github.com/MONIN013/Experiment-Hail-Mary/blob/6bb96d39135b98355a68ebc68de5167a1733b87d/matlab/experiment/proto/chirp_openloop.m',
        historic_source_note='The historic script declares control input [A] and both positions [deg], with exactly the same saved fields. It lists a 4 kHz sweep end and a commented 1.25e-4 s example; actual Ts came from an external config.mat that is absent from the repository history.',
        source_chirp=dict(type='linear',amplitude_A=amplitude,start_Hz=float(chirp_coeff[0]),
            end_Hz=float(chirp_coeff[0]+tc*chirp_coeff[1]),period_s=tc,
            first_period_max_formula_error_A=float(np.max(abs(u[:n]-chirp_model))),
            repeat_max_error_except_last_sample_A=float(np.max(abs(u.reshape(count,n)[:,:-1]-u[:n-1])))),
        retained_period_indices_one_based=(periods+1).tolist(),
        input_unit='command A (historic control-input label and exact chirp reproduction; no separate actual-current channel is saved)',
        source_angle_unit='degree (historic source and exact 360/2^20 quantization)',
        model_angle_unit='rad',angle_quantum_degree=quantum,
        quantum_integer_residual=float(quantum_residual),
        frf_method='Remove first two periods by default; backward difference across original sample boundaries, rectangular nonoverlapping 10 s period spectra, H1 cross spectrum, then inverse (1-exp(-j*w*Ts))/Ts. No DC position estimate. Coherence is across retained periods.',
        coherence_summary=metadata_coherence,
        fit_method='Joint complex relative error, nonnegative two-inertia parameters plus common effective delay; soft_l1 robust loss, capped coherence weights, approximately equal weight per log-frequency interval; 0.2 Hz fit grid.',
        input_mean_A_per_period=u.reshape(count,n).mean(axis=1).tolist(),
        position_increment_degree_per_period=(angle_recorded.reshape(2,count,n)[:,:,-1]-angle_recorded.reshape(2,count,n)[:,:,0]).tolist(),
        fit_band_Hz=[5,700],fit_channel_order=['motor','load'],
        normalization='Kt=1; jm,jl,ks,cs,bm,bl are effective current-normalized quantities, not independently identified physical constants',
        parameters=params,fit_errors=errors(f,h,p),
        train_period_indices_one_based=(periods[:split]+1).tolist(),
        heldout_period_indices_one_based=(periods[split:]+1).tolist(),
        heldout_errors=heldout,fit_band_variants=variant_parameters,
        ratio_fit=dict(antiresonance_natural_Hz=np.sqrt(kl)/(2*np.pi),
                       antiresonance_zeta=(cl+bl)/(2*np.sqrt(kl)),k_Jl=kl,c_Jl=cl,Bl_Jl=bl),
        nominal_extra_delay_samples_at_8k=2,
        caveats=[
          'The passive four-state fit has material phase error around 10-30 Hz; check controller directly against the measured FRF and all retained periods.',
          'Bm reaches the nonnegative optimization boundary; the viscous split and shaft damping are not independent physical measurements.',
          'Coherence measures repetition consistency; repeatable nonlinear distortion can remain highly coherent.',
          'This is a legacy 16 kHz acquisition with 20-bit angle quantization; the present 8 kHz/23-bit configuration requires fresh identification.',
          'Subtracting source_Ts/2 from effective delay assumes simultaneous zero-order-held command/output sampling. Original logger timing and current-loop dynamics remain unresolved.',
          'The exported FRF retains source_Ts=1/16000 and is not a replacement for a fresh 8 kHz plant.mat.',
          'The source chirp has nonzero mean and large, variable rotation offsets; low-frequency drift is not a universal LTI model.'])
    (args.out/'identified_plant.json').write_text(json.dumps(meta,indent=2))
    lines=['# Identification from the legacy chirp record', '',
        f'- Source SHA-256: `{meta["source_sha256"]}`',
        '- Input: current command [A]; angles: recorded degrees converted to radians.',
        f'- Acquisition: {1/ts:g} Hz, {count} periods of {tc:g} s; periods {periods[0]+1}–{periods[-1]+1} retained.',
        f'- Source unit declaration: {meta["historic_source_url"]}',
        '- Source sampling metadata is preserved. These files do not replace fresh identification at the current controller rate.', '',
        '## Effective four-state model', '',
        'The normalization is Kt=1. The fitted values are divided by the unknown effective torque constant; they are not independent measurements of physical inertia or damping.', '',
        '| Quantity | Value |', '|---|---:|']
    for name in ['jm','jl','ks','cs','bm','bl','effective_delay_s_including_source_zoh','resonance_damped_Hz','resonance_zeta']:
        lines.append(f'| {name} | {params[name]:.9g} |')
    lines += ['', 'The nominal fit uses 5–700 Hz. Band variants are included in the JSON. Bm reaches the nonnegative optimization boundary. The motor/load ratio independently places the antiresonance near '+f'{np.sqrt(kl)/(2*np.pi):.3f} Hz.', '',
        '## Fit quality', '', '| Band | Motor complex RMS error | Load complex RMS error |', '|---|---:|---:|']
    for name,table in meta['fit_errors'].items():
        em,el=table['relative_complex_rms'];lines.append(f'| {name} | {em:.1%} | {el:.1%} |')
    em,el=heldout['5-700Hz']['relative_complex_rms']
    lines += ['', f'Training on periods {periods[0]+1}–{periods[split-1]+1} and checking periods {periods[split]+1}–{periods[-1]+1} gives {em:.1%} motor / {el:.1%} load complex RMS error. This checks repetition consistency, not a new input amplitude.', '',
        '## Limits for controller design', '',
        'The nominal load model is about 17 degrees too optimistic in phase at 10 Hz. Check the controller against the measured response and every retained period, then obtain a fresh record with the present hardware configuration.', '',
        'The fitted common delay includes source zero-order hold, acquisition alignment and unmodeled current-loop dynamics. Subtracting half of the original sample period assumes a known simultaneous command/output timestamp, which this old MAT does not contain.', '',
        'The chirp has a nonzero mean, and its rotation offset varies considerably between periods. High coherence does not exclude repeatable nonlinear friction. The fit should not be extrapolated to arbitrary small-signal stiction or treated as a proof of HIGS stability.', '',
        '## Reproduce', '', '```bash', 'python simulations/identify_chirp.py --input /path/to/chirp_result.mat', '```', '',
        f'The raw MAT is external and is not committed. measured_frf.npz covers 1–4000 Hz, retaining 0.1 Hz spacing at 1–100 Hz, 0.2 Hz at 180–360 Hz and 1 Hz elsewhere; each period array has shape ({len(periods)}, frequency_count).']
    (args.out/'identification_summary.md').write_text('\n'.join(lines)+'\n')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    band=(f>=.5)&(f<=1400)
    fig,ax=plt.subplots(3,2,figsize=(12,9),sharex=True,constrained_layout=True)
    hh=response(p,f[band])
    for ch,name in enumerate(['motor','load']):
        for per in individual[ch]:
            ax[0,ch].semilogx(f[band],20*np.log10(abs(per[band])),color='.8',lw=.4)
        ax[0,ch].semilogx(f[band],20*np.log10(abs(h[ch,band])),label='measured H1',lw=.7)
        ax[0,ch].semilogx(f[band],20*np.log10(abs(hh[ch])),label='four-state fit (5-700 Hz)',lw=1.3)
        ax[1,ch].semilogx(f[band],np.unwrap(np.angle(h[ch,band]))*180/np.pi,lw=.7)
        ax[1,ch].semilogx(f[band],np.unwrap(np.angle(hh[ch]))*180/np.pi,lw=1.3)
        ax[2,ch].semilogx(f[band],coherence[ch,band],lw=.7)
        ax[0,ch].set_title(name);ax[0,ch].legend();ax[0,ch].set_ylabel('gain [dB rad/A]')
        ax[1,ch].set_ylabel('phase [degree]');ax[2,ch].set_ylabel('period coherence')
        ax[2,ch].set_xlabel('frequency [Hz]');ax[2,ch].set_ylim(0,1.02)
        for aa in ax[:,ch]:aa.grid(True,which='both',alpha=.3)
    fig.savefig(args.out/'identification.png',dpi=160)
    print(json.dumps(dict(parameters=params,ratio_fit=meta['ratio_fit'],
        errors=meta['fit_errors']['5-700Hz'],heldout=heldout['5-700Hz']),indent=2))


if __name__=='__main__':
    main()
