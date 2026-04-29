classdef TestSystemConfig < matlab.unittest.TestCase
  methods (Test)
    function constantsHaveExpectedValues(testCase)
      sys = config.SystemConfig;
      testCase.verifyEqual(sys.AMS_NET_ID, "192.168.10.3.1.1");
      testCase.verifyEqual(sys.SEQ_PORT, 853);
      testCase.verifyEqual(sys.CONTROL_PORT, 852);
      testCase.verifyEqual(sys.MODULE_PORT, 351);
      testCase.verifyEqual(sys.TASK_RATE_HZ, 8000);
      testCase.verifyEqual(sys.TABLE_MAX_N, 100000);
      testCase.verifyEqual(sys.LOGGER_RELEASE_TIMEOUT_S, 5.0);
    end

    function taskDtNsReturnsOneEighthMsInNanoseconds(testCase)
      dt = config.SystemConfig.task_dt_ns();
      testCase.verifyEqual(dt, uint64(125000));
    end

    function toStructReturnsAllConstants(testCase)
      s = config.SystemConfig.to_struct();
      testCase.verifyTrue(isstruct(s));
      testCase.verifyTrue(isfield(s, 'AMS_NET_ID'));
      testCase.verifyTrue(isfield(s, 'SEQ_PORT'));
      testCase.verifyTrue(isfield(s, 'CONTROL_PORT'));
      testCase.verifyTrue(isfield(s, 'MODULE_PORT'));
      testCase.verifyTrue(isfield(s, 'TASK_RATE_HZ'));
      testCase.verifyTrue(isfield(s, 'CTRL_PREFIX'));
      testCase.verifyTrue(isfield(s, 'MODE_FLAGS_SYMBOL'));
      testCase.verifyTrue(isfield(s, 'LOGGER_FILE_RELEASED_SYMBOL'));
      testCase.verifyTrue(isfield(s, 'LOGGER_ERROR_CODE_SYMBOL'));
      testCase.verifyTrue(isfield(s, 'TABLE_MAX_N'));
      testCase.verifyEqual(s.SEQ_PORT, 853);
      testCase.verifyFalse(isfield(s, 'DRIVER_PORT'));
    end

    function controllerPrefixIsNonEmpty(testCase)
      sys = config.SystemConfig;
      testCase.verifyGreaterThan(strlength(sys.CTRL_PREFIX), 0);
    end

    function modeFlagsSymbolIsString(testCase)
      sys = config.SystemConfig;
      testCase.verifyClass(sys.MODE_FLAGS_SYMBOL, 'string');
      testCase.verifyTrue(contains(sys.MODE_FLAGS_SYMBOL, "modeFlags"));
    end
  end
end
