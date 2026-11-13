#!/usr/bin/env python3
"""Recheck a saved HIGS design without the raw MAT or measured_frf.npz.

Uses the unchanged ControllerAlgorithm.cpp and higs_host.cpp. This is a finite
model-based audit, not a fresh identification or a hardware/stability approval.
Run from the repository: python simulations/audit_higs.py
"""
from __future__ import annotations
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import numpy as np
from scipy import signal
from higs_two_inertia import Host as RuntimeHost, make_design

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

class Host(RuntimeHost):
    def run(self, design, p, r, *, mode="linear", delay=2, disturbance=None,
            noise=None, initial=None, quantized=True):
        baseline, _, _ = candidate(design)
        controller = baseline | dict(higs_lp_enabled=mode in ("lowpass", "both"),
                                     higs_i_enabled=mode in ("integrator", "both"))
        model = dict(jm=p['jm'], jl=p['jl'], bm=p['bm'], bl=p['bl'],
                     stiffness=p['ks'], damping=p['cs'], torque_constant=p['kt'])
        return super().run(controller, r, disturbance, model=model, delay=delay,
            noise=noise, initial=initial, quantized=quantized, current_limit=design['max_current_a'])


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
    m['sector_violations'] = 0
    for name, col in [('lp', 7), ('i', 11)]:
        z,h,mode = out[:,col],out[:,col+1],out[:,col+2]
        bound=d['tuning'][f'higs_{name}_gain']*z
        tolerance=64*np.finfo(float).eps*np.maximum(np.maximum(abs(h),abs(bound)),1e-300)
        violations=(h<np.minimum(0,bound)-tolerance)|(h>np.maximum(0,bound)+tolerance)
        m['sector_violations'] += int(np.sum(violations & (mode != 0)))
    return m


def linear_check(d, p, delay=2):
    """Unsaturated saved-model linear loop; stability is not inferred from |S|."""
    ts=d['sample_time_s']; a,b=plant(p,ts); sos=np.asarray(candidate(d)[0]['linear_sos'])
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


def candidate(d):
    tuning=d['tuning']
    return make_design(crossover_hz=tuning['measured_crossover_target_hz'],
        lowpass_hz=tuning['lowpass_hz'],
        integral_hz=tuning['integral_hz'], lead_zero_hz=tuning['lead_zero_hz'],
        lead_pole_hz=tuning['lead_pole_hz'],
        higs_lp_corner_hz=tuning['higs_lp_corner_hz'], higs_i_corner_hz=tuning['higs_i_corner_hz'],
        higs_lp_gain=tuning['higs_lp_gain'], higs_i_gain=tuning['higs_i_gain'], kp=tuning['kp'])


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
        for key in ['linear','integrator','lowpass','both']:
            trace=host.run(design,model,ref,mode=key,**kwargs)
            report[key]=metrics(ref,trace,design,kwargs.get('disturbance'),t if name=='nominal' else None)
            if name=='nominal':traces[key]=trace
        report['rms_reduction_percent']=100*(1-report['both']['rms_rad']/report['linear']['rms_rad'])
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
    for lp_corner,i_corner in itertools.product([20.,60.,100.],[1.,2.,5.]):
        dd=d|{'tuning':d['tuning']|{'higs_lp_corner_hz':lp_corner,'higs_i_corner_hz':i_corner}}
        out=host.run(dd,p,r,mode='both')
        initial=host.run(dd,p,np.zeros_like(t6),mode='both',initial=[.005,0,.005,0])
        result['tuning_exploration'].append({'lp_corner_hz':lp_corner,'i_corner_hz':i_corner,
            'tracking':metrics(r,out,dd,t=t),'initial_displacement':metrics(np.zeros_like(t6),initial,dd)})
    # Compare packed LP*(P+I) against the original PI*lead*Butterworth cascade.
    baseline,_,_=candidate(d)
    omega=2*np.pi*ts*np.geomspace(.01,.49/ts,10000)
    sos=baseline['sos']
    def response(rows):
        return signal.sosfreqz(rows,worN=omega)[1]
    linear=response(baseline['linear_sos'])
    reconstructed=response(sos[:2])*(response(sos[2:3])+response(sos[3:]))
    error=float(np.max(abs(reconstructed/linear-1)))
    result['linear_replacement_max_relative_error']=error
    result['linear_nominal_check']=linear_check(d,p)
    result['linear_corner_stability_pass']=all(q['linear_check']['stable'] for q in result['corner_scan'])
    result['worst_linear_corner_sensitivity']=max(q['linear_check']['peak_sensitivity'] for q in result['corner_scan'])
    result['corner_count']=len(result['corner_scan'])
    result['corner_reduction_range_percent']=[min(q['rms_reduction_percent'] for q in result['corner_scan']),max(q['rms_reduction_percent'] for q in result['corner_scan'])]
    result['corner_envelope_pass']=all(q[key]['within_envelope'] for q in result['corner_scan'] for key in ['linear','integrator','lowpass','both'])
    result['sector_violation_count']=sum(q[mode]['sector_violations'] for q in result['cases'] for mode in ['integrator','lowpass','both'])
    np.savez_compressed(args.output/'nominal_traces.npz',t=t,reference=r,**traces)
    save(args.output/'audit_summary.json',result)
    if not (result['corner_envelope_pass'] and result['sector_violation_count']==0 and error<1e-8
            and result['linear_corner_stability_pass'] and result['linear_nominal_check']['stable']
            and result['worst_linear_corner_sensitivity']<=d['sensitivity_limit']):
        raise SystemExit('Saved-design regression failed; inspect audit_summary.json')
    print(json.dumps({k:result[k] for k in ['corner_count','corner_reduction_range_percent','corner_envelope_pass','sector_violation_count','linear_replacement_max_relative_error']},indent=2))
    for q in result['cases']:
        if q['kind']!='corner':print(q['name'],q['rms_reduction_percent'],q['linear']['rms_rad'],q['both']['rms_rad'],q['both']['within_envelope'])

if __name__=='__main__':main()
