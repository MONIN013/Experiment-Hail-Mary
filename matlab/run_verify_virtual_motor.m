%% VirtualMotor verify script
%
%  VirtualMotorCore の parameter symbols が active contract と一致するかを確認する。

cfg = experiment.ExperimentConfig.defaults();
conn = experiment.ConnectionManager.create(cfg);
cleanup = onCleanup(@() conn.session.close()); 

symbols = virtualMotor.Symbols.from_defaults();
twincat_ads.SymbolBrowser.validate_symbols(conn.module, symbols.requiredProbes);

fprintf("VirtualMotor symbols verified: %d probes on module port %d\n", ...
  size(symbols.requiredProbes, 1), cfg.module_port);
