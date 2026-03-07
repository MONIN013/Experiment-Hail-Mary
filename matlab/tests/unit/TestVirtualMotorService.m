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

    function runDelegatesToExperimentRunner(testCase)
      plc = MockAdsTransport();
      vm = MockAdsTransport();
      ctrl = MockAdsTransport();
      seed_state(plc);
      seed_state(ctrl);
      svc = experiment.VirtualMotorService(plc, vm, ctrl);
      out = svc.run(experiment.ExperimentConfig.from_varargin( ...
        "ref_profile", [0.1; 0.2], ...
        "wait_for_done", false, ...
        "hold_seconds", 0.0, ...
        "validate_symbols", false));
      testCase.verifyTrue(isfield(out.raw, "ref_value"));
      testCase.verifyTrue(any(contains(plc.operations, "write_array:GVL_SEQ.refTable")));
      testCase.verifyTrue(any(contains(vm.operations, "write_scalar:VirtualMotorCore_Obj1 (Module1).VirtualMotor1Parameter.mass")));
    end
  end
end

function seed_state(t)
t.scalarMap("GVL_MODE.modeFlags") = uint16(0);
t.scalarMap("GVL_MODE.resetReq") = false;
t.scalarMap("GVL_MODE.resetAckCounter") = uint32(0);
t.scalarMap("GVL_MODE.hostHeartbeatCounter") = uint32(0);
t.scalarMap("GVL_MODE.experimentActive") = false;
t.scalarMap("GVL_MODE.experimentState") = uint32(3);
t.scalarMap("GVL_MODE.loggerFileReleased") = true;
t.scalarMap("GVL_MODE.loggerErrorCode") = uint32(0);
t.scalarMap("GVL_SEQ.idx") = uint32(0);
end
