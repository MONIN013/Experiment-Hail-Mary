%% VirtualMotor prediction-vs-runtime/logger end-to-end verification
%
% Test-only oracle entrypoint. It intentionally restarts the VM TwinCAT
% runtime to establish a zero hidden state, then compares every logger signal
% against the fixed 8 kHz discrete prediction. Do not use on RealMotor.

run_virtual_motor_prediction_e2e_result = run_virtual_motor_prediction_e2e_main();

function virtual_motor_prediction_e2e = run_virtual_motor_prediction_e2e_main()

tool_file = mfilename("fullpath");
matlab_root = fileparts(fileparts(tool_file));
addpath(matlab_root, fullfile(matlab_root, "experiment"));
clear tool_file matlab_root;

cfg = experiment.ExperimentConfig.defaults();
Ts = 1 / cfg.env.task_rate_hz;
sample_n = round(1.0 / Ts);
ff = zeros(sample_n, 1);
% Thirty exact 1.6 mA driver quanta keep the independent lsim stimulus
% identical to the command applied by the quantized strict VM oracle.
ff(round(0.125 / Ts) + 1:round(0.375 / Ts)) = 0.048;
ff(round(0.375 / Ts) + 1:round(0.625 / Ts)) = -0.048;

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
plant = virtualMotor.PlantConfig();

restart = virtualMotor.restart_runtime(cfg.env);
configure_conn = experiment.ConnectionManager.create(cfg);
configure_cleanup = onCleanup(@() configure_conn.session.close());
configuration = virtualMotor.configure(configure_conn, plant, ...
  "taskDtNs", cfg.env.task_dt_ns(), ...
  "timeout_s", cfg.reset_timeout_s, ...
  "validateSymbols", true);
clear configure_cleanup

prediction = virtualMotor.predict_logger(cfg, plant);
if prediction.fault.motor || prediction.fault.load || prediction.position_saturated
  error("virtualMotor:predictionE2e:unsafeStimulus", ...
    "Test stimulus is unsafe in the oracle (motorFault=%d, loadFault=%d, positionSaturated=%d).", ...
    prediction.fault.motor, prediction.fault.load, prediction.position_saturated);
end

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
  "restart", restart, ...
  "configuration", configuration);
end
