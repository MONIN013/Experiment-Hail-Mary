function plan = predict_ilc_campaign(scenario, plant_cfg)
% predict_ilc_campaign  Test-only exact simulation of all ILC trials.
%
% Experiment-purpose and endpoint gates are applied once by the frozen
% manifest's evaluate_outcome pass. Keeping this wrapper gate-free prevents
% duplicated literals and comparison-boundary drift.
plan = testoracle.simulate_ilc_campaign(scenario, plant_cfg);
end
