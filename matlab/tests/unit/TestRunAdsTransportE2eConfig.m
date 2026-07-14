classdef TestRunAdsTransportE2eConfig < matlab.unittest.TestCase
  methods (Test)
    function arrayWritesUseBulkNetConversion(testCase)
      root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
      source = string(fileread(fullfile(root, "+twincat_ads", "AdsTransport.m")));

      testCase.verifyTrue(contains(source, "stream.Write(raw_bytes(:)"));
      testCase.verifyTrue(contains(source, "c.Write(uint32(info.index_group)"));
      testCase.verifyFalse(contains(source, "NET.convertArray("));
      testCase.verifyFalse(contains(source, 'NET.createArray("System.Double", n_double)'));
      testCase.verifyFalse(contains(source, "net_arr(k)"));
    end

    function toolCoversLiveStructArraySliceAndSosWriteApis(testCase)
      root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
      source = string(fileread(fullfile(root, "tools", "run_ads_transport_e2e.m")));

      required = [ ...
        "conn.ctrl.read_struct(idle_map)"
        "conn.seq.read_array(symbols.refTable"
        "conn.seq.read_array_slice("
        "conn.seq.write_array(symbols.refTable"
        "conn.module.write_array(controller_symbols.controllerParams.coefficients"
        "conn.module.write_scalar(controller_symbols.controllerParams.sectionCount"
        "conn.module.write_scalar(controller_symbols.controllerParams.applyRevision"
        "conn.module.read_client().ReadState()"
        '"pass", true'];
      for value = required'
        testCase.verifyTrue(contains(source, value));
      end
      testCase.verifyTrue(contains(source, "mode_state) ~= int16(0)"));
      testCase.verifyTrue(contains(source, "probe_length = max(1, table_len)"));
      testCase.verifyTrue(contains(source, '"probe_length", probe_length'));
    end
  end
end
