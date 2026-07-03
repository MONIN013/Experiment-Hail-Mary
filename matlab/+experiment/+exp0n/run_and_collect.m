function out = run_and_collect(cfg)
% run_and_collect  exp0n 学生実験の接続、実行、logger 回収をまとめる。
%
%   out = experiment.exp0n.run_and_collect(cfg)
%
%   戻り値 out (struct):
%     .run        - ExperimentRunner.run が返した実行結果
%     .logger_bin - out.run.logger.file_path から読み出した logger bin

  arguments
    cfg experiment.ExperimentConfig
  end

  conn = experiment.ConnectionManager.create(cfg);
  cleanup = onCleanup(@() conn.session.close());

  run_out = experiment.ExperimentRunner.run(conn, cfg);
  logger_bin = experiment.read_logger_bin(run_out.logger.file_path);

  out = struct("run", run_out, "logger_bin", logger_bin);
end
