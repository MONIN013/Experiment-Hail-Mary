# Identification from the legacy chirp record

- Source SHA-256: `d882ff79015b8759f70110aaee2aebf039f4aa261c25994ee895e46800d8b4e4`
- Input: current command [A]; angles: recorded degrees converted to radians.
- Acquisition: 16000 Hz, 10 periods of 10 s; periods 3–10 retained.
- Source unit declaration: https://github.com/MONIN013/Experiment-Hail-Mary/blob/6bb96d39135b98355a68ebc68de5167a1733b87d/matlab/experiment/proto/chirp_openloop.m
- Source sampling metadata is preserved. These files do not replace fresh identification at the current controller rate.

## Effective four-state model

The normalization is Kt=1. The fitted values are divided by the unknown effective torque constant; they are not independent measurements of physical inertia or damping.

| Quantity | Value |
|---|---:|
| jm | 5.54651341e-05 |
| jl | 4.66910617e-05 |
| ks | 98.7849388 |
| cs | 0.00148139708 |
| bm | 5.54651341e-10 |
| bl | 0.0103974376 |
| effective_delay_s_including_source_zoh | 0.000240040189 |
| resonance_damped_Hz | 313.353372 |
| resonance_zeta | 0.0454158032 |

The nominal fit uses 5–700 Hz. Band variants are included in the JSON. Bm reaches the nonnegative optimization boundary. The motor/load ratio independently places the antiresonance near 231.139 Hz.

## Fit quality

| Band | Motor complex RMS error | Load complex RMS error |
|---|---:|---:|
| 5-20Hz | 31.1% | 30.5% |
| 20-50Hz | 18.0% | 16.8% |
| 50-150Hz | 24.1% | 17.9% |
| 150-250Hz | 34.7% | 16.1% |
| 250-400Hz | 19.4% | 15.8% |
| 400-700Hz | 17.7% | 17.9% |
| 5-700Hz | 22.5% | 17.6% |

Training on periods 3–6 and checking periods 7–10 gives 23.9% motor / 19.5% load complex RMS error. This checks repetition consistency, not a new input amplitude.

## Limits for controller design

The nominal load model is about 17 degrees too optimistic in phase at 10 Hz. Check the controller against the measured response and every retained period, then obtain a fresh record with the present hardware configuration.

The fitted common delay includes source zero-order hold, acquisition alignment and unmodeled current-loop dynamics. Subtracting half of the original sample period assumes a known simultaneous command/output timestamp, which this old MAT does not contain.

The chirp has a nonzero mean, and its rotation offset varies considerably between periods. High coherence does not exclude repeatable nonlinear friction. The fit should not be extrapolated to arbitrary small-signal stiction or treated as a proof of HIGS stability.

## Reproduce

```bash
python simulations/identify_chirp.py --input /path/to/chirp_result.mat
```

The raw MAT is external and is not committed. measured_frf.npz covers 1–4000 Hz, retaining 0.1 Hz spacing at 1–100 Hz, 0.2 Hz at 180–360 Hz and 1 Hz elsewhere; each period array has shape (8, frequency_count).
