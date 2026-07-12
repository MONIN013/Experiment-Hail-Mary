classdef TestExp04IlcHelpers < matlab.unittest.TestCase
  methods (Test)
    function srinvRoundTripsNonMinimumPhaseSystemOnInteriorSamples(testCase)
      Ts = 1e-3;
      n = 1600;
      t = (0:n-1)' * Ts;
      z = tf("z", Ts);
      plant = (z - 1.25) / (z - 0.35);
      desired_output = 0.35 + ...
        0.20*sin(2*pi*3*t + 0.2) + ...
        0.07*cos(2*pi*11*t);

      inverse_input = experiment.exp04.srinv(plant, desired_output, 180);
      round_trip = lsim(plant, inverse_input, t);

      interior = 260:(n-260);
      relative_error = norm(round_trip(interior) - desired_output(interior)) / ...
        norm(desired_output(interior));
      testCase.verifyLessThan(relative_error, 1e-5);
    end

    function srinvMatchesExactInverseForStableBiproperSystem(testCase)
      Ts = 1e-3;
      n = 1400;
      t = (0:n-1)' * Ts;
      phase = linspace(0, 1, n)';
      envelope = phase.^2 .* (1 - phase).^2;
      z = tf("z", Ts);
      plant = (z - 0.20) / (z - 0.60);
      exact_inverse = 1 / plant;
      ref = envelope .* (0.4*sin(2*pi*4*t) + 0.15*cos(2*pi*9*t + 0.1));
      [inverse_num, inverse_den] = tfdata(tf(exact_inverse), "v");

      actual = experiment.exp04.srinv(plant, ref, 160);
      expected = filter(inverse_num, inverse_den, ref);

      testCase.verifyLessThan(norm(actual - expected) / norm(expected), 1e-8);
    end

    function filtfiltCleanIsZeroPhaseAndSuppressesEndpointTransients(testCase)
      B = [0.2 0.2];
      A = [1 -0.6];
      n = 801;
      center = 401;
      impulse = zeros(n, 1);
      impulse(center) = 1;

      impulse_response = experiment.exp04.filtfilt_clean(B, A, impulse, 220);
      radius = 160;
      left = impulse_response(center-(1:radius));
      right = impulse_response(center+(1:radius));
      testCase.verifyLessThan(max(abs(left(:) - right(:))), 1e-10);

      nonzero_endpoint_signal = 2.5 * ones(n, 1);
      filtered_constant = experiment.exp04.filtfilt_clean(B, A, nonzero_endpoint_signal, 220);
      testCase.verifyLessThan(max(abs(filtered_constant - nonzero_endpoint_signal)), 1e-10);
      testCase.verifyLessThan(max(abs(filtered_constant([1 end]) - 2.5)), 1e-10);
    end

    function designpidPlacesRigidModelClosedLoopAtFourthOrderRepeatedPole(testCase)
      s = tf("s");
      d = 0.42;
      k = 0;
      Kt = 3.7;
      w = 20;
      plant = Kt / (s^2 + d*s);
      controller = experiment.exp02.designpid(d, k, Kt, w);

      [plant_num, plant_den] = tfdata(tf(plant), "v");
      [controller_num, controller_den] = tfdata(tf(controller), "v");
      closed_loop_characteristic = add_polynomials( ...
        conv(plant_den, controller_den), ...
        conv(plant_num, controller_num));
      closed_loop_characteristic = closed_loop_characteristic / closed_loop_characteristic(1);
      expected_characteristic = [1 4*w 6*w^2 4*w^3 w^4];

      coefficient_error = norm(closed_loop_characteristic - expected_characteristic) / ...
        norm(expected_characteristic);
      testCase.verifyLessThan(coefficient_error, 1e-10);
    end

    function learningUpdateReportsInputLimit(testCase)
      Ts = 1e-3;
      z = tf("z", Ts);
      filters = struct( ...
        "Linv", (z - 0.2) / (z - 0.6), ...
        "Qnum", 1, ...
        "Qden", 1);
      previous_ff = 0.2 * ones(1001, 1);
      error_signal = zeros(size(previous_ff));

      [next_ff, status] = experiment.exp04.learning_update( ...
        previous_ff, error_signal, filters, ...
        "transient_samples", 20, "max_input", 0.1);

      testCase.verifyEqual(next_ff, previous_ff, "AbsTol", 1e-12);
      testCase.verifyFalse(status.ok);
      testCase.verifyEqual(status.reason, "input_limit");
    end

    function precomputesCompleteVirtualMotorCampaign(testCase)
      cfg = small_vm_config(zeros(256, 1));
      filters = identity_learning_filters(1 / cfg.env.task_rate_hz);

      plan = experiment.exp04.precompute_virtual_motor_plan( ...
        cfg, cfg.ref_profile, filters, ...
        "trial_count", 3, "Npad", 10, "transient_samples", 0);

      testCase.verifyEqual(plan.completedTrials, 3);
      testCase.verifyEqual(plan.stopReason, "completed");
      testCase.verifyEqual(plan.bestTrial, 1);
      testCase.verifyEqual(plan.eNorm, zeros(1, 3));
      testCase.verifySize(plan.f, [256, 3]);
      testCase.verifyNumElements(plan.predictions, 3);
    end

    function precomputedCampaignRejectsPredictedInputLimit(testCase)
      cfg = small_vm_config(ones(256, 1));
      filters = identity_learning_filters(1 / cfg.env.task_rate_hz);

      testCase.verifyError(@() experiment.exp04.precompute_virtual_motor_plan( ...
        cfg, cfg.ref_profile, filters, ...
        "trial_count", 3, "Npad", 10, "transient_samples", 0, ...
        "max_input", 0.01), "experiment:exp04:inputLimitExceeded");
    end

    function precomputedCampaignRecordsErrorIncreaseAndCompletesTrials(testCase)
      cfg = small_vm_config(0.01 * ones(256, 1));
      filters = identity_learning_filters(1 / cfg.env.task_rate_hz);
      filters.Linv = tf(-1, 1, 1 / cfg.env.task_rate_hz);

      plan = experiment.exp04.precompute_virtual_motor_plan( ...
        cfg, cfg.ref_profile, filters, ...
        "trial_count", 3, "Npad", 0, "transient_samples", 0);

      testCase.verifyEqual(plan.completedTrials, 3);
      testCase.verifyEqual(plan.stopReason, "completed");
      testCase.verifyTrue(any(plan.errorIncreased(2:end)));
      testCase.verifySize(plan.maxAbsInput, [1, 3]);
    end

    function twoHundredHzVmCompletesTenTrialsWithTempLearningLaw(testCase)
      [cfg, reference, filters] = two_hundred_hz_learning_fixture();

      plan = experiment.exp04.precompute_virtual_motor_plan( ...
        cfg, reference, filters, ...
        "trial_count", 10, "alpha", 0.6, "Npad", 100, ...
        "transient_samples", 200, "max_input", 1.6);

      testCase.verifyEqual(plan.completedTrials, 10);
      testCase.verifyEqual(plan.stopReason, "completed");
      testCase.verifyEqual(plan.bestTrial, 10);
      testCase.verifyTrue(all(diff(plan.eNorm) < 0));
      testCase.verifyLessThan(plan.eNorm(end), 1.0);
      testCase.verifyLessThan(max(abs(plan.f), [], "all"), 0.5);
      testCase.verifyLessThan(filters.max_convergence_gain, 0.8);
    end
  end
end

function cfg = small_vm_config(reference)
cfg = experiment.ExperimentConfig.defaults();
cfg.ref_profile = reference(:);
cfg.ff_profile = zeros(size(reference(:)));
cfg.dist_profile = zeros(size(reference(:)));
cfg.controller = experiment.ControllerConfig.p_only(0);
cfg.write_virtual_motor_params = true;
cfg.virtual_motor_plant = virtualMotor.PlantConfig();
end

function filters = identity_learning_filters(Ts)
filters = struct("Linv", tf(1, 1, Ts), "Qnum", 1, "Qden", 1);
end

function [cfg, reference, filters] = two_hundred_hz_learning_fixture()
Ts = 1 / 8000;
plant = virtualMotor.PlantConfig();
frequency_hz = logspace(0, log10(1/(2*Ts)), 4000)';
omega_rad_s = 2*pi*frequency_hz;
velocity_frf = experiment.analysis.nominal_two_inertia_frf( ...
  plant, omega_rad_s, "Ts", Ts, "sample_delay", 3);
s = tf("s");
position_integrator = c2d(1/s, Ts, "tustin");
integrator_frf = squeeze(freqresp(position_integrator, omega_rad_s));
Pd = frd(velocity_frf .* integrator_frf(:), frequency_hz, ...
  "FrequencyUnit", "Hz");
Pd.Ts = Ts;

torque_per_amp = plant.motor.ratedTorque / 1.6;
Jn = (plant.motor.inertia + plant.load.inertia) / torque_per_amp;
Dn = (plant.motor.damping + plant.load.damping) / torque_per_amp;
z = tf("z", Ts);
Pdn = c2d(1/(Jn*s + Dn)/s, Ts, "zoh") / z^2;
Kd = c2d(experiment.exp02.designpid(Dn/Jn, 0, 1/Jn, 15), Ts, "tustin");
filters = experiment.exp04.design_learning_filters( ...
  Pd, Pdn, Kd, Ts, 0.6, 120, false);

trajectory = experiment.exp0n.load_trajectory( ...
  "expected_sample_time_s", Ts, "table_max_n", 100000);
reference = trajectory.p;
cfg = experiment.ExperimentConfig.defaults();
cfg.ref_profile = reference;
cfg.ff_profile = zeros(size(reference));
cfg.dist_profile = zeros(size(reference));
cfg.controller = experiment.controller.from_discrete_tf(Kd);
cfg.write_virtual_motor_params = true;
cfg.virtual_motor_plant = plant;
end

function out = add_polynomials(a, b)
a = a(:).';
b = b(:).';
width = max(numel(a), numel(b));
out = [zeros(1, width - numel(a)) a] + [zeros(1, width - numel(b)) b];
out = trim_leading_near_zero(out);
end

function out = trim_leading_near_zero(values)
first = find(abs(values) > 1e-12, 1, "first");
if isempty(first)
  out = 0;
else
  out = values(first:end);
end
end
