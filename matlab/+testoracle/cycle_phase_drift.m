function value = cycle_phase_drift(position, cycle_samples, transient_cycles)
%CYCLE_PHASE_DRIFT Maximum steady same-phase cycle-end displacement.
arguments
  position (:, 1) double
  cycle_samples (1, 1) double {mustBePositive, mustBeInteger}
  transient_cycles (1, 1) double {mustBeNonnegative, mustBeInteger}
end
if any(~isfinite(position)) || mod(numel(position), cycle_samples) ~= 0
  error("testoracle:si:invalidCycleHistory", ...
    "Position must be finite and contain an integer number of cycles.");
end
cycle_count = numel(position)/cycle_samples;
first_cycle = transient_cycles+1;
if cycle_count-first_cycle+1 < 2
  error("testoracle:si:insufficientSteadyCycles", ...
    "At least two complete cycles are required after transient removal.");
end
end_indices = (first_cycle:cycle_count)*cycle_samples;
endpoints = position(end_indices);
value = max(abs(diff(endpoints)));
end
