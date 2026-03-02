classdef TestPositionCommandConfig < matlab.unittest.TestCase
  methods (Test)
    function inheritsSystemDefaults(testCase)
      cfg = experiment.PositionCommandConfig.from_varargin("ref_profile", [1; 2]);
      sys = experiment.SystemConfig;
      testCase.verifyEqual(string(cfg.ams_net_id), sys.AMS_NET_ID);
      testCase.verifyEqual(cfg.ams_port, double(sys.SEQ_PORT));
      testCase.verifyEqual(cfg.control_ams_port, double(sys.CONTROL_PORT));
      testCase.verifyEqual(cfg.task_rate_hz, double(sys.TASK_RATE_HZ));
      testCase.verifyEqual(cfg.log_n, double(sys.LOG_N));
      testCase.verifyEqual(cfg.table_max_n, double(sys.TABLE_MAX_N));
      testCase.verifyEqual(string(cfg.mode_flags_symbol), sys.MODE_FLAGS_SYMBOL);
    end

    function zeroFillsFfAndDistAndDerivesHoldSeconds(testCase)
      cfg = experiment.PositionCommandConfig.from_varargin( ...
        "ref_profile", [1; 2; 3], ...
        "task_rate_hz", 2000);
      testCase.verifyEqual(cfg.ff_profile(:), [0; 0; 0]);
      testCase.verifyEqual(cfg.dist_profile(:), [0; 0; 0]);
      testCase.verifyEqual(cfg.hold_seconds, 3 / 2000, "AbsTol", 1e-12);
    end

    function defaultsControlPortToDataPortForNonSequencerPort(testCase)
      cfg = experiment.PositionCommandConfig.from_varargin( ...
        "ams_port", 851, ...
        "ref_profile", [1; 2]);
      testCase.verifyEqual(cfg.control_ams_port, 851);
    end

    function rejectsModeFlagsTransportWithoutSymbol(testCase)
      cfg_struct = experiment.SystemConfig.position_command_defaults();
      cfg_struct.ref_profile = [1; 2];
      cfg_struct.mode_flags_symbol = "";
      cfg_struct.mode_flags_transport = MockAdsTransport();
      testCase.verifyError(@() experiment.PositionCommandConfig.from_struct(cfg_struct), ...
        "experiment:position_command:invalidConfig");
    end
  end
end
