function out = load_plant_data(file_path, varargin)
% load_plant_data  exp01 が保存する plant.mat 契約を検証して読み込む。

  p = inputParser;
  p.addParameter("RequiredFields", ["Pd", "Pdn", "Jn", "Dn", "Ndelay", "Ts"], ...
    @(x) isstring(x) || iscellstr(x));
  p.addParameter("expected_sample_time_s", 1 / 8000, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
  p.parse(varargin{:});

  file_path = require_existing_mat_file(file_path, "plant.mat");
  out = load(char(file_path));
  required_fields = string(p.Results.RequiredFields(:));
  missing_fields = required_fields(~isfield(out, required_fields));
  if ~isempty(missing_fields)
    error("experiment:exp0n:invalidPlantData", ...
      "plant.mat is missing required field(s): %s.", strjoin(missing_fields, ", "));
  end

  require_finite_scalar(out.Jn, "Jn", true);
  require_finite_scalar(out.Dn, "Dn", false);
  require_finite_scalar(out.Ts, "Ts", true);
  require_nonnegative_integer(out.Ndelay, "Ndelay");
  if abs(double(out.Ts) - double(p.Results.expected_sample_time_s)) > 1e-12
    error("experiment:exp0n:sampleTimeMismatch", ...
      "plant.mat Ts must be %.12g s (8 kHz); got %.12g s.", ...
      double(p.Results.expected_sample_time_s), double(out.Ts));
  end
  require_dynamic_system(out.Pd, "Pd");
  require_dynamic_system(out.Pdn, "Pdn");
end

function file_path = require_existing_mat_file(value, label)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
  error("experiment:exp0n:invalidPlantData", "%s path must be text.", label);
end
file_path = string(value);
if strlength(file_path) == 0 || ~isfile(char(file_path))
  error("experiment:exp0n:plantRequired", "%s is required: %s", label, file_path);
end
end

function require_finite_scalar(value, name, strictly_positive)
ok = isnumeric(value) && isreal(value) && isscalar(value) && isfinite(double(value));
if strictly_positive
  ok = ok && double(value) > 0;
  description = "positive";
else
  ok = ok && double(value) >= 0;
  description = "nonnegative";
end
if ~ok
  error("experiment:exp0n:invalidPlantData", ...
    "%s must be a finite %s scalar.", name, description);
end
end

function require_nonnegative_integer(value, name)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(double(value)) && ...
    double(value) >= 0 && fix(double(value)) == double(value))
  error("experiment:exp0n:invalidPlantData", ...
    "%s must be a finite nonnegative integer.", name);
end
end

function require_dynamic_system(value, name)
if ~(isa(value, "DynamicSystem") || isa(value, "frd") || isa(value, "lti"))
  error("experiment:exp0n:invalidPlantData", ...
    "%s must be a Control System Toolbox dynamic system.", name);
end
end
