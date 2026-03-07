classdef TestRunConfig < matlab.unittest.TestCase
  methods (Test)
    function fillsSystemDefaultsWhenEnvironmentFieldsOmitted(testCase)
      cfg = experiment.RunConfig.from_varargin("ref_profile", [1; 2; 3]);
      sys = experiment.SystemConfig;
      testCase.verifyEqual(string(cfg.ams_net_id), sys.AMS_NET_ID);
      testCase.verifyEqual(cfg.ams_port, double(sys.SEQ_PORT));
      testCase.verifyEqual(cfg.control_ams_port, double(sys.CONTROL_PORT));
      testCase.verifyEqual(cfg.module_ams_port, double(sys.MODULE_PORT));
      testCase.verifyEqual(string(cfg.vm_param_symbol_prefix), sys.VM_PREFIX);
      testCase.verifyEqual(string(cfg.controller_param_symbol_prefix), sys.CTRL_PREFIX);
      testCase.verifyEqual(double(cfg.table_max_n), double(sys.TABLE_MAX_N));
    end

    function fillsEmptyFfAndDistWithZeros(testCase)
      cfg = experiment.RunConfig.from_varargin("ref_profile", [1; 2; 3]);
      testCase.verifyEqual(cfg.ff_profile(:), [0; 0; 0]);
      testCase.verifyEqual(cfg.dist_profile(:), [0; 0; 0]);
      testCase.verifyGreaterThan(double(cfg.task_dt_ns), 0);
      testCase.verifyNotEmpty(cfg.save_path);
    end

    function recomputesTaskDtFromTaskRateOverride(testCase)
      cfg = experiment.RunConfig.from_varargin( ...
        "ref_profile", [1; 2], ...
        "task_rate_hz", 2000);
      testCase.verifyEqual(cfg.task_rate_hz, 2000);
      testCase.verifyEqual(cfg.task_dt_ns, uint64(500000));
    end

    function preservesExplicitEnvironmentOverrides(testCase)
      cfg = experiment.RunConfig.from_varargin( ...
        "ref_profile", [1; 2], ...
        "ams_net_id", "1.2.3.4.5.6", ...
        "ams_port", 900, ...
        "control_ams_port", 901, ...
        "module_ams_port", 902, ...
        "vm_param_symbol_prefix", "Vm.", ...
        "controller_param_symbol_prefix", "Ctrl.");
      testCase.verifyEqual(string(cfg.ams_net_id), "1.2.3.4.5.6");
      testCase.verifyEqual(cfg.ams_port, 900);
      testCase.verifyEqual(cfg.control_ams_port, 901);
      testCase.verifyEqual(cfg.module_ams_port, 902);
      testCase.verifyEqual(string(cfg.vm_param_symbol_prefix), "Vm.");
      testCase.verifyEqual(string(cfg.controller_param_symbol_prefix), "Ctrl.");
    end

    function rejectsMissingRefProfile(testCase)
      testCase.verifyError(@() experiment.RunConfig.from_varargin(), ...
        "experiment:config:invalid");
    end

    function rejectsLengthMismatch(testCase)
      testCase.verifyError(@()experiment.RunConfig.from_varargin( ...
        "ref_profile", [1; 2; 3], ...
        "ff_profile", [1; 2]), "experiment:config:invalid");
    end

    function defaultsControlPortToDataPortWhenNonSequencerPortSelected(testCase)
      cfg = experiment.RunConfig.from_varargin( ...
        "ref_profile", [1; 2], ...
        "ams_port", 851);
      testCase.verifyEqual(cfg.control_ams_port, 851);
    end

    function bridgesToExperimentConfig(testCase)
      legacy = experiment.RunConfig.from_varargin("ref_profile", [1; 2], "ff_profile", [9; 0]);
      cfg = experiment.ExperimentConfig.from_struct(legacy);
      testCase.verifyEqual(cfg.seq_port, legacy.ams_port);
      testCase.verifyEqual(cfg.ff_profile(:), [9; 0]);
      testCase.verifyTrue(cfg.write_plant_params);
      testCase.verifyTrue(cfg.write_controller_params);
    end
  end
end
