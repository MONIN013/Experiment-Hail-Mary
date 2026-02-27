classdef TestSystemConfig < matlab.unittest.TestCase
  methods (Test)
    function constantsHaveExpectedValues(testCase)
      sys = experiment.SystemConfig;
      testCase.verifyEqual(sys.AMS_NET_ID, "192.168.10.3.1.1");
      testCase.verifyEqual(sys.SEQ_PORT, 853);
      testCase.verifyEqual(sys.CONTROL_PORT, 852);
      testCase.verifyEqual(sys.DRIVER_PORT, 851);
      testCase.verifyEqual(sys.MODULE_PORT, 351);
      testCase.verifyEqual(sys.TASK_RATE_HZ, 1000);
      testCase.verifyEqual(sys.LOG_N, 200000);
      testCase.verifyEqual(sys.TABLE_MAX_N, 100000);
    end

    function taskDtNsReturnsOneMsInNanoseconds(testCase)
      dt = experiment.SystemConfig.task_dt_ns();
      testCase.verifyEqual(dt, uint64(1000000));
    end

    function toStructReturnsAllConstants(testCase)
      s = experiment.SystemConfig.to_struct();
      testCase.verifyTrue(isstruct(s));
      testCase.verifyTrue(isfield(s, 'AMS_NET_ID'));
      testCase.verifyTrue(isfield(s, 'SEQ_PORT'));
      testCase.verifyTrue(isfield(s, 'CONTROL_PORT'));
      testCase.verifyTrue(isfield(s, 'DRIVER_PORT'));
      testCase.verifyTrue(isfield(s, 'MODULE_PORT'));
      testCase.verifyTrue(isfield(s, 'TASK_RATE_HZ'));
      testCase.verifyTrue(isfield(s, 'VM_PREFIX'));
      testCase.verifyTrue(isfield(s, 'CTRL_PREFIX'));
      testCase.verifyTrue(isfield(s, 'MODE_FLAGS_SYMBOL'));
      testCase.verifyTrue(isfield(s, 'LOG_N'));
      testCase.verifyTrue(isfield(s, 'TABLE_MAX_N'));
      testCase.verifyEqual(s.SEQ_PORT, 853);
    end

    function prefixesAreNonEmpty(testCase)
      sys = experiment.SystemConfig;
      testCase.verifyGreaterThan(strlength(sys.VM_PREFIX), 0);
      testCase.verifyGreaterThan(strlength(sys.CTRL_PREFIX), 0);
    end

    function modeFlagsSymbolIsString(testCase)
      sys = experiment.SystemConfig;
      testCase.verifyClass(sys.MODE_FLAGS_SYMBOL, 'string');
      testCase.verifyTrue(contains(sys.MODE_FLAGS_SYMBOL, "modeFlags"));
    end
  end
end
