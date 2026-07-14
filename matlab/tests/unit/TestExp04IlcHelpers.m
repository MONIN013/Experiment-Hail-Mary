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
        "Qden", 1, ...
        "error_quantum_rad", 1e-6);
      previous_ff = 0.2 * ones(1001, 1);
      error_signal = zeros(size(previous_ff));

      [next_ff, status] = experiment.exp04.learning_update( ...
        previous_ff, error_signal, filters, ...
        "transient_samples", 20, "max_input", 0.1);

      testCase.verifyEqual(next_ff, previous_ff, "AbsTol", 1e-12);
      testCase.verifyFalse(status.ok);
      testCase.verifyEqual(status.reason, "input_limit");
    end

    function learningUpdateRejectsSubEncoderRoundoff(testCase)
      Ts = 1e-3;
      filters = struct( ...
        "Linv", tf(1, 1, Ts), "Qnum", 1, "Qden", 1, ...
        "error_quantum_rad", 1e-6);
      current_ff = zeros(1001, 1);
      nominal_error = 0.25e-6 * ones(1001, 1);
      rounded_error = nominal_error + 4e-15;

      nominal = experiment.exp04.learning_update( ...
        current_ff, nominal_error, filters, "transient_samples", 0);
      rounded = experiment.exp04.learning_update( ...
        current_ff, rounded_error, filters, "transient_samples", 0);

      testCase.verifyEqual(rounded, nominal);
    end

    function simulatesCompleteVirtualMotorCampaign(testCase)
      scenario = small_vm_scenario(zeros(256, 1));
      plant = virtualMotor.PlantConfig();

      plan = testoracle.simulate_ilc_campaign(scenario, plant);

      testCase.verifyEqual(plan.best_trial, 1);
      testCase.verifyEqual(plan.error_norm, zeros(1, 3));
      testCase.verifySize(plan.feedforward, [256, 3]);
      testCase.verifyNumElements(plan.predictions, 3);
      testCase.verifyEqual(plan.max_feedforward_A, 0);
      testCase.verifyEqual(plan.max_total_input_A, 0);
    end

    function simulatedCampaignRejectsPredictedInputLimit(testCase)
      scenario = small_vm_scenario(ones(256, 1), 0.01);
      plant = virtualMotor.PlantConfig();

      testCase.verifyError(@() testoracle.simulate_ilc_campaign( ...
        scenario, plant), "testoracle:ilc:inputLimit");
    end

    function simulatedCampaignRecordsErrorIncreaseAndCompletesTrials(testCase)
      scenario = small_vm_scenario(0.01 * ones(256, 1));
      plant = virtualMotor.PlantConfig();
      scenario.learning_filters.Linv = tf(-1, 1, ...
        1 / scenario.cfg.env.task_rate_hz);

      plan = testoracle.simulate_ilc_campaign(scenario, plant);

      testCase.verifyNumElements(plan.predictions, 3);
      testCase.verifyTrue(any(diff(plan.error_norm) > 0));
      testCase.verifySize(plan.current_cmd, [256, 3]);
      testCase.verifyGreaterThan(plan.max_total_input_A, 0);
      testCase.verifyEqual(plan.initial_states{2}, ...
        plan.predictions{1}.final_state);
      testCase.verifyTrue(plan.inter_trial_state_carried);
    end

    function twoHundredHzVmCompletesTenTrialsWithTempLearningLaw(testCase)
      [scenario, plant] = two_hundred_hz_learning_fixture();

      plan = testoracle.predict_ilc_campaign(scenario, plant);

      testCase.verifyNumElements(plan.predictions, 10);
      testCase.verifyEqual(plan.best_trial, 10);
      testCase.verifyTrue(all(diff(plan.error_norm) < 0));
      testCase.verifyLessThan(plan.error_norm(end), 1.0);
      testCase.verifyLessThan( ...
        plan.error_norm(end) / plan.error_norm(1), 0.01);
      testCase.verifyLessThan(plan.max_feedforward_A, 0.5);
      testCase.verifyLessThan(plan.max_total_input_A, 0.5);
      testCase.verifyLessThan(plan.convergence_factor, 0.8);
      testCase.verifyEqual([plan.endpoints.motor_velocity_count], zeros(1, 10));
      testCase.verifyEqual([plan.endpoints.load_velocity_count], zeros(1, 10));
      testCase.verifyLessThanOrEqual( ...
        max([plan.endpoints.motor_load_position_delta_count]), 2);
    end
  end
end

function scenario = small_vm_scenario(reference, max_input_A)
if nargin < 2
  max_input_A = 1.6;
end
Ts = 1 / 8000;
plant_data = struct( ...
  "Pd", tf(1, 1, Ts), "Pdn", tf(1, 1, Ts), ...
  "Jn", 1, "Dn", 1, "Ts", Ts);
reference = double(reference(:));
trajectory = struct( ...
  "t", (0:numel(reference) - 1)' * Ts, "p", reference);
scenario = experiment.scenario.exp04( ...
  plant_data, trajectory, "Kd", tf(1, 1, Ts), ...
  "trial_count", 3, "max_input_A", max_input_A, ...
  "Npad", 10, "transient_samples", 0, "settling_tail_s", 0, ...
  "save_results", false);
scenario.learning_filters = struct( ...
  "Linv", tf(1, 1, Ts), "Qnum", 1, "Qden", 1, ...
  "max_convergence_gain", 0, ...
  "error_quantum_rad", scenario.learning_error_quantum_rad);
end

function [scenario, plant] = two_hundred_hz_learning_fixture()
Ts = 1 / 8000;
plant = virtualMotor.PlantConfig();
frequency_hz = logspace(0, log10(1/(2*Ts)), 4000)';
omega_rad_s = 2*pi*frequency_hz;
velocity_frf = virtualMotor.discrete_velocity_frf( ...
  plant, omega_rad_s, "Ts", Ts, "sample_delay", 4);
s = tf("s");
z = tf("z", Ts);
position_integrator = Ts*z/(z-1);
integrator_frf = squeeze(freqresp(position_integrator, omega_rad_s));
Pd = frd(velocity_frf .* integrator_frf(:), frequency_hz, ...
  "FrequencyUnit", "Hz");
Pd.Ts = Ts;

torque_per_amp = plant.motor.ratedTorque / 1.6;
Jn = (plant.motor.inertia + plant.load.inertia) / torque_per_amp;
Dn = (plant.motor.damping + plant.load.damping) / torque_per_amp;
Pdn = c2d(1/(Jn*s + Dn)/s, Ts, "zoh") / z^4;
Kd = c2d(experiment.exp02.designpid(Dn/Jn, 0, 1/Jn, 15), Ts, "tustin");
trajectory = experiment.exp0n.load_trajectory( ...
  "expected_sample_time_s", Ts, "table_max_n", 100000);
plant_data = struct( ...
  "Pd", Pd, "Pdn", Pdn, "Jn", Jn, "Dn", Dn, "Ts", Ts);
scenario = experiment.scenario.exp04( ...
  plant_data, trajectory, "Kd", Kd, ...
  "trial_count", 10, "alpha", 0.6, "q_cutoff_hz", 120, ...
  "max_input_A", 1.6, "Npad", 100, "transient_samples", 200, ...
  "settling_tail_s", 9, "save_results", false);
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
