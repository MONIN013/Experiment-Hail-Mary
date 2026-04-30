function controller_cfg = from_discrete_tf(discrete_tf)
% from_discrete_tf  Convert a discrete transfer function into ControllerConfig.
pid_stage = experiment.controller.biquad_stage_from_discrete_tf(discrete_tf);
controller_cfg = experiment.ControllerConfig();
controller_cfg.pid = pid_stage;
controller_cfg.lead = experiment.BiquadStage.passthrough();
controller_cfg.notch = experiment.BiquadStage.passthrough();
controller_cfg.reso = experiment.BiquadStage.passthrough();
end
