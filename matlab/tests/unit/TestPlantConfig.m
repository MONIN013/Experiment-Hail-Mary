classdef TestPlantConfig < matlab.unittest.TestCase
  methods (Test)
    function defaultsMatchPanasonicMhmf011l1a2Preset(testCase)
      cfg = virtualMotor.PlantConfig();
      out = cfg.to_struct();

      testCase.verifyEqual(out.motor.inertia, 7.1e-6, "AbsTol", 1e-12);
      testCase.verifyEqual(out.motor.damping, 7.1e-5, "AbsTol", 1e-12);
      testCase.verifyEqual(out.motor.ratedTorque, 0.32, "AbsTol", 1e-12);
      testCase.verifyEqual(out.motor.tauLimit, 1.11, "AbsTol", 1e-12);
      testCase.verifyEqual(out.motor.velLimit, 2*pi*6500/60, "AbsTol", 1e-12);
      testCase.verifyEqual(out.motor.maxPermille, 1000.0, "AbsTol", 1e-12);
      testCase.verifyEqual(out.motor.encoderResolution, uint32(8388608));

      testCase.verifyEqual(out.load.inertia, 7.1e-6, "AbsTol", 1e-12);
      testCase.verifyEqual(out.load.damping, 3.55e-5, "AbsTol", 1e-12);
      testCase.verifyEqual(out.load.ratedTorque, 0.32, "AbsTol", 1e-12);
      testCase.verifyEqual(out.load.tauLimit, 1.11, "AbsTol", 1e-12);
      testCase.verifyEqual(out.load.velLimit, 2*pi*6500/60, "AbsTol", 1e-12);
      testCase.verifyEqual(out.load.encoderResolution, uint32(8388608));

      testCase.verifyEqual(out.coupling.stiffness, 5.6059352998187553, "RelTol", 1e-14);
      testCase.verifyEqual(out.coupling.damping, 0.0004194811568097506, "RelTol", 1e-14);

      mode = virtualMotor.torsional_mode(cfg);
      testCase.verifyEqual(mode.natural_frequency_hz, 200, "AbsTol", 1e-3);
      testCase.verifyEqual(mode.damping_ratio, 0.05, "AbsTol", 1e-6);
      testCase.verifyEqual(mode.damped_frequency_hz, 199.749, "AbsTol", 1e-3);
    end

    function structRoundTripUsesNestedPlant(testCase)
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
      out = cfg.to_struct();
      testCase.verifyEqual(out.motor.inertia, 1);
      testCase.verifyEqual(out.load.velLimit, 12);
      testCase.verifyEqual(out.coupling.stiffness, 14);
      testCase.verifyFalse(isfield(out.load, "maxPermille"));
    end

    function rejectsUnknownTopLevelFields(testCase)
      testCase.verifyError(@() virtualMotor.PlantConfig.from_struct(struct( ...
        "motor", struct(), "load", struct(), "coupling", struct(), ...
        "typo", 1)), "virtualMotor:plant:invalid");
    end

    function rejectsLoadMaxPermille(testCase)
      bad = struct( ...
        "motor", struct( ...
          "inertia", 1, "damping", 2, "ratedTorque", 3, ...
          "tauLimit", 4, "velLimit", 5, "maxPermille", 6, ...
          "encoderResolution", uint32(7)), ...
        "load", struct( ...
          "inertia", 8, "damping", 9, "ratedTorque", 10, ...
          "tauLimit", 11, "velLimit", 12, "maxPermille", 13, ...
          "encoderResolution", uint32(14)), ...
        "coupling", struct("stiffness", 15, "damping", 16));
      testCase.verifyError(@() virtualMotor.PlantConfig.from_struct(bad), ...
        "virtualMotor:plant:invalid");
    end

    function rejectsUnknownNestedField(testCase)
      bad = valid_plant_struct();
      bad.motor.typo = 1;
      testCase.verifyError(@() virtualMotor.PlantConfig.from_struct(bad), ...
        "virtualMotor:plant:invalid");
    end

    function rejectsNonFiniteAndNonPhysicalValues(testCase)
      cases = {
        "motor", "inertia", 0;
        "motor", "damping", -1;
        "motor", "tauLimit", -1;
        "motor", "velLimit", Inf;
        "motor", "maxPermille", -1;
        "load", "inertia", NaN;
        "load", "ratedTorque", 0;
        "load", "encoderResolution", 1.5;
        "coupling", "stiffness", -1;
        "coupling", "damping", Inf
      };
      for k = 1:size(cases, 1)
        bad = valid_plant_struct();
        group = cases{k, 1};
        field = cases{k, 2};
        bad.(group).(field) = cases{k, 3};
        testCase.verifyError(@() virtualMotor.PlantConfig.from_struct(bad), ...
          "virtualMotor:plant:invalid");
      end
    end
  end
end

function plant = valid_plant_struct()
plant = struct( ...
  "motor", struct( ...
    "inertia", 1, "damping", 2, "ratedTorque", 3, ...
    "tauLimit", 4, "velLimit", 5, "maxPermille", 6, ...
    "encoderResolution", uint32(7)), ...
  "load", struct( ...
    "inertia", 8, "damping", 9, "ratedTorque", 10, ...
    "tauLimit", 11, "velLimit", 12, ...
    "encoderResolution", uint32(13)), ...
  "coupling", struct("stiffness", 14, "damping", 15));
end
