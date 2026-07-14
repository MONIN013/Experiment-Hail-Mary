function report = refresh_live_script(file_path, options)
%REFRESH_LIVE_SCRIPT Refresh one rich .m Live Script in this MATLAB process.
% Invoke this tool once per `matlab -batch` process. It first validates a
% temporary same-directory copy without running the experiment, then executes
% the target exactly once and validates the freshly embedded output.
arguments
  file_path {mustBeTextScalar}
  options.backup_root {mustBeTextScalar} = ""
  options.keep_probe (1, 1) logical = false
end

tool_file = mfilename("fullpath");
matlab_root = fileparts(fileparts(tool_file));
addpath(matlab_root, fullfile(matlab_root, "experiment"));

report = experiment.liveeditor.refresh( ...
  file_path, ...
  "backup_root", options.backup_root, ...
  "keep_probe", options.keep_probe);

LiveScript = report.file_path;
Outputs = numel(report.after.output_definition_ids);
Images = numel(report.after.image_output_ids);
TextBlocks = report.after.text_count;
Sections = report.after.section_count;
ProbeSeconds = report.probe_execution_time_s;
TargetSeconds = report.target_execution_time_s;
Backup = report.backup_path;
disp(table(LiveScript, Outputs, Images, TextBlocks, Sections, ...
  ProbeSeconds, TargetSeconds, Backup));
end
