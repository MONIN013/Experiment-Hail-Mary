classdef TestRunConfig < matlab.unittest.TestCase
  methods (Test)
    function requiresAmsNetId(testCase)
      testCase.verifyError(@()experiment.RunConfig.from_varargin( ...
        "vm_param_symbol_prefix", "VirtualMotor."), "experiment:config:invalid");
    end

    function computesDefaults(testCase)
      cfg = experiment.RunConfig.from_varargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.");
      testCase.verifyEqual(cfg.ams_port, 851);
      testCase.verifyGreaterThan(double(cfg.task_dt_ns), 0);
      testCase.verifyNotEmpty(cfg.save_path);
    end
  end
end
