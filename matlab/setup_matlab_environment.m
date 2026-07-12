matlab_root = fileparts(mfilename("fullpath"));
addpath(matlab_root);

% Batch/CI sessions cannot answer input(). Keep the existing machine-local
% config there; desktop users still receive the explicit reconfigure prompt.
out = config.MatlabEnvironment.setup( ...
  matlab_root, "Interactive", usejava("desktop"));

fprintf("ExperimentHailMary MATLAB environment configured.\n");
fprintf("cache=%s\n", char(out.cache_file));
fprintf("startup=%s\n", char(out.startup_file));
for idx = 1:numel(out.path_entries)
  fprintf("path[%d]=%s\n", idx, char(out.path_entries(idx)));
end
fprintf("localConfig=%s (%s)\n", char(out.local_config_file), char(out.local_config_status));
