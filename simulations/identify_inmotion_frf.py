"""Reproduce the in-motion current-command to load-position FRF.

Run: python simulations/identify_inmotion_frf.py
Inputs: trials_book/sens_{linear,both}{,_dist}.mat and standstill FRF files.
Output: simulations/hardware/frf/inmotion_ramp.npz (no hardware access).
The first ramp period is discarded. Delete-one-period jackknife uncertainty
and period coherence quantify repeatability, not closed-loop systematic bias.
"""
from pathlib import Path
import json
import numpy as np
from scipy.io import loadmat
from scipy.signal import detrend
from scipy.stats import t as student_t

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'simulations/hardware'
def estimate(y, u):
    n = len(y)
    p = y.mean(axis=0) / u.mean(axis=0)
    pp = y / u
    leave = (y.sum(axis=0) - y) / (u.sum(axis=0) - u)
    dev = leave - leave.mean(axis=0)
    covariance = (n - 1) / n * np.einsum('pif,pjf->fij',
        np.stack([dev.real, dev.imag], axis=1),
        np.stack([dev.real, dev.imag], axis=1))
    complex_se = np.sqrt(np.trace(covariance, axis1=1, axis2=2))
    md = 20 * np.log10(np.abs(leave))
    ph = np.rad2deg(np.angle(leave / p))
    jack_se = lambda a: np.sqrt((n-1) / n * np.sum((a-a.mean(axis=0))**2, axis=0))
    mag_se = jack_se(md)
    phase_se = jack_se(ph)
    crit = student_t.ppf(.975, n - 1)
    coherence = np.abs(np.sum(y * u.conj(), axis=0))**2 / (
        np.sum(np.abs(y)**2, axis=0) * np.sum(np.abs(u)**2, axis=0))
    return dict(P=p, per_period=pp, complex_se=complex_se,
        covariance=covariance, mag_se_db=mag_se, phase_se_deg=phase_se,
        mag95_db=crit*mag_se, phase95_deg=crit*phase_se,
        coherence=coherence, period_complex_std=np.std(pp, axis=0, ddof=1),
        periods=n, t95=float(crit))

def spectrum(x, p, k, discard):
    return np.fft.rfft(np.asarray(x).reshape(-1,p), axis=1)[discard:,k]

def ramp(mode):
    m = loadmat(DATA / 'trials_book' / f'sens_{mode}.mat', simplify_cells=True)
    r = m['raw']
    d = loadmat(DATA / 'trials_book' / f'sens_{mode}_dist.mat', simplify_cells=True)
    p, k = int(d['P']), np.asarray(d['k'],dtype=int)
    assert p==16000 and len(r['load_position'])==6*p
    assert np.array_equal(k,np.arange(5,1000,2))
    assert np.all(np.diff(r['seq'])==1) and np.all(np.diff(r['t_ns'])==62500)
    assert np.array_equal(r['current_cmd'][1:],(r['control_input']+r['dist_value'])[:-1])
    assert np.max(np.abs(np.diff(r['ref_value'][p:])-2*62.5e-6))<1e-12
    y = spectrum(r['load_position']-r['ref_value'],p,k,1)
    u = spectrum(r['current_cmd'],p,k,1)
    out=estimate(y,u)
    fit = detrend(np.asarray(r['load_position']).reshape(-1,p),axis=1,type='linear')
    out['fitted_line_P']=estimate(np.fft.rfft(fit,axis=1)[1:,k],u)['P']
    out['last4_P']=estimate(y[1:],u[1:])['P']
    out['f']=k.astype(float)
    out['reference_slope_rad_s']=float(np.polyfit(r['t_s'][p:],r['ref_value'][p:],1)[0])
    return out,r,d

def standstill(name):
    saved=loadmat(DATA/'frf'/f'frf_{name}.mat',simplify_cells=True)
    raw=loadmat(DATA/'frf'/f'{name}.mat',simplify_cells=True)['raw']
    p=16000;k=np.asarray(saved['f'],dtype=int)
    out=estimate(spectrum(detrend(raw['load_position']),p,k,2),
                 spectrum(raw['current_cmd'],p,k,2))
    out['saved_recompute_relative_error']=float(np.max(np.abs(out['P']/saved['Hl']-1)))
    assert out['saved_recompute_relative_error']<1e-9
    out['P']=np.asarray(saved['Hl'])
    out['f']=k.astype(float)
    return out

def main():
    linear,rl,dl=ramp('linear');both,rh,dh=ramp('both')
    stationary={name:standstill(name) for name in ['ms030','ms060','ms100']}
    assert np.array_equal(dl['u'],dh['u'])
    method={
        'input':'raw.current_cmd (same as standstill Hl); no double addition of dist or ff',
        'output':'raw.load_position - raw.ref_value; reference 2 rad/s after first period',
        'FRF':'mean across retained periods of Y FFT / mean across retained periods of U FFT',
        'sample_period_s':62.5e-6,'period_samples':16000,'ramp_discard_periods':1,
        'standstill_discard_periods':2,'output_input_sample_correction':0,
        'timing':'current_cmd[1:]=(control_input+dist_value)[:-1] exactly; current_cmd and load_position share logger sample; no controller reconstruction',
        'uncertainty':'complex RMS standard error from delete-one-period jackknife; approximate marginal magnitude/phase 95% t halfwidths; coherence is across retained periods at each excited line',
        'weak_signal_limit':'Magnitude/phase t intervals are approximate and unreliable near zero complex response/input; phase halfwidth >=180 degrees is uninformative. Use complex uncertainty, coherence, and period sensitivity to judge these lines.',
        'systematic_limit':'period repeatability does not measure shared deterministic distortion or feedback-correlated bias; runs use identical multisine realization',
        'source_evidence':[
            'matlab/tools/higs_bench/higs_bench_multisine.m:63-73 (discard2; globally detrend positions; Uc=current_cmd; Hl ratio of complex means)',
            'matlab/tools/higs_bench/higs_bench_sensitivity.m:5-7,19,27-40,52-63 (1s period;6 periods; discard1)',
            'DriverAdapter/Module1.cpp:54,56,59,267; ExperimentLogger/Module1.cpp:777-795; LoggerRecord.h:68-76 (same logged sample for load position and current command)',
            'matlab/+experiment/read_logger_bin.m:99; ControllerAlgorithm.cpp:110 (ref_value and load position in same position units)',
        ]}
    arrays=dict(f=linear['f'],P=linear['P'],uncertainty=linear['complex_se'],
        coherence=linear['coherence'],
        uncertainty_definition=np.array('complex RMS standard error from period jackknife; same units as P (rad/A)'),
        runs=np.array(['linear','HIGS']),P_runs=np.stack([linear['P'],both['P']]),
        uncertainty_runs=np.stack([linear['complex_se'],both['complex_se']]),
        metadata=np.array(json.dumps(method)))
    for mode,a in [('linear',linear),('HIGS',both)]:
        for key in ['P','complex_se','covariance','per_period','period_complex_std','mag_se_db','phase_se_deg','mag95_db','phase95_deg','coherence','fitted_line_P','last4_P']:
            arrays[f'{mode}_{key}']=a[key]
    for name,a in stationary.items():
        for key in ['f','P','complex_se','mag95_db','phase95_deg','coherence','per_period']:
            arrays[f'{name}_{key}']=a[key]
    target = DATA / 'frf/inmotion_ramp.npz'
    np.savez_compressed(target,**arrays)
    print(f'Saved {target.relative_to(ROOT)}: {len(linear["f"])} lines, 5 retained ramp periods per run')


if __name__ == '__main__':
    main()
