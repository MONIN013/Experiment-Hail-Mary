function si_frf(freq_hz, frf_measured, frf_nominal, coherence, transient_cycles)
% si_frf  Plot measured and nominal SI FRF.
mag_measured_db = mag2db(abs(frf_measured(:)));
mag_nominal_db = mag2db(abs(frf_nominal(:)));
phase_measured_deg = experiment.wrap_phase_at_180(rad2deg(unwrap(angle(frf_measured(:)))));
phase_nominal_deg = experiment.wrap_phase_at_180(rad2deg(unwrap(angle(frf_nominal(:)))));

figure("Name", "Real Motor SI", "Color", "w");
tiledlayout(3, 1, "Padding", "compact", "TileSpacing", "compact");

nexttile;
semilogx(freq_hz, mag_measured_db, "-", "LineWidth", 1.2, "DisplayName", "Measured"); hold on;
semilogx(freq_hz, mag_nominal_db, "--", "LineWidth", 1.2, "DisplayName", "Nominal");
hold off;
grid on;
xlabel("Frequency [Hz]");
ylabel("Gain [dB]");
legend("Location", "best");
title("FRF Gain: ffValue -> loadVelocity");

nexttile;
semilogx(freq_hz, phase_measured_deg, "-", "LineWidth", 1.2, "DisplayName", "Measured"); hold on;
semilogx(freq_hz, phase_nominal_deg, "--", "LineWidth", 1.2, "DisplayName", "Nominal");
hold off;
grid on;
xlabel("Frequency [Hz]");
ylabel("Phase [deg]");
ylim([-180, 180]);
yticks([-180, -135, -90, -45, 0, 45, 90, 135, 180]);
legend("Location", "best");
title("FRF Phase: ffValue -> loadVelocity");

nexttile;
semilogx(freq_hz, coherence(:), "-", "LineWidth", 1.2);
grid on;
xlabel("Frequency [Hz]");
ylabel("Coherence");
ylim([0, 1.05]);
title(sprintf("Coherence (transient cycles removed = %d)", transient_cycles));
end
