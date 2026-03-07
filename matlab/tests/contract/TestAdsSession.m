classdef TestAdsSession < matlab.unittest.TestCase
  methods (Test)
    function cachesTransportPerPort(testCase)
      session = twincat_ads.AdsSession("1.2.3.4.5.6", ...
        "transport_factory", @factory);
      t1 = session.transport(851);
      t2 = session.transport(851);
      t3 = session.transport(852);
      testCase.verifyTrue(t1 == t2);
      testCase.verifyFalse(t1 == t3);
      session.close();
      testCase.verifyFalse(t1.connected);
      testCase.verifyFalse(t3.connected);
    end

    function rejectsMissingAmsNetId(testCase)
      testCase.verifyError(@() twincat_ads.AdsSession(""), ...
        "twincat_ads:session:invalidConfig");
    end
  end
end

function transport_obj = factory(varargin)
transport_obj = MockAdsTransport();
unused(varargin);
end

function unused(varargin)
end
