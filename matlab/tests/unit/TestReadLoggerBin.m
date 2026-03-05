classdef TestReadLoggerBin < matlab.unittest.TestCase
  methods (Test)
    function decodesFixedSizeRecords(testCase)
      file_path = [tempname, '.bin'];
      cleaner = onCleanup(@() delete_if_exists(file_path)); %#ok<NASGU>
      write_sample_file(file_path);

      out = experiment.read_logger_bin(file_path);

      testCase.verifyEqual(out.record_count, 2);
      testCase.verifyEqual(out.summary.file_size_bytes, 192);
      testCase.verifyEqual(out.raw.seq, uint32([1; 2]));
      testCase.verifyEqual(out.raw.reserved_pad0, uint32([0; 0]));
      testCase.verifyEqual(out.raw.t_ns, uint64([1000; 2000]));
      testCase.verifyEqual(out.raw.load_position, [0.4; 1.4]);
      testCase.verifyEqual(out.raw.ff_value, [0.9; 1.9]);
      testCase.verifyEqual(out.raw.control_input, [1.0; 2.0]);
      testCase.verifyEqual(out.summary.duration_s, 1e-6, "AbsTol", 1e-12);
      testCase.verifyEqual(out.table.seq, uint32([1; 2]));
    end

    function rejectsNonAlignedFileSize(testCase)
      file_path = [tempname, '.bin'];
      cleaner = onCleanup(@() delete_if_exists(file_path)); %#ok<NASGU>

      [fid, msg] = fopen(char(file_path), "wb");
      testCase.assertGreaterThanOrEqual(fid, 0, msg);
      fwrite(fid, uint8(1:95), "uint8");
      fclose(fid);

      testCase.verifyError(@() experiment.read_logger_bin(file_path), ...
        "experiment:read_logger_bin:invalidSize");
    end
  end
end

function write_sample_file(file_path)
  [fid, msg] = fopen(char(file_path), "wb", "ieee-le");
  assert(fid >= 0, msg);
  cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

  rows = [ ...
    1, 1000, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0; ...
    2, 2000, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0];

  for k = 1:size(rows, 1)
    fwrite(fid, uint32(rows(k, 1)), "uint32");
    fwrite(fid, uint32(0), "uint32");
    fwrite(fid, uint64(rows(k, 2)), "uint64");
    fwrite(fid, rows(k, 3:end), "double");
  end
end

function delete_if_exists(file_path)
  if isfile(file_path)
    delete(file_path);
  end
end
