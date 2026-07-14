function ledger = record_entry(ledger, name, layer_reports, varargin)
% record_entry  Record one executed (never skipped) entry and four gates.
p = inputParser;
p.addParameter("detail", "", @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.addParameter("started_at_utc", "", @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.parse(varargin{:});
required_layers = ["exact", "independent", "outcome", "artifact"];
if ~isstruct(layer_reports) || ~isscalar(layer_reports) || ...
    any(~isfield(layer_reports, required_layers))
  error("testoracle:ledger:invalidLayers", ...
    "exact/independent/outcome/artifact reports are required.");
end
passes = false(size(required_layers));
for index = 1:numel(required_layers)
  report = layer_reports.(char(required_layers(index)));
  if ~isstruct(report) || ~isscalar(report) || ~isfield(report, "pass") || ...
      ~(islogical(report.pass) && isscalar(report.pass))
    error("testoracle:ledger:invalidLayers", ...
      "Layer %s must contain a scalar logical pass.", required_layers(index));
  end
  passes(index) = report.pass;
end
names = string({ledger.records.name});
match = find(names == string(name));
if numel(match) ~= 1
  error("testoracle:ledger:unknownEntry", "Unknown ledger entry %s.", name);
end
if string(ledger.records(match).status) ~= "pending"
  error("testoracle:ledger:duplicateEntry", "%s was already recorded.", name);
end
started_at = string(p.Results.started_at_utc);
if strlength(started_at) == 0, started_at = utc_now(); end
ledger.records(match).status = "completed";
ledger.records(match).pass = all(passes);
ledger.records(match).started_at_utc = started_at;
ledger.records(match).finished_at_utc = utc_now();
ledger.records(match).layers = layer_reports;
ledger.records(match).result_digest = testoracle.canonical_digest(layer_reports);
ledger.records(match).detail = string(p.Results.detail);
end

function value = utc_now()
value = string(datetime("now", "TimeZone", "UTC", ...
  "Format", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"));
end
