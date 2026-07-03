function out = read_latest_logger_bin(share_dir, file_glob)
% read_latest_logger_bin  共有フォルダ上の最新 logger bin を読み出す。
%
%   out = experiment.io.read_latest_logger_bin(share_dir, file_glob)
%
%   戻り値 out (struct):
%     .ok          - 有効な logger bin が取得できたか
%     .logger_bin  - experiment.read_logger_bin の戻り値（失敗時は []）
%     .file_path   - 選択/診断対象パス（失敗時は最新候補）
%     .reason      - 失敗/成功理由の診断文字列

  arguments
    share_dir {mustBeTextScalar}
    file_glob {mustBeTextScalar} = "*.bin"
  end

  share_dir = string(share_dir);
  file_glob = string(file_glob);
  out = struct( ...
    "ok", false, ...
    "logger_bin", [], ...
    "file_path", "", ...
    "reason", "");

  files = dir(fullfile(char(share_dir), char(file_glob)));
  files = files(~[files.isdir]);
  if isempty(files)
    out.reason = sprintf("no .bin files found under %s", share_dir);
    return;
  end

  [~, order] = sort([files.datenum], "descend");
  files = files(order);
  newest_file = files(1);
  newest_path = string(fullfile(newest_file.folder, newest_file.name));
  out.file_path = newest_path;

  diagnostics = strings(0, 1);
  for idx = 1:numel(files)
    candidate = files(idx);
    target_file = string(fullfile(candidate.folder, candidate.name));

    if double(candidate.bytes) == 0
      diagnostics(end + 1, 1) = sprintf("%s: zero records", target_file); %#ok<AGROW>
      continue;
    end

    try
      logger_bin = experiment.read_logger_bin(target_file);
    catch e
      diagnostics(end + 1, 1) = sprintf("%s: read failed (%s)", ... %#ok<AGROW>
        target_file, string(e.identifier));
      continue;
    end

    if ~isfield(logger_bin, "record_count") || double(logger_bin.record_count) <= 0
      diagnostics(end + 1, 1) = sprintf("%s: zero records", target_file); %#ok<AGROW>
      continue;
    end

    out.ok = true;
    out.logger_bin = logger_bin;
    out.file_path = target_file;
    out.reason = sprintf("latest valid .bin loaded [%s]", target_file);
    return;
  end

  summary = "no usable .bin found";
  if ~isempty(diagnostics)
    summary = sprintf("%s (newest=%s; tried=%s)", ...
      summary, newest_path, strjoin(diagnostics, "; "));
  end
  out.reason = summary;
end
