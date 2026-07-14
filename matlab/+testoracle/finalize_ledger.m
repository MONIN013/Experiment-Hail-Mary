function ledger = finalize_ledger(ledger, final_state)
% finalize_ledger  Reject pending/skipped/failed entries and dirty VM state.
statuses = string({ledger.records.status});
if any(statuses ~= "completed")
  error("testoracle:ledger:incomplete", ...
    "Pending entries remain: %s.", ...
    strjoin(string({ledger.records(statuses ~= "completed").name}), ", "));
end
if any(~[ledger.records.pass])
  error("testoracle:ledger:failed", ...
    "Four-layer gate failed for: %s.", ...
    strjoin(string({ledger.records(~[ledger.records.pass]).name}), ", "));
end
state_report = testoracle.verify_final_state(final_state);
if ~state_report.pass
  error("testoracle:ledger:dirtyFinalState", ...
    "Final ADS/VirtualMotor state is not clean.");
end
ledger.final_state = struct("readback", final_state, "report", state_report);
ledger.complete = true;
ledger.completed_at_utc = string(datetime("now", "TimeZone", "UTC", ...
  "Format", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"));
payload = ledger;
if isfield(payload, "canonical_digest")
  payload = rmfield(payload, "canonical_digest");
end
ledger.canonical_digest = testoracle.canonical_digest(payload);
end
