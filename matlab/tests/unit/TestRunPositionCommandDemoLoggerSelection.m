classdef TestRunPositionCommandDemoLoggerSelection < matlab.unittest.TestCase
  methods (Test)
    function picksLatestBinFile(testCase)
      temp_dir = tempname;
      mkdir(temp_dir);
      cleaner = onCleanup(@() cleanup_dir(temp_dir)); %#ok<NASGU>

      older_path = fullfile(temp_dir, "older.bin");
      latest_path = fullfile(temp_dir, "latest.bin");
      write_sample_file(older_path, 1);
      pause(0.02);
      write_sample_file(latest_path, 2);

      out = experiment.read_latest_logger_bin(temp_dir, "*.bin");

      testCase.verifyTrue(out.ok);
      testCase.verifyEqual(string(out.file_path), string(latest_path));
      testCase.verifyEqual(out.logger_bin.record_count, 2);
      testCase.verifyThat(string(out.reason), matlab.unittest.constraints.ContainsSubstring("latest valid .bin loaded"));
    end

    function failsWhenNoBinFiles(testCase)
      temp_dir = tempname;
      mkdir(temp_dir);
      cleaner = onCleanup(@() cleanup_dir(temp_dir)); %#ok<NASGU>

      out = experiment.read_latest_logger_bin(temp_dir, "*.bin");

      testCase.verifyFalse(out.ok);
      testCase.verifyEmpty(out.logger_bin);
      testCase.verifyThat(string(out.reason), matlab.unittest.constraints.ContainsSubstring("no .bin files"));
    end

    function picksNewestValidBinWhenLatestHasZeroRecords(testCase)
      temp_dir = tempname;
      mkdir(temp_dir);
      cleaner = onCleanup(@() cleanup_dir(temp_dir)); %#ok<NASGU>

      valid_path = fullfile(temp_dir, "valid.bin");
      latest_empty_path = fullfile(temp_dir, "latest_empty.bin");
      write_sample_file(valid_path, 1);
      pause(0.02);
      touch_empty_file(latest_empty_path);

      out = experiment.read_latest_logger_bin(temp_dir, "*.bin");

      testCase.verifyTrue(out.ok);
      testCase.verifyEqual(string(out.file_path), string(valid_path));
      testCase.verifyEqual(out.logger_bin.record_count, 1);
      testCase.verifyThat(string(out.reason), matlab.unittest.constraints.ContainsSubstring("latest valid .bin loaded"));
    end

    function failsWhenAllBinFilesAreUnusable(testCase)
      temp_dir = tempname;
      mkdir(temp_dir);
      cleaner = onCleanup(@() cleanup_dir(temp_dir)); %#ok<NASGU>

      malformed_path = fullfile(temp_dir, "older_malformed.bin");
      latest_empty_path = fullfile(temp_dir, "latest_empty.bin");
      write_malformed_file(malformed_path);
      pause(0.02);
      touch_empty_file(latest_empty_path);

      out = experiment.read_latest_logger_bin(temp_dir, "*.bin");

      testCase.verifyFalse(out.ok);
      testCase.verifyEmpty(out.logger_bin);
      testCase.verifyEqual(string(out.file_path), string(latest_empty_path));
      testCase.verifyThat(string(out.reason), matlab.unittest.constraints.ContainsSubstring("no usable .bin found"));
      testCase.verifyThat(string(out.reason), matlab.unittest.constraints.ContainsSubstring("zero records"));
      testCase.verifyThat(string(out.reason), matlab.unittest.constraints.ContainsSubstring("read failed"));
    end
  end
end

function write_sample_file(file_path, n_records)
[fid, msg] = fopen(char(file_path), "wb", "ieee-le");
assert(fid >= 0, msg);
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

for k = 1:n_records
  fwrite(fid, uint32(k), "uint32");
  fwrite(fid, uint32(0), "uint32");
  fwrite(fid, uint64(1000 * k), "uint64");
  fwrite(fid, [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0], "double");
end
end

function touch_empty_file(file_path)
[fid, msg] = fopen(char(file_path), "wb");
assert(fid >= 0, msg);
fclose(fid);
end

function write_malformed_file(file_path)
[fid, msg] = fopen(char(file_path), "wb");
assert(fid >= 0, msg);
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, uint8([1 2 3 4 5]), "uint8");
end

function cleanup_dir(path)
if isfolder(path)
  rmdir(path, "s");
end
end
