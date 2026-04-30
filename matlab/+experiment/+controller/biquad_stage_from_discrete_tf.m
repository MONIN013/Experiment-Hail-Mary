function stage = biquad_stage_from_discrete_tf(discrete_tf)
% biquad_stage_from_discrete_tf  Convert up to second-order discrete TF to BiquadStage.
[num, den] = tfdata(discrete_tf, "v");
num = experiment.controller.normalize_polynomial(num);
den = experiment.controller.normalize_polynomial(den);
if numel(num) > 3 || numel(den) > 3
  error("experiment:controller:unsupportedControllerOrder", ...
    "ControllerCore PID stage supports up to second-order discrete transfer functions.");
end
if isempty(den) || den(1) == 0
  error("experiment:controller:invalidController", ...
    "Discrete controller denominator must have a nonzero leading coefficient.");
end

num = num ./ den(1);
den = den ./ den(1);
num(end+1:3) = 0;
den(end+1:3) = 0;

stage = experiment.BiquadStage.from_struct(struct( ...
  "b0", num(1), ...
  "b1", num(2), ...
  "b2", num(3), ...
  "a1", den(2), ...
  "a2", den(3), ...
  "enable", true));
end
