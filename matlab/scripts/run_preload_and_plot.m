%% virtualMotor minimal I/O validation script (8 kHz)
baseDir = fileparts(fileparts(mfilename("fullpath")));
restoredefaultpath;
addpath(genpath(baseDir));

%% Connection and model parameters
amsNetId = "192.168.10.3.1.1";
taskRateHz = 8000;
M = 0.01;
D = 0.1;
Kt = 1.0;
tauLimit = 5.0;
velLimit = 100.0;

%% Current command
currentIn = 0.4;
holdSeconds = 2.0;
fprintf("Current command: %.4f A, hold %.3f s\n", currentIn, holdSeconds);

%% Run experiment
out = virtualmotor_run( ...
    "ams_net_id", amsNetId, ...
    "current_in", currentIn, ...
    "hold_seconds", holdSeconds, ...
    "task_rate_hz", taskRateHz, ...
    "M", M, ...
    "D", D, ...
    "Kt", Kt, ...
    "tau_limit", tauLimit, ...
    "vel_limit", velLimit);

%% Evaluation and plotting
raw = out.raw;
cfg = out.config;
m = out.metrics;

seq = raw.log_seq(:);
logI = raw.log_i(:);
logX = raw.log_x(:);

f = figure("Name", "virtualMotor Validation", "Color", "w"); %#ok<NASGU>
tiledlayout(2, 2, "Padding", "compact", "TileSpacing", "compact");

if ~isempty(seq)
    tPlc = (seq - seq(1)) / cfg.task_rate_hz;
else
    tPlc = [];
end

nexttile;
plot(tPlc, logI, "b-", "LineWidth", 1.0); grid on;
xlabel("Time [s]"); ylabel("Current [A]");
title("Input Current");

nexttile;
plot(tPlc, logX, "r-", "LineWidth", 1.0); grid on;
xlabel("Time [s]"); ylabel("Position");
title("Position");

nexttile;
histogram(logI, 60, "FaceColor", [0.3 0.5 0.9]); grid on;
xlabel("Current [A]"); ylabel("Count");
title("Current Distribution");

nexttile;
histogram(logX, 60, "FaceColor", [0.9 0.5 0.3]); grid on;
xlabel("Position"); ylabel("Count");
title("Position Distribution");

acc = m.acceptance;
fn = fieldnames(acc);
av = cellfun(@(f) logical(acc.(f)), fn);
isPass = all(av);
posErr = NaN;
if isfield(m, "model") && isfield(m.model, "position")
    posErr = m.model.position.max_abs_err;
end
sgtitle(sprintf("virtualMotor Validation: %s | pos max|err|=%.3g", ...
    ternary(isPass, "PASS", "FAIL"), posErr));

fprintf("\n=== virtualMotor Validation Summary ===\n");
fprintf("Samples: %d\n", m.sample_count);
fprintf("Final position: %.9g\n", raw.position_last);
fprintf("Final current : %.9g\n", raw.current_last);
if isfield(m, "model") && isfield(m.model, "position")
    fprintf("Position model max|err|: %.6g\n", m.model.position.max_abs_err);
end
if isfield(m, "throughput")
    fprintf("Log throughput: %.1f Hz\n", m.throughput.plc_log_rate_hz);
end
fprintf("--- Acceptance ---\n");
for i = 1:numel(fn)
    fprintf("  %-36s : %s\n", fn{i}, ternary(av(i), "PASS", "FAIL"));
end
fprintf("Overall: %s\n", ternary(isPass, "PASS", "FAIL"));

function s = ternary(c, a, b), if c, s = a; else, s = b; end, end
