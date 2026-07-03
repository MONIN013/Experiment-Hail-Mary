function out = stability_check(Kd_z, plant_mat_path, Smax, Ts, nominal_sample_delay)
%STABILITY_CHECK exp02 の安定性・感度確認を行う。
% data/plant.mat がある場合は、測定 FRF と nominal plant で Nyquist と
% sensitivity を確認する。plant.mat がない場合は警告し、未確認として返す。

out = struct( ...
  "ok", false, ...
  "plant_mat_path", string(plant_mat_path), ...
  "reason", "plant_mat_missing");

if isfile(char(plant_mat_path))
  plant_data = load(char(plant_mat_path));
  if isfield(plant_data, "frf_out")
    freq_hz = plant_data.frf_out.freq_hz(:);
    omega_rad_s = 2 * pi * freq_hz;
    omega_rad_s(omega_rad_s == 0) = eps;
    frf_velocity = plant_data.frf_out.frf(:);
  elseif isfield(plant_data, "plant_out")
    freq_hz = plant_data.plant_out.freq_hz(:);
    omega_rad_s = 2 * pi * freq_hz;
    omega_rad_s(omega_rad_s == 0) = eps;
    frf_velocity = plant_data.plant_out.frf_velocity(:);
  else
    freq_hz = zeros(0, 1);
    omega_rad_s = zeros(0, 1);
    frf_velocity = zeros(0, 1);
    out.reason = "plant_mat_missing_frf";
    warning("experiment:exp02_feedback:plantMatMissingFrf", ...
      "plant_mat_path exists but does not contain frf_out or plant_out.");
  end

  if ~isempty(freq_hz)
    controller_response = squeeze(freqresp(Kd_z, omega_rad_s));
    controller_response = controller_response(:);
    plant_position = frf_velocity ./ (1i * omega_rad_s);
    loop_measured = plant_position .* controller_response;

    vm_cfg = experiment.exp01.nominal_overlay_plant();
    frf_nominal_velocity = experiment.analysis.nominal_two_inertia_frf( ...
      vm_cfg, omega_rad_s, ...
      "Ts", Ts, ...
      "sample_delay", nominal_sample_delay);
    plant_nominal_position = frf_nominal_velocity(:) ./ (1i * omega_rad_s);
    loop_nominal = plant_nominal_position .* controller_response;

    theta = linspace(0, 2*pi, 360);
    figure("Name", "Nyquist Stability Check", "Color", "w");
    plot(real(loop_nominal), imag(loop_nominal), "--", "LineWidth", 1.0, "DisplayName", "nominal"); hold on;
    plot(real(loop_measured), imag(loop_measured), "-", "LineWidth", 1.2, "DisplayName", "measured");
    plot(-1 + cos(theta) / Smax, sin(theta) / Smax, ":", "LineWidth", 1.0, "DisplayName", "Smax circle");
    plot(-1, 0, "kx", "LineWidth", 1.2, "DisplayName", "-1");
    axis equal;
    grid on;
    xlabel("Real");
    ylabel("Imaginary");
    title("Nyquist Check: P(z)K(z)");
    legend("Location", "best");

    sensitivity_measured = 1 ./ (1 + loop_measured);
    sensitivity_nominal = 1 ./ (1 + loop_nominal);
    figure("Name", "Sensitivity Check", "Color", "w");
    semilogx(freq_hz, 20*log10(abs(sensitivity_nominal)), "--", "LineWidth", 1.0, "DisplayName", "nominal"); hold on;
    semilogx(freq_hz, 20*log10(abs(sensitivity_measured)), "-", "LineWidth", 1.2, "DisplayName", "measured");
    yline(20*log10(Smax), ":", "Smax", "LineWidth", 1.0);
    grid on;
    xlabel("Frequency [Hz]");
    ylabel("|S| [dB]");
    title("Sensitivity Check");
    legend("Location", "best");

    out = struct( ...
      "ok", true, ...
      "plant_mat_path", string(plant_mat_path), ...
      "reason", "ok", ...
      "freq_hz", freq_hz, ...
      "loop_measured", loop_measured, ...
      "loop_nominal", loop_nominal, ...
      "sensitivity_measured", sensitivity_measured, ...
      "sensitivity_nominal", sensitivity_nominal, ...
      "Smax", Smax);
  end
else
  warning("experiment:exp02_feedback:plantMatMissing", ...
    "plant_mat_path is not found. Run exp01_SysId first to create data/plant.mat. Continuing without Nyquist/sensitivity check.");
end
end
