classdef TestVirtualMotorConfigure < matlab.unittest.TestCase
  methods (Test)
    function configuresAndReadsBackAllParametersWhileIdle(testCase)
      [conn, seq, ctrl, module] = seeded_connection();
      plant = virtualMotor.PlantConfig();

      out = virtualMotor.configure(conn, plant, ...
        "taskDtNs", uint64(125000), "timeout_s", 0.02);

      testCase.verifyTrue(out.verified);
      testCase.verifyEqual(out.requested.plant, plant.to_struct());
      testCase.verifyEqual(out.readback.plant, plant.to_struct());
      testCase.verifyEqual(out.readback.taskDtNs, uint64(125000));
      testCase.verifyEqual(seq.scalarMap("GVL_SEQ.tableLen"), uint32(0));
      testCase.verifyEqual(ctrl.scalarMap("GVL_MODE.modeFlags"), uint16(0));
      testCase.verifyTrue(any(contains(module.operations, ...
        "write_scalar:VirtualMotorCore_Obj1 (Module1).PlantParameter.motor.inertia")));
    end

    function rejectsUnsafeCommonRuntimeState(testCase)
      cases = {
        "GVL_MODE.modeFlags", uint16(1);
        "GVL_MODE.modeState", int16(20);
        "GVL_MODE.experimentActive", true;
        "GVL_SEQ.tableLen", uint32(1)
      };
      for k = 1:size(cases, 1)
        [conn, seq, ctrl] = seeded_connection();
        key = cases{k, 1};
        if startsWith(key, "GVL_SEQ")
          seq.scalarMap(key) = cases{k, 2};
        else
          ctrl.scalarMap(key) = cases{k, 2};
        end
        testCase.verifyError(@() virtualMotor.configure( ...
          conn, virtualMotor.PlantConfig(), "timeout_s", 0.02), ...
          "virtualMotor:configure:runtimeNotIdle");
      end
    end

    function rejectsPositionSaturationBeforeWriting(testCase)
      [conn, ~, ~, module] = seeded_connection();
      prefix = "VirtualMotorCore_Obj1 (Module1).Outputs.";
      module.scalarMap(char(prefix + "motor.positionActualValue")) = int32(intmax("int32"));

      testCase.verifyError(@() virtualMotor.configure( ...
        conn, virtualMotor.PlantConfig(), "timeout_s", 0.02), ...
        "virtualMotor:settle:positionSaturated");
      testCase.verifyFalse(any(contains(module.operations, "write_scalar:VirtualMotorCore")));
    end

    function rejectsMissingSymbols(testCase)
      [conn, ~, ~, module] = seeded_connection();
      symbols = virtualMotor.Symbols.from_defaults();
      remove(module.scalarMap, char(symbols.vmParams.coupling.stiffness));

      testCase.verifyError(@() virtualMotor.configure( ...
        conn, virtualMotor.PlantConfig(), "timeout_s", 0.02), ...
        "twincat_ads:symbol:notFound");
    end

    function rejectsReadbackMismatch(testCase)
      [conn, ~, ~, module] = seeded_connection();
      symbols = virtualMotor.Symbols.from_defaults();
      module.set_scalar_read_sequence(symbols.vmParams.motor.inertia, 999);

      testCase.verifyError(@() virtualMotor.configure( ...
        conn, virtualMotor.PlantConfig(), "timeout_s", 0.02, ...
        "validateSymbols", false), ...
        "virtualMotor:configure:readbackMismatch");
    end

    function rejectsIncompleteConnection(testCase)
      testCase.verifyError(@() virtualMotor.configure( ...
        struct(), virtualMotor.PlantConfig()), ...
        "virtualMotor:configure:invalidConnection");
      testCase.verifyError(@() virtualMotor.readParams(struct()), ...
        "virtualMotor:readParams:invalidConnection");
    end
  end
end

function [conn, seq, ctrl, module] = seeded_connection()
seq = MockAdsTransport();
ctrl = MockAdsTransport();
module = MockAdsTransport();
seq.scalarMap("GVL_SEQ.tableLen") = uint32(0);
ctrl.scalarMap("GVL_MODE.modeFlags") = uint16(0);
ctrl.scalarMap("GVL_MODE.modeState") = int16(0);
ctrl.scalarMap("GVL_MODE.experimentActive") = false;

symbols = virtualMotor.Symbols.from_defaults();
types = twincat_ads.AdsTransport.net_types();
for k = 1:size(symbols.requiredProbes, 1)
  key = char(symbols.requiredProbes{k, 1});
  net_type = string(symbols.requiredProbes{k, 2});
  if net_type == string(types.u32)
    module.scalarMap(key) = uint32(1);
  elseif net_type == string(types.u64)
    module.scalarMap(key) = uint64(1);
  else
    module.scalarMap(key) = 1.0;
  end
end
prefix = "VirtualMotorCore_Obj1 (Module1).Outputs.";
module.scalarMap(char(prefix + "motor.positionActualValue")) = int32(0);
module.scalarMap(char(prefix + "motor.velocityActualValue")) = int32(0);
module.scalarMap(char(prefix + "load.positionActualValue")) = int32(0);
module.scalarMap(char(prefix + "load.velocityActualValue")) = int32(0);

env = config.EnvironmentConfig.from_struct(struct("task_rate_hz", 8000));
conn = experiment.ConnectionManager.from_transports(seq, ctrl, module, env);
end
