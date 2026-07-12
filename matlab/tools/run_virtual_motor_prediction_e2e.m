%% VirtualMotor prediction-vs-runtime/logger end-to-end verification
%
% Test-only oracle entrypoint. It intentionally restarts the VM TwinCAT
% runtime to establish a zero hidden state, then compares every logger signal
% against the fixed 8 kHz discrete prediction. Do not use on RealMotor.

tool_file = mfilename("fullpath");
matlab_root = fileparts(fileparts(tool_file));
addpath(matlab_root, fullfile(matlab_root, "experiment"));
clear tool_file matlab_root;

cfg = experiment.ExperimentConfig.defaults();
Ts = 1 / cfg.env.task_rate_hz;
sample_n = round(1.0 / Ts);
ff = zeros(sample_n, 1);
ff(round(0.125 / Ts) + 1:round(0.375 / Ts)) = 0.05;
ff(round(0.375 / Ts) + 1:round(0.625 / Ts)) = -0.05;

cfg.ref_profile = zeros(sample_n, 1);
cfg.ff_profile = ff;
cfg.dist_profile = zeros(sample_n, 1);
cfg.repeat_count = 1;
cfg.wait_for_done = true;
cfg.hold_seconds = sample_n * Ts + 0.5;
cfg.done_timeout_s = sample_n * Ts + 5.0;
cfg.logger_release_timeout_s = 5.0;
cfg.host_heartbeat_enable = false;
cfg.external_host_heartbeat_enable = true;
cfg.controller = experiment.ControllerConfig.p_only(0.0);
cfg.write_virtual_motor_params = true;
cfg.restart_virtual_motor_runtime = false;
cfg.virtual_motor_plant = virtualMotor.PlantConfig();

prediction = virtualMotor.predict_logger(cfg);
if prediction.fault.motor || prediction.fault.load || prediction.position_saturated
  error("virtualMotor:predictionE2e:unsafeStimulus", ...
    "Test stimulus is unsafe in the oracle (motorFault=%d, loadFault=%d, positionSaturated=%d).", ...
    prediction.fault.motor, prediction.fault.load, prediction.position_saturated);
end

restart = virtualMotor.restart_runtime(cfg.env);
collect_out = experiment.exp0n.run_and_collect(cfg);
experiment.exp0n.assert_run_contract(collect_out.run);
metrics = virtualMotor.compare_prediction(collect_out.logger_bin, prediction);
virtualMotor.assert_prediction(metrics, "VirtualMotor prediction E2E");

signal_names = string(fieldnames(metrics.signals));
fprintf("VirtualMotor prediction E2E PASS: samples=%d restart=%.3f s logger=%s\n", ...
  prediction.sample_count, restart.elapsed_s, string(collect_out.logger_bin.file_path));
for k = 1:numel(signal_names)
  item = metrics.signals.(char(signal_names(k)));
  fprintf("  %-18s maxAbs=%g tolerance=%g\n", ...
    signal_names(k), item.max_abs_error, item.tolerance);
end

virtual_motor_prediction_e2e = struct( ...
  "run", collect_out.run, ...
  "logger_bin", collect_out.logger_bin, ...
  "prediction", prediction, ...
  "metrics", metrics, ...
  "restart", restart);
