classdef TestHigsExperiment < matlab.unittest.TestCase
  methods (Test)
    function previewUsesSameReferenceAndNeverNeedsPlantOrAds(testCase)
      path = write_design();
      clean = onCleanup(@() delete(path));
      a = exp05_Higs("preview", "design_path", path, "plot", false, ...
        "plant_path", "missing-plant.mat");
      b = exp05_Higs("preview", "design_path", path, "plot", false);
      testCase.verifyEqual(a.reference, b.reference);
      testCase.verifyEqual(a.reference(1), 0, "AbsTol", 1e-14);
      testCase.verifyEqual(a.reference(end), 0, "AbsTol", 1e-14);
      testCase.verifyEqual(max(a.reference), 0.1, "AbsTol", 1e-14);
      testCase.verifyEqual(diff(a.t), repmat(1/8000, numel(a.t)-1, 1), "AbsTol", 1e-15);
      testCase.verifyFalse(a.linear.higs_enabled);
      testCase.verifyTrue(a.higs.higs_enabled);
      testCase.verifyFalse(isfield(a, "run"));
      testCase.verifySize(a.linear.sos, [1, 6]);
      testCase.verifySize(a.higs.sos, [1, 6]);
      testCase.verifyFalse(a.io_backend_verified);
      testCase.verifyEqual(a.target_label, "");
    end

    function labelDoesNotSelectConnection(testCase)
      path = write_design();
      clean = onCleanup(@() delete(path));
      a = exp05_Higs("preview", "design_path", path, "plot", false, "target_label", "bench-A");
      b = exp05_Higs("preview", "design_path", path, "plot", false, "target_label", "bench-B");
      testCase.verifyEqual(a.connection_environment, b.connection_environment);
      testCase.verifyEqual(a.target_label, "bench-A");
      testCase.verifyEqual(b.target_label, "bench-B");
      testCase.verifyFalse(a.io_backend_verified);
      testCase.verifyFalse(b.io_backend_verified);
    end

    function linearGateExcludesOnlyDc(testCase)
      [plant, controller] = example_plant();
      response = plant.Pd.ResponseData;
      response(1,1,1) = Inf;
      plant.Pd = frd(response, plant.Pd.Frequency, plant.Ts, "FrequencyUnit", "Hz");
      check = experiment.higs_linear_check(plant, controller, 2, false);
      testCase.verifyTrue(check.dc_excluded);
      testCase.verifyEqual(check.frequency_band_hz, [1, 1000]);
      response(1,1,3) = NaN;
      plant.Pd = frd(response, plant.Pd.Frequency, plant.Ts, "FrequencyUnit", "Hz");
      testCase.verifyError(@() experiment.higs_linear_check(plant, controller, 2, false), ...
        "experiment:higs:invalidPositiveFrf");
    end

    function linearGateRejectsMissingBandAndPeriodMismatch(testCase)
      [plant, controller] = example_plant();
      f = [1;10;100];
      plant.Pd = frd(squeeze(freqresp(plant.Pdn, 2*pi*f)), f, plant.Ts, "FrequencyUnit", "Hz");
      testCase.verifyError(@() experiment.higs_linear_check(plant, controller, 2, false), ...
        "experiment:higs:insufficientFrequencyBand");
      [plant, controller] = example_plant();
      plant.Pdn.Ts = 1/4000;
      testCase.verifyError(@() experiment.higs_linear_check(plant, controller, 2, false), ...
        "experiment:higs:plantSampleTime");
    end

    function runRequiresExplicitTargetLabelBeforeConnection(testCase)
      path = write_design();
      clean = onCleanup(@() delete(path));
      testCase.verifyError(@() exp05_Higs("linear", "design_path", path, "plot", false), ...
        "experiment:higs:targetLabelRequired");
    end

    function runRequiresMeasuredPlantBeforeConnection(testCase)
      path = write_design();
      clean = onCleanup(@() delete(path));
      testCase.verifyError(@() exp05_Higs("higs", "design_path", path, ...
        "plot", false, "target_label", "bench-A", "plant_path", "missing-plant.mat"), ...
        "experiment:exp0n:plantRequired");
    end
  end
end

function path = write_design()
d = struct("linear_sos", [1,0,0,1,0,0], "higs_sos", [1,0,0,1,0,0], ...
  "pre_section_count", 0, "higs_gain", 1, "higs_omega_ts", 0.01, ...
  "sample_time_s", 1/8000, "reference_amplitude_rad", 0.1, ...
  "move_time_s", 0.1, "dwell_time_s", 0.2, "settle_time_s", 0.4, ...
  "sensitivity_limit", 2, "max_current_a", 0.08, ...
  "max_position_rad", 0.25, "max_velocity_rad_s", 10, "max_twist_rad", 0.01);
path = string(tempname()) + ".json";
fid = fopen(path, "w");
clean = onCleanup(@() fclose(fid));
fprintf(fid, "%s", jsonencode(d));
end

function [plant, controller] = example_plant()
Ts = 1/8000;
Pdn = c2d(tf(1, [0.01, 1]), Ts);
f = [0; 1; 10; 200; 500; 1000];
Pd = frd(squeeze(freqresp(Pdn, 2*pi*f)), f, Ts, "FrequencyUnit", "Hz");
plant = struct("Pd", Pd, "Pdn", Pdn, "Ts", Ts);
controller = experiment.ControllerConfig.from_struct(struct( ...
  "sos", [0.1,0,0,1,0,0], "sample_time_s", Ts));
end
