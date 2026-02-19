classdef TestRunConfig < matlab.unittest.TestCase
  methods (Test)
    function requiresAmsNetId(testCase)
      testCase.verifyError(@()ehm.config.RunConfig.fromVarargin( ...
        "vm_param_symbol_prefix", "VirtualMotor."), "ehm:config:invalid");
    end

    function computesDefaults(testCase)
      cfg = ehm.config.RunConfig.fromVarargin( ...
        "ams_net_id", "192.168.10.3.1.1", ...
        "vm_param_symbol_prefix", "VirtualMotor.");
      testCase.verifyEqual(cfg.ams_port, 851);
      testCase.verifyGreaterThan(double(cfg.task_dt_ns), 0);
      testCase.verifyNotEmpty(cfg.save_path);
    end
  end
end
