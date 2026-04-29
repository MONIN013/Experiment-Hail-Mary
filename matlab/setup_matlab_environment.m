matlab_root = fileparts(mfilename("fullpath"));
addpath(matlab_root);

out = config.MatlabEnvironment.install(matlab_root);

fprintf("ExperimentHailMary MATLAB environment configured.\n");
fprintf("cache=%s\n", char(out.cache_file));
fprintf("startup=%s\n", char(out.startup_file));
for idx = 1:numel(out.path_entries)
  fprintf("path[%d]=%s\n", idx, char(out.path_entries(idx)));
end
