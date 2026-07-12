classdef TestExperimentDataLoaders < matlab.unittest.TestCase
  methods (Test)
    function trackedTrajectoryHasCanonicalHashAndUnits(testCase)
      trajectory = experiment.exp0n.load_trajectory();

      testCase.verifyEqual(trajectory.sample_count, 8000);
      testCase.verifyEqual(median(diff(trajectory.t)), 1.25e-4, "AbsTol", 1e-15);
      testCase.verifyEqual(max(trajectory.p), deg2rad(720), "AbsTol", 1e-10);
      testCase.verifyEqual(trajectory.units, "rad");
      testCase.verifyEqual(file_sha256(trajectory.file_path), ...
        "11c4e587d2e413707c09ca0875779269e1f6f7ecfd1cec1c50030c18a62b5cb0");
    end

    function plantLoaderAcceptsCanonicalContract(testCase)
      file_path = [tempname '.mat'];
      cleanup = onCleanup(@() delete_if_exists(file_path)); %#ok<NASGU>
      create_plant_fixture(file_path, 1.25e-4);

      data = experiment.exp0n.load_plant_data( ...
        file_path, "expected_sample_time_s", 1.25e-4);

      testCase.verifyEqual(data.Jn, 7.1e-5);
      testCase.verifyEqual(data.Ndelay, 2);
      testCase.verifyClass(data.Pd, "frd");
    end

    function plantLoaderRejectsSampleTimeMismatch(testCase)
      file_path = [tempname '.mat'];
      cleanup = onCleanup(@() delete_if_exists(file_path)); %#ok<NASGU>
      create_plant_fixture(file_path, 1e-3);

      testCase.verifyError(@() experiment.exp0n.load_plant_data( ...
        file_path, "expected_sample_time_s", 1.25e-4), ...
        "experiment:exp0n:sampleTimeMismatch");
    end
  end
end

function create_plant_fixture(file_path, Ts)
freq_hz = [1; 10; 100];
response = reshape([1; 0.5; 0.1], 1, 1, []);
Pd = frd(response, freq_hz, "FrequencyUnit", "Hz");
Pd_motor = Pd;
Pd_load = Pd;
Pd_vel_load = Pd;
Pd_vel_motor = Pd;
Pdn = tf(1, [1 1], Ts);
Jn = 7.1e-5;
Dn = 5.325e-4;
Ndelay = 2;
save(file_path, "Pd", "Pd_motor", "Pd_load", "Pd_vel_load", ...
  "Pd_vel_motor", "Pdn", "Jn", "Dn", "Ndelay", "Ts");
end

function digest = file_sha256(file_path)
fid = fopen(file_path, "rb");
if fid < 0
  error("test:resourceReadFailed", "Cannot open %s.", file_path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, "*uint8");
engine = java.security.MessageDigest.getInstance("SHA-256");
engine.update(bytes);
digest = lower(join(string(dec2hex(typecast(engine.digest(), "uint8"), 2)), ""));
end

function delete_if_exists(file_path)
if isfile(file_path)
  delete(file_path);
end
end
