classdef MockDotNetCollection < handle
  properties
    Items = {}
  end

  properties (Dependent)
    Count
  end

  methods
    function obj = MockDotNetCollection(items)
      if nargin < 1 || isempty(items)
        obj.Items = {};
        return;
      end
      obj.Items = items(:)';
    end

    function value = get.Count(obj)
      value = int32(numel(obj.Items));
    end

    function item = Item(obj, index)
      idx = double(index) + 1;
      if idx < 1 || idx > numel(obj.Items) || mod(idx, 1) ~= 0
        error("MockDotNetCollection:IndexOutOfRange", "Invalid index.");
      end
      item = obj.Items{idx};
    end
  end
end
