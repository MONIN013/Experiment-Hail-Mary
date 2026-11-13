#!/usr/bin/env python3
"""Recheck a saved HIGS design without the raw MAT or measured_frf.npz.

Uses the unchanged ControllerAlgorithm.cpp and higs_host.cpp. This is a finite
model-based audit, not a fresh identification or a hardware/stability approval.
Run from the repository: python simulations/audit_higs.py
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

def save(path, obj):
    path.write_text(json.dumps(obj, indent=2, allow_nan=False,
        default=lambda v: v.tolist() if isinstance(v, np.ndarray) else v.item())+'\n')

def plant(p, ts):
    jm, jl, k, c, bm, bl, kt = [p[n] for n in ('jm','jl','ks','cs','bm','bl','kt')]
    a = np.array([[0,1,0,0],[-k/jm,-(bm+c)/jm,k/jm,c/jm],
                  [0,0,0,1],[k/jl,c/jl,-k/jl,-(bl+c)/jl]])
    b = np.array([[0],[kt/jm],[0],[0]])
    ad, bd, _, _, _ = signal.cont2discrete((a,b,np.eye(4),np.zeros((4,1))),ts)
    return ad, bd[:,0]

class Host:
    def __init__(self):
        self.temp = tempfile.TemporaryDirectory(prefix='higs-audit-')
        library = Path(self.temp.name)/'higs.so'
        subprocess.run([os.environ.get('CXX','g++'),'-std=c++17','-O2','-shared','-fPIC',
            '-Wall','-Wextra','-Werror','-I'+str(ROOT/'ControllerCore'),
            str(ROOT/'ControllerCore/ControllerAlgorithm.cpp'),str(ROOT/'simulations/higs_host.cpp'),
            '-o',str(library)],check=True)
        self.lib = ctypes.CDLL(str(library))
        self.fn = self.lib.simulate_higs
        ptr = np.ctypeslib.ndpointer(dtype=np.float64,flags='C_CONTIGUOUS')
        self.fn.argtypes = [ctypes.c_int]+[ptr]*6+[ctypes.c_uint,ctypes.c_int,
            ctypes.c_double,ctypes.c_double,ctypes.c_uint,ctypes.c_int,
            ctypes.c_double,ctypes.c_double,ctypes.c_double,ptr,ptr]
        self.fn.restype = ctypes.c_int

    def run(self, design, p, r, *, higs=False, delay=2, disturbance=None,
            noise=None, initial=None, quantized=True):
        n = len(r)
        a,b = plant(p,design['sample_time_s'])
        sos = np.asarray(design['higs_sos' if higs else 'linear_sos'])
        coef = np.ascontiguousarray(sos[:,[0,1,2,4,5]])
        out = np.zeros((n,11))
        vector = lambda x: np.ascontiguousarray(x,dtype=np.float64)
        code = self.fn(n,vector(r),vector(np.zeros(n) if disturbance is None else disturbance),
            vector(np.zeros(n) if noise is None else noise),vector(a),vector(b),coef,len(sos),int(higs),
            design['higs_gain'],design['higs_omega_ts'],design['pre_section_count'],delay,
            design['max_current_a'],.0016 if quantized else 0.,
            2*np.pi/8388608 if quantized else 0.,vector(np.zeros(4) if initial is None else initial),out)
        if code: raise RuntimeError(f'Host failed: {code}')
        return out


def reference(d, amplitude=None, move=None):
    amp = d['reference_amplitude_rad'] if amplitude is None else amplitude
    move = d['move_time_s'] if move is None else move
    ts,hold,settle = d['sample_time_s'],d['dwell_time_s'],d['settle_time_s']
    t = np.arange(round((2*settle+2*move+hold)/ts)+1)*ts
    smooth = lambda q:q**4*(35-84*q+70*q*q-20*q**3)
    r = amp*(smooth(np.clip((t-settle)/move,0,1))-smooth(np.clip((t-settle-move-hold)/move,0,1)))
    return t,r


def metrics(r, out, d, disturbance=None, t=None):
    e = r-out[:,2]
    rms = lambda x:float(np.sqrt(np.mean(x*x)))
    demand = out[:,4]+(0. if disturbance is None else disturbance)
    m = {'rms_rad':rms(e),'tail_rms_rad':rms(e[-round(.2/d['sample_time_s']):]),
         'peak_error_rad':float(np.max(abs(e))), 'peak_demand_a':float(np.max(abs(demand))),
         'peak_applied_a':float(np.max(abs(out[:,5]))),'current_rms_a':rms(out[:,5]),
         'peak_position_rad':float(np.max(abs(out[:,[0,2]]))),
         'peak_speed_rad_s':float(np.max(abs(out[:,[1,3]]))),
         'peak_twist_rad':float(np.max(abs(out[:,0]-out[:,2]))),'clipped_samples':int(out[:,10].sum())}
    m['within_envelope'] = bool(m['clipped_samples']==0 and m['peak_demand_a']<d['max_current_a']
        and m['peak_position_rad']<d['max_position_rad'] and m['peak_speed_rad_s']<d['max_velocity_rad_s']
        and m['peak_twist_rad']<d['max_twist_rad'])
    if t is not None:
        start,move,hold = d['settle_time_s'],d['move_time_s'],d['dwell_time_s']
        moving=((t>=start)&(t<start+move))|((t>=start+move+hold)&(t<start+2*move+hold))
        plateau=(t>=start+move)&(t<start+move+hold)
        m.update(moving_rms_rad=rms(e[moving]),plateau_rms_rad=rms(e[plateau]))
    # Check the invariant with a scale-dependent floating-point tolerance.
    z,h = out[:,7],out[:,8]
    bound=d['higs_gain']*z
    tolerance=64*np.finfo(float).eps*np.maximum(np.maximum(abs(h),abs(bound)),1e-300)
    m['sector_violations']=int(np.sum((h<np.minimum(0,bound)-tolerance)|(h>np.maximum(0,bound)+tolerance)))
    return m


def linear_check(d, p, delay=2):
    """Unsaturated saved-model linear loop; stability is not inferred from |S|."""
    ts=d['sample_time_s']; a,b=plant(p,ts); sos=np.asarray(d['linear_sos'])
    size=4+2*len(sos)+delay
    def advance(x):
        nxt=np.zeros(size); u=-x[2]
        for j,row in enumerate(sos):
            at=4+2*j; y=row[0]*u+x[at]
            nxt[at]=row[1]*u-row[4]*y+x[at+1]
            nxt[at+1]=row[2]*u-row[5]*y; u=y
        applied=x[-delay] if delay else u
        nxt[:4]=a@x[:4]+b*applied
        if delay: nxt[-delay:]=np.r_[x[-delay+1:] if delay>1 else [],u]
        return nxt
    radius=float(np.max(abs(np.linalg.eigvals(np.column_stack([advance(x) for x in np.eye(size)])))))
    f=np.geomspace(.01,.5/ts-1,6000); z=np.exp(2j*np.pi*f*ts)
    G=np.linalg.solve(z[:,None,None]*np.eye(4)-a,np.broadcast_to(b[:,None],(len(f),4,1)))[:,2,0]
    _,C=signal.sosfreqz(sos,worN=2*np.pi*f*ts)
    return {'spectral_radius':radius,'stable':radius<1.,
            'peak_sensitivity':float(np.max(abs(1/(1+C*G/z**delay))))}


def candidate(d,corner,shaping=0.):
    ts=d['sample_time_s']; wl=2*np.pi*d['tuning']['lowpass_hz']; wc=2*np.pi*corner
    def section(b,a):
        bz,az=signal.bilinear(b,a,fs=1/ts)
        return np.r_[np.pad(bz,(0,3-len(bz))),np.pad(az,(0,3-len(az)))]
    num=np.array([wl*wl/wc,wl*wl]); den=[1,np.sqrt(2)*wl,wl*wl]
    pre=[]
    if shaping:
        ww=2*np.pi*shaping
        pre=[section([ww],[1,ww])]
        num=np.convolve([1,ww],num)/ww
    sos=np.vstack(pre+[section(num,den),np.array(d['linear_sos'][0]),np.array(d['linear_sos'][1])])
    return d|{'higs_sos':sos,'pre_section_count':len(pre),
              'higs_omega_ts':wc*ts/np.sqrt(1+16/np.pi**2)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'simulations/audit')
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    d=json.loads((ROOT/'simulations/higs_design.json').read_text())
    identified=json.loads((ROOT/'simulations/data/identified_plant.json').read_text())
    p=identified['parameters']; ts=d['sample_time_s']; host=Host();t,r=reference(d)
    result={'scope':'Saved coefficients/model only. No raw-data refit, ADS, MATLAB, TwinCAT build or hardware execution.',
        'source_chirp_sha256':identified['source_sha256'], 'model_parameters':{k:p[k] for k in ['jm','jl','ks','cs','bm','bl','kt']},
        'files_sha256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in
            ['ControllerCore/ControllerAlgorithm.cpp','ControllerCore/ControllerAlgorithm.h','simulations/higs_host.cpp']},
        'sample_time_s':ts,'quantization_assumptions':{'current_a':.0016,'encoder_counts':8388608},
        'cases':[],'corner_scan':[],'tuning_exploration':[]}
    traces={}
    def pair(name,ref,model=p,design=d,kind='validation',**kwargs):
        report={'name':name,'kind':kind}
        for key in ['linear','higs']:
            trace=host.run(design,model,ref,higs=key=='higs',**kwargs)
            report[key]=metrics(ref,trace,design,kwargs.get('disturbance'),t if name=='nominal' else None)
            if name=='nominal':traces[key]=trace
        report['rms_reduction_percent']=100*(1-report['higs']['rms_rad']/report['linear']['rms_rad'])
        result['cases'].append(report)
        return report
    pair('nominal',r)
    pair('unquantized',r,quantized=False)
    for amp in [.001,.01,.2]:pair(f'amplitude_{amp}',reference(d,amplitude=amp)[1])
    for move in [.05,.2]:pair(f'move_{move}',reference(d,move=move)[1])
    t6=np.arange(round(6/ts))*ts
    pair('initial_displacement',np.zeros_like(t6),initial=[.005,0,.005,0])
    pair('dc_on_off',np.zeros_like(t6),disturbance=.005*((t6>.5)&(t6<3.5)))
    pair('two_tone_disturbance',np.zeros_like(t6),disturbance=.005*np.sin(2*np.pi*3*t6)+.002*np.sin(2*np.pi*313*t6))
    pair('multisine_reference',.02*np.sin(2*np.pi*3*t6)+.01*np.sin(2*np.pi*11*t6)+.004*np.sin(2*np.pi*37*t6))
    pair('encoder_noise',r,noise=np.random.default_rng(728).normal(0,10*2*np.pi/8388608,len(r)))
    for delay in [1,4,8,16,32,40,48,64]:
        q=pair(f'delay_{delay}',r,delay=delay,kind='delay_stress')
        q['extra_explicit_delay_s']=delay*ts
    for jm,jl,k,c,b,delay in itertools.product([.8,1.2],[.8,1.2],[.8,1.2],[.5,1.5],[.5,1.5],[1,4,8]):
        pp=p|{'jm':p['jm']*jm,'jl':p['jl']*jl,'ks':p['ks']*k,'cs':p['cs']*c,'bm':p['bm']*b,'bl':p['bl']*b}
        q=pair(f'Jm{jm}_Jl{jl}_K{k}_C{c}_B{b}_d{delay}',r,model=pp,delay=delay,kind='corner')
        q['linear_check']=linear_check(d,pp,delay)
        result['corner_scan'].append(q)
    for corner,shaping in itertools.product([5.,10.,20.,40.,60.,100.],[0.,20.,40.,80.]):
        dd=candidate(d,corner,shaping)
        out=host.run(dd,p,r,higs=True)
        initial=host.run(dd,p,np.zeros_like(t6),higs=True,initial=[.005,0,.005,0])
        result['tuning_exploration'].append({'corner_hz':corner,'prefilter_hz':shaping,
            'tracking':metrics(r,out,dd,t=t),'initial_displacement':metrics(np.zeros_like(t6),initial,dd)})
    # Replace HIGS by the bilinear representative LPF H. H*V must recover C_L.
    wc=2*np.pi*d['tuning']['higs_corner_hz']
    bz,az=signal.bilinear([wc],[1,wc],fs=1/ts)
    hs=np.r_[np.pad(bz,(0,3-len(bz))),np.pad(az,(0,3-len(az)))]
    all_sos=np.insert(np.asarray(d['higs_sos']),d['pre_section_count'],hs,axis=0)
    omega=2*np.pi*ts*np.geomspace(.01,.49/ts,10000)
    _,linear=signal.sosfreqz(d['linear_sos'],worN=omega)
    _,reconstructed=signal.sosfreqz(all_sos,worN=omega)
    error=float(np.max(abs(reconstructed/linear-1)))
    result['linear_replacement_max_relative_error']=error
    result['linear_nominal_check']=linear_check(d,p)
    result['linear_corner_stability_pass']=all(q['linear_check']['stable'] for q in result['corner_scan'])
    result['worst_linear_corner_sensitivity']=max(q['linear_check']['peak_sensitivity'] for q in result['corner_scan'])
    result['corner_count']=len(result['corner_scan'])
    result['corner_reduction_range_percent']=[min(q['rms_reduction_percent'] for q in result['corner_scan']),max(q['rms_reduction_percent'] for q in result['corner_scan'])]
    result['corner_envelope_pass']=all(q[key]['within_envelope'] for q in result['corner_scan'] for key in ['linear','higs'])
    result['sector_violation_count']=sum(q['higs']['sector_violations'] for q in result['cases'])
    np.savez_compressed(args.output/'nominal_traces.npz',t=t,reference=r,**traces)
    save(args.output/'audit_summary.json',result)
    if not (result['corner_envelope_pass'] and result['sector_violation_count']==0 and error<1e-8
            and result['linear_corner_stability_pass'] and result['linear_nominal_check']['stable']
            and result['worst_linear_corner_sensitivity']<=d['sensitivity_limit']):
        raise SystemExit('Saved-design regression failed; inspect audit_summary.json')
    print(json.dumps({k:result[k] for k in ['corner_count','corner_reduction_range_percent','corner_envelope_pass','sector_violation_count','linear_replacement_max_relative_error']},indent=2))
    for q in result['cases']:
        if q['kind']!='corner':print(q['name'],q['rms_reduction_percent'],q['linear']['rms_rad'],q['higs']['rms_rad'],q['higs']['within_envelope'])

if __name__=='__main__':main()
