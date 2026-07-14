%% VirtualMotor verify script
%
%  VirtualMotorCore の parameter symbols が active contract と一致するかを確認する。

run_verify_virtual_motor_result = run_verify_virtual_motor_main();

function virtual_motor_verification = run_verify_virtual_motor_main()

tool_file = mfilename("fullpath");
matlab_root = fileparts(fileparts(tool_file));
addpath(matlab_root, fullfile(matlab_root, "experiment"));
clear tool_file matlab_root;

cfg = experiment.ExperimentConfig.defaults();
conn = experiment.ConnectionManager.create(cfg);
cleanup = onCleanup(@() conn.session.close()); 

symbols = virtualMotor.Symbols.from_defaults();
twincat_ads.SymbolBrowser.validate_symbols(conn.module, symbols.requiredProbes);

fprintf("VirtualMotor symbols verified: %d probes on module port %d\n", ...
  size(symbols.requiredProbes, 1), cfg.env.module_port);
virtual_motor_verification = struct( ...
  "probe_count", size(symbols.requiredProbes, 1), ...
  "module_port", double(cfg.env.module_port), "passed", true);
end
