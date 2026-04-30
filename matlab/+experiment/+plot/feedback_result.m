function feedback_result(signals, metrics)
% feedback_result  Plot tracking, error, and current signals.
t_log = signals.time_s(:);

figure("Name", "Feedback Experiment Result", "Color", "w");
tiledlayout(3, 1, "Padding", "compact", "TileSpacing", "compact");

nexttile;
plot(t_log, signals.ref_value(:), "-", "Color", [0.55 0.55 0.55], "LineWidth", 0.9, "DisplayName", "ref"); hold on;
plot(t_log, signals.position_act(:), "-", "Color", [0.1 0.45 0.75], "LineWidth", 1.2, "DisplayName", "loadPosition");
hold off;
grid on;
xlabel("Time [s]");
ylabel("Position [rad]");
legend("Location", "best");
title("Tracking");

nexttile;
plot(t_log, signals.error(:), "-", "Color", [0.85 0.25 0.2], "LineWidth", 1.2);
grid on;
xlabel("Time [s]");
ylabel("Error [rad]");
title(sprintf("Tracking Error (L2 = %.4g)", metrics.tracking_error_l2));

nexttile;
plot(t_log, signals.control_input(:), "-", "Color", [0.45 0.25 0.75], "LineWidth", 1.2, "DisplayName", "controlInput"); hold on;
plot(t_log, signals.current_cmd(:), "--", "Color", [0.2 0.6 0.2], "LineWidth", 0.9, "DisplayName", "currentCmd");
hold off;
grid on;
xlabel("Time [s]");
ylabel("Current [A]");
legend("Location", "best");
title("Controller Output");
end
