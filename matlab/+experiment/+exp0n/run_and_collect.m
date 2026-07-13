function out = run_and_collect(cfg)
% run_and_collect  exp0n 学生実験の接続、実行、logger 回収をまとめる。
%
%   out = experiment.exp0n.run_and_collect(cfg)
%
%   戻り値 out (struct):
%     .run        - ExperimentRunner.run が返した実行結果
%     .logger_bin - Runner が一度だけ読み出した logger bin

  arguments
    cfg experiment.ExperimentConfig
  end

  startup_t0 = tic;
  connect_t0 = tic;
  conn = experiment.ConnectionManager.create(cfg);
  connect_s = toc(connect_t0);
  cleanup = onCleanup(@() conn.session.close());

  pre_runner_s = toc(startup_t0);
  run_out = experiment.ExperimentRunner.run(conn, cfg);
  out = struct( ...
    "run", run_out, ...
    "logger_bin", run_out.logger_bin, ...
    "startup_timing", struct( ...
      "connect_s", connect_s, ...
      "runner", run_out.host.startup_timing, ...
      "total_to_start_s", pre_runner_s + run_out.host.startup_timing.total_s));
end
