classdef TestConnectionManager < matlab.unittest.TestCase
  methods (Test)
    function createBuildsSessionBoundTransports(testCase)
      conn = experiment.ConnectionManager.create( ...
        "ref_profile", [1; 2], ...
        "transport_factory", @factory);
      testCase.verifyTrue(isa(conn.seq, "twincat_ads.IAdsTransport"));
      testCase.verifyTrue(conn.seq.connected);
      testCase.verifyTrue(conn.ctrl.connected);
      testCase.verifyTrue(conn.module.connected);
      conn.session.close();
    end

    function createPlcOnlyOmitsModule(testCase)
      conn = experiment.ConnectionManager.create_plc_only( ...
        "ref_profile", [1; 2], ...
        "transport_factory", @factory);
      testCase.verifyFalse(isfield(conn, "module"));
      conn.session.close();
    end
  end
end

function transport_obj = factory(varargin)
transport_obj = MockAdsTransport();
unused(varargin);
end

function unused(varargin)
end
