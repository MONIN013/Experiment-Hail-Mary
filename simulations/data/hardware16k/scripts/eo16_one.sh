#!/bin/bash
# args: case k mode
S="c:/Users/Nogiku/source/repos/ExperimentHailMary/ExperimentHailMary/simulations/data/hardware16k/scripts"
for t in 1 2 3; do
 "/c/Program Files/MATLAB/R2025a/bin/matlab.exe" -batch "SP='$S'; FC=0.10; JFF=1e-4; MODE='$3'; DESIGN=fullfile(SP,'eo16','$1_$3.json'); NAME=string('eo_$1_$2_$3'); run(fullfile(SP,'hw_trial.m'))" 2>&1 | grep -E "RESULT" | sed -e 's/, logged.*//' -e 's/RESULT eo_//' | cut -c1-200
 [ -f "$S/hw/eo_$1_$2_$3.mat" ] && break; echo "retry $1 $2 $3"
done
