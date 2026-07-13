function controller_cfg = from_discrete_tf(discrete_tf)
% from_discrete_tf  Convert a real discrete SISO controller to a fixed SOS bank.
[sos, sample_time_s] = experiment.controller.sos_from_discrete_tf(discrete_tf);
controller_cfg = experiment.ControllerConfig.from_struct(struct( ...
  "sos", sos, "sample_time_s", sample_time_s));
end
