function capture = archive_trial_logger(logger_bin, destination)
% archive_trial_logger  Preserve one completed ILC trial logger.
capture = experiment.exp0n.archive_logger(logger_bin, destination);
end
