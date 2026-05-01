%% Check ExperimentLogger bin files on \\sunnyday\ExperimentData
%
%  共有フォルダ上の最新 .bin を既定で読み、概要表示と簡易プロットを行う。

tool_file = mfilename("fullpath");
matlab_root = fileparts(fileparts(tool_file));
addpath(matlab_root, fullfile(matlab_root, "experiment"));
clear tool_file matlab_root;

env = config.EnvironmentConfig.current();
share_dir = string(fileparts(char(env.logger_host_file_path)));
file_glob = "*.bin";
target_file = "";

if strlength(target_file) == 0
  files = dir(fullfile(share_dir, file_glob));
  files = files(~[files.isdir]);
  if isempty(files)
    error("experiment:run_check_logger_bin:noFiles", ...
      "No bin files matched %s under %s.", file_glob, share_dir);
  end

  [~, order] = sort([files.datenum], "descend");
  files = files(order);
  target_file = string(fullfile(files(1).folder, files(1).name));
else
  target_file = string(target_file);
end

out = experiment.read_logger_bin(target_file);

fprintf("Logger file: %s\n", out.file_path);
fprintf("Records: %d  Size: %.1f KB  Duration: %.6f s\n", ...
  out.summary.record_count, out.summary.file_size_bytes / 1024, out.summary.duration_s);
fprintf("Seq: %.0f -> %.0f  t: %.6f -> %.6f s\n", ...
  out.summary.seq_first, out.summary.seq_last, out.summary.t_start_s, out.summary.t_end_s);
fprintf("Load pos range: [%.6f, %.6f] rad  |u|_max: %.6f A\n", ...
  out.summary.load_position_min, out.summary.load_position_max, out.summary.control_input_abs_max);

preview_n = min(8, height(out.table));
if preview_n > 0
  disp(out.table(1:preview_n, :));
else
  fprintf("File is empty.\n");
end

if out.record_count > 0
  t_s = out.raw.t_s - out.raw.t_s(1);

  figure("Name", "ExperimentLogger bin check", "Color", "w");
  tiledlayout(3, 1, "Padding", "compact", "TileSpacing", "compact");

  nexttile;
  plot(t_s, out.raw.ref_value, "-", "LineWidth", 1.0, "DisplayName", "refValue"); hold on;
  plot(t_s, out.raw.load_position, "-", "LineWidth", 1.2, "DisplayName", "loadPosition");
  hold off;
  grid on;
  xlabel("Time [s]");
  ylabel("Position [rad]");
  legend("Location", "best");
  title("Reference vs Load Position");

  nexttile;
  plot(t_s, out.raw.control_input, "-", "LineWidth", 1.2, "DisplayName", "controlInput"); hold on;
  plot(t_s, out.raw.current_cmd, "--", "LineWidth", 1.0, "DisplayName", "currentCmd");
  plot(t_s, out.raw.ff_value, ":", "LineWidth", 1.0, "DisplayName", "ffValue");
  hold off;
  grid on;
  xlabel("Time [s]");
  ylabel("Current [A]");
  legend("Location", "best");
  title("Current-domain Signals");

  nexttile;
  plot(t_s, out.raw.error, "-", "LineWidth", 1.2, "DisplayName", "error"); hold on;
  plot(t_s, out.raw.load_velocity, "-", "LineWidth", 1.0, "DisplayName", "loadVelocity");
  hold off;
  grid on;
  xlabel("Time [s]");
  ylabel("Value");
  legend("Location", "best");
  title("Error and Load Velocity");
end
