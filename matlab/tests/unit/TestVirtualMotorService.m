classdef TestVirtualMotorService < matlab.unittest.TestCase
  methods (Test)
    function constructorRejectsInvalidDependencies(testCase)
      plc = MockAdsTransport();
      testCase.verifyError(@() experiment.VirtualMotorService([], plc, plc), "experiment:service:invalidDependency");
      testCase.verifyError(@() experiment.VirtualMotorService(plc, [], plc), "experiment:service:invalidDependency");
    end

    function constructorAcceptsMockTransports(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      ctrl = MockAdsTransport();
      svc = experiment.VirtualMotorService(plc, vm, ctrl);
      testCase.verifyClass(svc, "experiment.VirtualMotorService");
    end
  end
end
