function out = load_trajectory(varargin)
% load_trajectory  標準 8 kHz trajectory を検証し rad 単位で返す。

  file_path = default_trajectory_path();
  if ~isempty(varargin) && is_trajectory_path_argument(varargin{1})
    file_path = string(varargin{1});
    varargin = varargin(2:end);
  end
  p = inputParser;
  p.addParameter("expected_sample_time_s", 1 / 8000, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
  p.addParameter("table_max_n", 100000, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && fix(x) == x);
  p.parse(varargin{:});

  if ~(ischar(file_path) || (isstring(file_path) && isscalar(file_path)))
    error("experiment:exp0n:invalidTrajectoryData", "trajectory path must be text.");
  end
  file_path = string(file_path);
  if strlength(file_path) == 0 || ~isfile(char(file_path))
    error("experiment:exp0n:trajectoryRequired", ...
      "The tracked 8 kHz trajectory is required: %s", file_path);
  end

  loaded = load(char(file_path), "ref1_struct");
  required_fields = ["t", "p", "v", "a"];
  if ~isfield(loaded, "ref1_struct") || ~isscalar(loaded.ref1_struct)
    error("experiment:exp0n:invalidTrajectoryData", ...
      "trajectory must contain one scalar ref1_struct.");
  end
  ref = loaded.ref1_struct;
  missing_fields = required_fields(~isfield(ref, required_fields));
  if ~isempty(missing_fields)
    error("experiment:exp0n:invalidTrajectoryData", ...
      "ref1_struct is missing required field(s): %s.", strjoin(missing_fields, ", "));
  end

  values = cell(size(required_fields));
  for k = 1:numel(required_fields)
    name = char(required_fields(k));
    value = ref.(name);
    if ~(isnumeric(value) && isreal(value) && isvector(value) && all(isfinite(double(value(:)))))
      error("experiment:exp0n:invalidTrajectoryData", ...
        "ref1_struct.%s must be a finite real vector.", name);
    end
    values{k} = double(value(:));
  end
  counts = cellfun(@numel, values);
  if any(counts ~= counts(1)) || counts(1) < 3 || counts(1) > p.Results.table_max_n
    error("experiment:exp0n:invalidTrajectoryData", ...
      "trajectory t/p/v/a lengths must match and be within 3..%d.", p.Results.table_max_n);
  end

  t = values{1};
  dt = diff(t);
  Ts = double(p.Results.expected_sample_time_s);
  if any(dt <= 0) || max(abs(dt - Ts)) > 1e-12
    error("experiment:exp0n:invalidTrajectoryData", ...
      "trajectory time spacing must be %.12g s (8 kHz).", Ts);
  end

  p_rad = deg2rad(values{2});
  v_rad_s = deg2rad(values{3});
  a_rad_s2 = deg2rad(values{4});
  out = struct( ...
    "t", t, ...
    "p", p_rad, ...
    "v", v_rad_s, ...
    "a", a_rad_s2, ...
    "position", p_rad, ...
    "velocity", v_rad_s, ...
    "acceleration", a_rad_s2, ...
    "sample_count", double(counts(1)), ...
    "Ts", Ts, ...
    "file_path", file_path, ...
    "source_units", "deg", ...
    "units", "rad");
end

function tf = is_trajectory_path_argument(value)
tf = (ischar(value) || (isstring(value) && isscalar(value))) && ...
  ~any(lower(string(value)) == ["expected_sample_time_s", "table_max_n"]);
end

function path_value = default_trajectory_path()
package_dir = fileparts(mfilename("fullpath"));
matlab_root = fileparts(fileparts(package_dir));
path_value = string(fullfile(matlab_root, "resources", "trajectory_8khz.mat"));
end
