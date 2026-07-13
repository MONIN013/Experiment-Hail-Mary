classdef TestVirtualMotorPrediction < matlab.unittest.TestCase
  methods (Test)
    function predictsFixedRuntimePipelineAndQuantizedPlant(testCase)
      cfg = experiment.ExperimentConfig.defaults();
      n = 64;
      cfg.ref_profile = zeros(n, 1);
      cfg.ff_profile = [0; 0.2 * ones(n - 1, 1)];
      cfg.dist_profile = zeros(n, 1);
      cfg.controller = experiment.ControllerConfig.p_only(0);
      plant = virtualMotor.PlantConfig();

      out = virtualMotor.predict_logger(cfg, plant);

      testCase.verifyEqual(out.sample_count, n);
      testCase.verifyEqual(out.raw.t_s, double(out.raw.t_ns) * 1e-9);
      testCase.verifyEqual(out.raw.ff_value(2:end), cfg.ff_profile(1:end-1));
      testCase.verifyEqual(out.raw.control_input(3:end), cfg.ff_profile(1:end-2));
      testCase.verifyEqual(out.raw.current_cmd(4:end), cfg.ff_profile(1:end-3));
      testCase.verifyFalse(out.fault.motor);
      testCase.verifyFalse(out.fault.load);
      testCase.verifyFalse(out.position_saturated);
      testCase.verifyTrue(any(out.raw.motor_velocity ~= 0));
      testCase.verifyTrue(any(out.raw.load_position ~= 0));
    end

    function exactPredictionPassesAndEncoderRegressionFails(testCase)
      cfg = experiment.ExperimentConfig.defaults();
      n = 100;
      cfg.ref_profile = zeros(n, 1);
      cfg.ff_profile = 0.01 * ones(n, 1);
      cfg.dist_profile = zeros(n, 1);
      cfg.controller = experiment.ControllerConfig.p_only(0);
      plant = virtualMotor.PlantConfig();
      prediction = virtualMotor.predict_logger(cfg, plant);

      logger = struct("raw", prediction.raw, "record_count", n);
      metrics = virtualMotor.compare_prediction(logger, prediction);
      testCase.verifyTrue(metrics.pass);

      logger.raw.load_position(50) = logger.raw.load_position(50) + ...
        3 * prediction.encoder_quantum_load_rad;
      metrics = virtualMotor.compare_prediction(logger, prediction);
      testCase.verifyFalse(metrics.pass);
      testCase.verifyFalse(metrics.signals.load_position.pass);
      testCase.verifyError(@() virtualMotor.assert_prediction(metrics, "test"), ...
        "virtualMotor:prediction:mismatch");

      logger = struct("raw", prediction.raw, "record_count", n);
      logger.raw.error(25) = logger.raw.error(25) + ...
        prediction.encoder_quantum_load_rad;
      logger.raw.control_input(25) = logger.raw.control_input(25) + 5e-6;
      logger.raw.motor_current_act(25) = logger.raw.motor_current_act(25) + ...
        prediction.driver_current_quantum_A;
      metrics = virtualMotor.compare_prediction(logger, prediction);
      testCase.verifyTrue(metrics.pass);

      logger.raw.control_input(25) = prediction.raw.control_input(25) + 1e-4;
      metrics = virtualMotor.compare_prediction(logger, prediction);
      testCase.verifyFalse(metrics.pass);
      testCase.verifyFalse(metrics.signals.control_input.pass);
    end

    function unsafeSiStimulusPredictsFaultOrSaturation(testCase)
      cfg = experiment.ExperimentConfig.defaults();
      Ts = 1 / cfg.env.task_rate_hz;
      chirp = experiment.waveform.periodic_chirp( ...
        "Ts", Ts, "Tend", 10, "Tcycle", 10, ...
        "f0", 0.1, "f1", 4000, "A", 1);
      cfg.ref_profile = zeros(chirp.sample_count, 1);
      cfg.ff_profile = chirp.signal;
      cfg.dist_profile = zeros(chirp.sample_count, 1);
      cfg.repeat_count = 10;
      cfg.controller = experiment.ControllerConfig.p_only(0);
      plant = virtualMotor.PlantConfig();

      prediction = virtualMotor.predict_logger(cfg, plant);

      testCase.verifyTrue(prediction.fault.motor || prediction.fault.load || ...
        prediction.position_saturated);
    end

    function checkedInExp01StimulusRemainsSafeInTestOracle(testCase)
      scenario = experiment.scenario.exp01("save_results", false);
      cfg = scenario.cfg;
      plant = virtualMotor.PlantConfig();

      prediction = virtualMotor.predict_logger(cfg, plant);

      testCase.verifyEqual(prediction.sample_count, scenario.expected_sample_count);
      testCase.verifyFalse(prediction.fault.motor);
      testCase.verifyFalse(prediction.fault.load);
      testCase.verifyFalse(prediction.position_saturated);
    end

    function discreteFrfMatchesPredictedSteadyStateAtTorsionalMode(testCase)
      cfg = experiment.ExperimentConfig.defaults();
      Ts = 1 / cfg.env.task_rate_hz;
      n = cfg.env.task_rate_hz;
      frequency_hz = 200;
      time_s = (0:n-1)' * Ts;
      cfg.ref_profile = zeros(n, 1);
      cfg.ff_profile = 0.1 * sin(2*pi*frequency_hz*time_s);
      cfg.dist_profile = zeros(n, 1);
      cfg.controller = experiment.ControllerConfig.p_only(0);
      plant = virtualMotor.PlantConfig();

      prediction = virtualMotor.predict_logger(cfg, plant);
      keep = time_s >= 0.25;
      basis = exp(-1i*2*pi*frequency_hz*time_s(keep));
      measured = sum(prediction.raw.load_velocity(keep) .* basis) / ...
        sum(prediction.raw.ff_value(keep) .* basis);
      expected = virtualMotor.discrete_velocity_frf( ...
        plant, 2*pi*frequency_hz, ...
        "Ts", Ts, "sample_delay", 4, "axis", "load");

      testCase.verifyEqual(abs(measured), abs(expected), "RelTol", 2e-3);
      phase_error_deg = experiment.wrap_phase_at_180( ...
        rad2deg(angle(measured / expected)));
      testCase.verifyLessThan(abs(phase_error_deg), 0.2);
    end

    function settleGateAcceptsStationaryObservableState(testCase)
      module = MockAdsTransport();
      prefix = "VirtualMotorCore_Obj1 (Module1).Outputs.";
      module.scalarMap(char(prefix + "motor.positionActualValue")) = int32(100);
      module.scalarMap(char(prefix + "motor.velocityActualValue")) = int32(0);
      module.scalarMap(char(prefix + "load.positionActualValue")) = int32(101);
      module.scalarMap(char(prefix + "load.velocityActualValue")) = int32(0);

      out = virtualMotor.wait_for_settle(module, 0.01);

      testCase.verifyTrue(out.settled);
      testCase.verifyEqual(out.motor_position_count, 100);
      testCase.verifyEqual(out.load_position_count, 101);
      testCase.verifyEqual(nnz(startsWith(module.operations, "read_scalar:")), 4);
    end

    function settleGateRejectsSaturatedPosition(testCase)
      module = MockAdsTransport();
      prefix = "VirtualMotorCore_Obj1 (Module1).Outputs.";
      module.scalarMap(char(prefix + "motor.positionActualValue")) = int32(intmax("int32"));
      module.scalarMap(char(prefix + "motor.velocityActualValue")) = int32(0);
      module.scalarMap(char(prefix + "load.positionActualValue")) = int32(intmax("int32"));
      module.scalarMap(char(prefix + "load.velocityActualValue")) = int32(0);

      testCase.verifyError(@() virtualMotor.wait_for_settle(module, 0.01), ...
        "virtualMotor:settle:positionSaturated");
    end

    function settleGateRejectsNegativeSaturatedPosition(testCase)
      module = MockAdsTransport();
      prefix = "VirtualMotorCore_Obj1 (Module1).Outputs.";
      module.scalarMap(char(prefix + "motor.positionActualValue")) = int32(intmin("int32"));
      module.scalarMap(char(prefix + "motor.velocityActualValue")) = int32(0);
      module.scalarMap(char(prefix + "load.positionActualValue")) = int32(intmin("int32"));
      module.scalarMap(char(prefix + "load.velocityActualValue")) = int32(0);

      testCase.verifyError(@() virtualMotor.wait_for_settle(module, 0.01), ...
        "virtualMotor:settle:positionSaturated");
    end
  end
end
