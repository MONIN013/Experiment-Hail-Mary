%% Controller benchmark on a common 8 kHz trajectory
%
% Seven SISO controllers are loaded through the ControllerCore SOS contract
% and measured sequentially. This normal tool deliberately contains no VM
% configuration, runtime restart, or oracle comparison logic.

tool_file = mfilename("fullpath");
matlab_root = fileparts(fileparts(tool_file));
addpath(matlab_root, fullfile(matlab_root, "experiment"));
clear tool_file matlab_root;

%% User settings
save_results = true;
render_plots = true;
Smax = 2;
repeat_count = 1;
hold_margin_s = 1.0;
settle_timeout_s = 10.0;

%% Common plant and trajectory
cfg_template = experiment.ExperimentConfig.defaults();
script_dir = string(fileparts(mfilename("fullpath")));
data_dir = fullfile(fileparts(script_dir), "experiment", "data");
plant_path = fullfile(data_dir, "plant.mat");
plant = experiment.exp0n.load_plant_data(plant_path, ...
  "expected_sample_time_s", 1/cfg_template.env.task_rate_hz);
trajectory = experiment.exp0n.load_trajectory( ...
  "expected_sample_time_s", plant.Ts, ...
  "table_max_n", cfg_template.env.table_max_n);

catalog = experiment.exp02.controller_catalog(plant, "Smax", Smax);
design_table = controller_benchmark_design_table(catalog);
disp(design_table);
designs = [catalog.design];
failed = ~logical([designs.gate_ok]);
if any(failed)
  details = strings(nnz(failed), 1);
  failed_entries = catalog(failed);
  for k = 1:numel(failed_entries)
    details(k) = failed_entries(k).name + ": " + failed_entries(k).design.gate_reasons;
  end
  error("experiment:controllerBenchmark:designGateFailed", ...
    "Controller design gate failed: %s", strjoin(details, " | "));
end

%% Measured runs
sample_n = trajectory.sample_count;
per_trial_s = sample_n * plant.Ts;
run_stamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
run_dir = fullfile(data_dir, "controller_benchmark_runs", run_stamp);
if save_results && ~isfolder(char(run_dir))
  mkdir(char(run_dir));
end

rows = cell(numel(catalog), 1);
run_summaries = repmat(struct( ...
  "controller", "", "runner_path", "", "logger_path", "", ...
  "logger_archive_path", "", "logger_record_count", 0, ...
  "settle_elapsed_s", 0, "settle_motor_position_count", 0, ...
  "settle_load_position_count", 0, ...
  "settle_motor_velocity_count", 0, "settle_load_velocity_count", 0, ...
  "done", false, "timed_out", false), numel(catalog), 1);
for k = 1:numel(catalog)
  cfg = experiment.ExperimentConfig.defaults();
  cfg.ref_profile = trajectory.p;
  cfg.ff_profile = zeros(sample_n, 1);
  cfg.dist_profile = zeros(sample_n, 1);
  cfg.repeat_count = repeat_count;
  cfg.wait_for_done = true;
  cfg.hold_seconds = per_trial_s + hold_margin_s;
  cfg.done_timeout_s = repeat_count * per_trial_s + hold_margin_s + 5.0;
  cfg.logger_release_timeout_s = max(5.0, repeat_count * per_trial_s / 10);
  cfg.host_heartbeat_enable = false;
  cfg.external_host_heartbeat_enable = true;
  cfg.controller = catalog(k).controller_cfg;
  if save_results
    cfg.save_path = char(fullfile(run_dir, ...
      sprintf("%02d_%s_runner.mat", k, controller_benchmark_slug(catalog(k).name))));
  end

  settle = controller_benchmark_wait_for_settle(cfg, settle_timeout_s);
  collect_out = experiment.exp0n.run_and_collect(cfg);
  experiment.exp0n.assert_run_contract(collect_out.run);
  [signals, ~] = experiment.exp02.signals_from_logger_bin( ...
    collect_out.logger_bin, "expected_sample_count", sample_n * repeat_count);
  rows{k} = experiment.exp02.controller_benchmark_metrics(catalog(k), signals);
  logger_archive = controller_benchmark_archive_logger( ...
    collect_out.logger_bin, run_dir, k, catalog(k).name, save_results);
  run_summaries(k) = struct( ...
    "controller", catalog(k).name, ...
    "runner_path", string(cfg.save_path), ...
    "logger_path", string(collect_out.run.logger.file_path), ...
    "logger_archive_path", string(logger_archive.path), ...
    "logger_record_count", double(logger_archive.record_count), ...
    "settle_elapsed_s", double(settle.elapsed_s), ...
    "settle_motor_position_count", double(settle.motor_position_count), ...
    "settle_load_position_count", double(settle.load_position_count), ...
    "settle_motor_velocity_count", double(settle.motor_velocity_count), ...
    "settle_load_velocity_count", double(settle.load_velocity_count), ...
    "done", logical(collect_out.run.host.done), ...
    "timed_out", logical(collect_out.run.host.timed_out));
end

results_table = vertcat(rows{:});
disp(results_table);
benchmark = struct( ...
  "created_at", datetime("now", "TimeZone", "local"), ...
  "plant_path", string(plant_path), ...
  "trajectory_path", string(trajectory.file_path), ...
  "catalog", catalog, ...
  "design_table", design_table, ...
  "results_table", results_table, ...
  "runs", run_summaries, ...
  "summary_path", "");

if render_plots
  controller_benchmark_plot(results_table);
end
if save_results
  summary_path = fullfile(run_dir, "controller_benchmark_summary.mat");
  benchmark.summary_path = string(summary_path);
  save(char(summary_path), "benchmark");
end

%% Local presentation helpers

function out = controller_benchmark_design_table(catalog)
designs = [catalog.design];
out = table( ...
  [catalog.name].', [catalog.family].', ...
  [designs.max_sensitivity].', ...
  [designs.controller_gain_200_hz].', ...
  [designs.sos_section_count].', ...
  logical([designs.gate_ok].'), ...
  VariableNames=["controller", "family", "sensitivityPeak", ...
    "controllerGain200Hz", "sosSections", "gatePassed"]);
end

function value = controller_benchmark_slug(name)
value = lower(regexprep(char(string(name)), "[^A-Za-z0-9]+", "_"));
value = regexprep(value, "(^_+|_+$)", "");
end

function capture = controller_benchmark_archive_logger( ...
    logger_bin, run_dir, index, controller_name, save_results)
if save_results
  destination = fullfile(run_dir, sprintf("%02d_%s_logger.bin", ...
    index, controller_benchmark_slug(controller_name)));
  capture = experiment.exp0n.archive_logger(logger_bin, destination);
else
  capture = struct("path", "", ...
    "record_count", double(logger_bin.record_count));
end
end

function settle = controller_benchmark_wait_for_settle(cfg, timeout_s)
conn = experiment.ConnectionManager.create(cfg);
cleanup = onCleanup(@() conn.session.close());
settle = virtualMotor.wait_for_settle(conn.module, timeout_s, ...
  "max_position_delta_counts", 2);
clear cleanup
end

function controller_benchmark_plot(results)
names = string(results.controller);
x = 1:height(results);
figure("Name", "SISO Controller Benchmark");
layout = tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");

nexttile(layout);
bar(x, results.trackingErrorRms);
ylabel("Tracking RMS [rad]");
title("Tracking error");
grid on;

nexttile(layout);
bar(x, results.maxControlInputA);
yline(1.28, "r--", "1.28 A gate");
ylabel("Maximum input [A]");
title("Control effort");
grid on;

nexttile(layout);
bar(x, results.sensitivityPeak);
yline(2, "r--", "S_{max}");
ylabel("Peak |S|");
title("Sensitivity");
grid on;

nexttile(layout);
bar(x, results.controllerGain200Hz);
set(gca, "YScale", "log");
ylabel("|K(200 Hz)| [A/rad]");
title("Controller gain at 200 Hz");
grid on;

axes_handles = findall(gcf, "Type", "Axes");
for k = 1:numel(axes_handles)
  axes_handles(k).XTick = x;
  axes_handles(k).XTickLabel = names;
  axes_handles(k).XTickLabelRotation = 25;
end
title(layout, "SISO Controller Benchmark");
drawnow;
end
