function elapsed_s = structure_probe(file_path)
% structure_probe  Validate a temporary rich .m copy without executing it.
%
% Executing the probe would run the physical workflow twice and would break
% the frozen prediction's one-restart/one-campaign contract. The target is the
% only file passed to executeAndSave.
timer = tic;
report = experiment.liveeditor.assert_refreshable(file_path);
if ~report.is_live_code
  error("experiment:liveeditor:ProbeNotLiveCode", ...
    "Temporary probe is not recognized as rich Live Code: %s", file_path);
end
elapsed_s = toc(timer);
end
