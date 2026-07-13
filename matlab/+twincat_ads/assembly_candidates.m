function candidates = assembly_candidates(ads_assembly, missing_error_id)
% assembly_candidates  Resolve the shared ADS .NET assembly search order.

arguments
  ads_assembly = ""
  missing_error_id (1, 1) string = "twincat_ads:assembly:notFound"
end

explicit = strtrim(string(ads_assembly));
if ~isscalar(explicit)
  error("twincat_ads:assembly:invalidReference", ...
    "ADS assembly reference must be a string scalar or character vector.");
end
known_path = ...
  "C:\Program Files (x86)\Beckhoff\TwinCAT\Functions\TE14xx-ToolsForMatlabAndSimulink\TE140x\NET\TwinCAT.Ads.dll";

if strlength(explicit) > 0 && looks_like_path(explicit) && ~isfile(explicit)
  error(missing_error_id, ...
    "TwinCAT ADS .NET assembly is not found: %s", explicit);
end

candidates = strings(0, 1);
if strlength(explicit) > 0
  candidates(end + 1, 1) = explicit;
end
if isfile(known_path)
  candidates(end + 1, 1) = known_path;
end
candidates(end + 1, 1) = "TwinCAT.Ads";
[~, unique_indices] = unique(candidates, "stable");
candidates = candidates(unique_indices);
end

function tf = looks_like_path(value)
tf = endsWith(lower(value), ".dll") || ...
  contains(value, "\") || contains(value, "/");
end
