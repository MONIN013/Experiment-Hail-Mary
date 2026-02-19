classdef MockDotNetSymbol < handle
  properties
    InstancePath = []
    InstanceName = []
    PathName = []
    Name = []
    TypeName = []
    DataTypeName = []
    DataType = struct("Name", "")
    Size = int32(0)
    SubSymbols = []
    Members = []
  end

  methods
    function obj = MockDotNetSymbol(varargin)
      if mod(nargin, 2) ~= 0
        error("MockDotNetSymbol:InvalidArgs", "Name/value pairs are required.");
      end
      for k = 1:2:nargin
        key = varargin{k};
        value = varargin{k + 1};
        if ~ischar(key) && ~isstring(key)
          error("MockDotNetSymbol:InvalidKey", "Property name must be text.");
        end
        obj.(char(string(key))) = value;
      end
    end
  end
end
