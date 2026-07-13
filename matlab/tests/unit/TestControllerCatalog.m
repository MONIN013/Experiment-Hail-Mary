classdef TestControllerCatalog < matlab.unittest.TestCase
  methods (Test)
    function returnsSevenControllersInTheSpecifiedOrder(testCase)
      plant = nominal_plant();
      catalog = experiment.exp02.controller_catalog(plant);

      testCase.verifyEqual([catalog.name], ...
        ["P", "PI", "filtered PD", "filtered PID", ...
         "lead", "lead-lag", "lead + 200 Hz notch"]);
      testCase.verifyEqual(string(fieldnames(catalog)), ...
        ["name"; "family"; "K"; "Kd"; "controller_cfg"; "design"]);
      designs = [catalog.design];
      testCase.verifyEqual([designs.target_crossover_rad_s], ...
        [10 NaN NaN NaN 15 15 15]);
      testCase.verifyEqual([designs.target_pole_rad_s], ...
        [NaN 4 15 15 NaN NaN NaN]);
      testCase.verifyEqual(catalog(7).design.notch_frequency_hz, 200);
      testCase.verifyEqual(catalog(7).design.notch_zeta_zero, 0.02);
      testCase.verifyEqual(catalog(7).design.notch_zeta_pole, 0.20);
    end

    function everyControllerPassesTheNominalSosAndStabilityGates(testCase)
      plant = nominal_plant();
      catalog = experiment.exp02.controller_catalog(plant, "Smax", 2);

      for k = 1:numel(catalog)
        testCase.verifyClass(catalog(k).controller_cfg, "experiment.ControllerConfig");
        catalog(k).controller_cfg.validate_for_task_rate(1/plant.Ts);
        testCase.verifyTrue(catalog(k).design.gate_ok, catalog(k).name);
        testCase.verifyTrue(catalog(k).design.nominal_closed_loop_stable);
        testCase.verifyTrue(catalog(k).design.real_coefficients_siso);
        testCase.verifyLessThanOrEqual(catalog(k).design.max_sensitivity, 2);
        testCase.verifyLessThanOrEqual(catalog(k).design.sos_section_count, 10);
        testCase.verifyGreaterThan(catalog(k).design.sos_section_count, 0);
      end
      testCase.verifyLessThan( ...
        catalog(7).design.controller_gain_200_hz, ...
        catalog(5).design.controller_gain_200_hz / 5);
    end

    function rejectsAPlantWithMismatchedSampleTime(testCase)
      plant = nominal_plant();
      plant.Ts = 1/4000;

      testCase.verifyError(@() experiment.exp02.controller_catalog(plant), ...
        "experiment:exp02:invalidControllerCatalogPlant");
    end
  end
end

function plant = nominal_plant()
Ts = 1/8000;
Jn = 7.1e-5;
Dn = 5.325e-4;
s = tf("s");
Pdn = c2d(1/(Jn*s^2 + Dn*s), Ts, "zoh");
z = tf("z", Ts);
Pdn = Pdn / z^4;
plant = struct("Pd", Pdn, "Pdn", Pdn, "Jn", Jn, "Dn", Dn, "Ts", Ts);
end
