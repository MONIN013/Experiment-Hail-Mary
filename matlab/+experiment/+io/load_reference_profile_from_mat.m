function ref_profile = load_reference_profile_from_mat(file_path, variable_name)
% load_reference_profile_from_mat  Load a numeric reference vector in rad.
file_path = string(file_path);
variable_name = char(string(variable_name));
if ~isfile(file_path)
  error("experiment:io:trajectoryMissing", ...
    "Trajectory mat file not found: %s", file_path);
end
data = load(file_path, variable_name);
if ~isfield(data, variable_name)
  error("experiment:io:trajectoryVariableMissing", ...
    "Trajectory variable '%s' is missing in %s.", variable_name, file_path);
end
ref_profile = data.(variable_name);
if ~isnumeric(ref_profile) || ~isvector(ref_profile) || isempty(ref_profile)
  error("experiment:io:invalidTrajectory", ...
    "Trajectory variable '%s' must be a nonempty numeric vector in rad.", variable_name);
end
ref_profile = double(ref_profile(:));
end
