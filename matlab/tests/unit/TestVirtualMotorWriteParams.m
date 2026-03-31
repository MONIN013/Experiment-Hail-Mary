classdef TestVirtualMotorWriteParams < matlab.unittest.TestCase
  methods (Test)
    function writesAllPlantParametersWithDefaultTaskDt(testCase)
      module = MockAdsTransport();
      conn = struct("module", module);
      symbols = virtualMotor.Symbols.from_defaults();
      seed_vm_symbols(module, symbols);
      cfg = virtualMotor.PlantConfig.from_struct(struct( ...
        "motor", struct( ...
          "inertia", 1, "damping", 2, "ratedTorque", 3, ...
          "tauLimit", 4, "velLimit", 5, "maxPermille", 6, ...
          "encoderResolution", uint32(7)), ...
        "load", struct( ...
          "inertia", 8, "damping", 9, "ratedTorque", 10, ...
          "tauLimit", 11, "velLimit", 12, ...
          "encoderResolution", uint32(13)), ...
        "coupling", struct("stiffness", 14, "damping", 15)));

      virtualMotor.writeParams(conn, cfg);

      testCase.verifyTrue(any(contains(module.operations, "write_scalar:VirtualMotorCore_Obj1 (Module1).PlantParameter.motor.inertia")));
      testCase.verifyEqual(module.scalarMap(char(symbols.vmParams.motor.inertia)), 1);
      testCase.verifyEqual(module.scalarMap(char(symbols.vmParams.load.velLimit)), 12);
      testCase.verifyEqual(module.scalarMap(char(symbols.vmParams.taskDtNs)), experiment.SystemConfig.task_dt_ns());
    end
  end
end

function seed_vm_symbols(transport, symbols)
probes = symbols.requiredProbes;
for k = 1:size(probes, 1)
  key = char(probes{k, 1});
  transport.scalarMap(key) = default_value_for_type(probes{k, 2});
end
end

function value = default_value_for_type(net_type)
switch char(string(net_type))
  case char(string(twincat_ads.AdsTransport.net_types().u32))
    value = uint32(0);
  case char(string(twincat_ads.AdsTransport.net_types().u64))
    value = uint64(0);
  otherwise
    value = 0.0;
end
end
