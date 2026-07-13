%% Configure VirtualMotor plant parameters while the common runtime is idle

run_configure_virtual_motor_result = run_configure_virtual_motor_main();

function virtual_motor_configuration = run_configure_virtual_motor_main()

tool_file = mfilename("fullpath");
matlab_root = fileparts(fileparts(tool_file));
addpath(matlab_root, fullfile(matlab_root, "experiment"));
clear tool_file matlab_root;

plant = virtualMotor.PlantConfig();
timeout_s = 5.0;

cfg = experiment.ExperimentConfig.defaults();
conn = experiment.ConnectionManager.create(cfg);
cleanup = onCleanup(@() conn.session.close());

virtual_motor_configuration = virtualMotor.configure(conn, plant, ...
  "taskDtNs", cfg.env.task_dt_ns(), ...
  "timeout_s", timeout_s, ...
  "validateSymbols", true);

mode = virtualMotor.torsional_mode(plant);
fprintf("VirtualMotor parameters configured and verified.\n");
fprintf("  taskDtNs=%u fn=%.6f Hz zeta=%.6f\n", ...
  virtual_motor_configuration.readback.taskDtNs, ...
  mode.natural_frequency_hz, mode.damping_ratio);
end
