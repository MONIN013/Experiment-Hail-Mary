classdef TestExperimentConfig < matlab.unittest.TestCase
  methods (Test)
    function defaultsUseSystemConfig(testCase)
      cfg = experiment.ExperimentConfig.defaults();
      sys = experiment.SystemConfig;
      testCase.verifyEqual(string(cfg.ams_net_id), sys.AMS_NET_ID);
      testCase.verifyEqual(cfg.seq_port, double(sys.SEQ_PORT));
      testCase.verifyEqual(cfg.control_port, double(sys.CONTROL_PORT));
      testCase.verifyEqual(cfg.module_port, double(sys.MODULE_PORT));
      testCase.verifyEqual(cfg.logger_release_timeout_s, double(sys.LOGGER_RELEASE_TIMEOUT_S));
    end

    function rejectsLegacyAliasesAndRemovedBridgeFiles(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_struct(struct( ...
        "ams_port", 851, ...
        "ref_profile", [1; 2])), "experiment:config:invalid");
      testCase.verifyEqual(which("experiment.RunConfig"), '');
      testCase.verifyEqual(which("experiment.PositionCommandConfig"), '');
    end

    function rejectsPrefixOverride(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [1; 2], ...
        "vm_param_symbol_prefix", "Vm."), "experiment:config:invalid");
    end

    function rejectsWaveformLongerThanReference(testCase)
      testCase.verifyError(@() experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [1; 2], ...
        "dist_profile", [0; 0; 0]), "experiment:config:invalid");
    end
  end
end
