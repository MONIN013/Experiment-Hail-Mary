function out = read_logger_bin(file_path)
% read_logger_bin  ExperimentLogger の固定長バイナリログを読み出す。
%
%   out = experiment.read_logger_bin(file_path)
%
%   入力:
%     file_path - LogRecord(96 bytes) が連結された .bin ファイル
%
%   戻り値 out (struct):
%     .file_path     - 読み込んだファイルパス
%     .record_count  - レコード数
%     .summary       - 要約情報
%     .table         - 各レコードを table 化したもの
%     .raw           - 各列をベクトルで保持した struct

  arguments
    file_path {mustBeTextScalar}
  end

  file_path = string(file_path);
  if ~isfile(file_path)
    error("experiment:read_logger_bin:fileNotFound", ...
      "Logger bin file not found: %s", file_path);
  end

  info = dir(char(file_path));
  record_size = 96;
  if mod(info.bytes, record_size) ~= 0
    error("experiment:read_logger_bin:invalidSize", ...
      "Logger bin size must be a multiple of %d bytes, got %d bytes.", ...
      record_size, info.bytes);
  end

  [fid, msg] = fopen(char(file_path), "rb", "ieee-le");
  if fid < 0
    error("experiment:read_logger_bin:openFailed", ...
      "Failed to open logger bin file: %s", string(msg));
  end
  cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

  raw_bytes = fread(fid, [record_size, inf], "*uint8");
  record_count = size(raw_bytes, 2);
  raw = decode_records(raw_bytes);

  out = struct();
  out.file_path = char(file_path);
  out.record_count = record_count;
  out.summary = make_summary(raw, record_count, info.bytes);
  out.table = table( ...
    raw.seq, ...
    raw.t_ns, ...
    raw.t_s, ...
    raw.motor_position, ...
    raw.motor_velocity, ...
    raw.motor_current_act, ...
    raw.load_position, ...
    raw.load_velocity, ...
    raw.current_cmd, ...
    raw.error, ...
    raw.ref_value, ...
    raw.ff_value, ...
    raw.control_input, ...
    'VariableNames', { ...
      'seq', 't_ns', 't_s', ...
      'motor_position', 'motor_velocity', 'motor_current_act', ...
      'load_position', 'load_velocity', 'current_cmd', ...
      'error', 'ref_value', 'ff_value', 'control_input'});
  out.raw = raw;
end

function raw = decode_records(raw_bytes)
  raw = struct();
  raw.seq = decode_uint32(raw_bytes, 1, 4);
  raw.reserved_pad0 = decode_uint32(raw_bytes, 5, 8);
  raw.t_ns = decode_uint64(raw_bytes, 9, 16);
  raw.motor_position = decode_double(raw_bytes, 17, 24);
  raw.motor_velocity = decode_double(raw_bytes, 25, 32);
  raw.motor_current_act = decode_double(raw_bytes, 33, 40);
  raw.load_position = decode_double(raw_bytes, 41, 48);
  raw.load_velocity = decode_double(raw_bytes, 49, 56);
  raw.current_cmd = decode_double(raw_bytes, 57, 64);
  raw.error = decode_double(raw_bytes, 65, 72);
  raw.ref_value = decode_double(raw_bytes, 73, 80);
  raw.ff_value = decode_double(raw_bytes, 81, 88);
  raw.control_input = decode_double(raw_bytes, 89, 96);
  raw.t_s = double(raw.t_ns) * 1e-9;
end

function summary = make_summary(raw, record_count, file_size_bytes)
  summary = struct( ...
    "file_size_bytes", double(file_size_bytes), ...
    "record_count", double(record_count), ...
    "seq_first", NaN, ...
    "seq_last", NaN, ...
    "t_start_s", NaN, ...
    "t_end_s", NaN, ...
    "duration_s", 0, ...
    "control_input_abs_max", NaN, ...
    "load_position_min", NaN, ...
    "load_position_max", NaN);

  if record_count == 0
    return;
  end

  summary.seq_first = double(raw.seq(1));
  summary.seq_last = double(raw.seq(end));
  summary.t_start_s = raw.t_s(1);
  summary.t_end_s = raw.t_s(end);
  summary.duration_s = max(0, raw.t_s(end) - raw.t_s(1));
  summary.control_input_abs_max = max(abs(raw.control_input));
  summary.load_position_min = min(raw.load_position);
  summary.load_position_max = max(raw.load_position);
end

function out = decode_uint32(raw_bytes, start_idx, end_idx)
  out = reshape(typecast(reshape(raw_bytes(start_idx:end_idx, :), 1, []), "uint32"), [], 1);
end

function out = decode_uint64(raw_bytes, start_idx, end_idx)
  out = reshape(typecast(reshape(raw_bytes(start_idx:end_idx, :), 1, []), "uint64"), [], 1);
end

function out = decode_double(raw_bytes, start_idx, end_idx)
  out = reshape(typecast(reshape(raw_bytes(start_idx:end_idx, :), 1, []), "double"), [], 1);
end
