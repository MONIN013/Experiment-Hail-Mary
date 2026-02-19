classdef SymbolTraversal
  methods (Static)
    function [names, types, sizes] = collectSymbols(symbols, top_level_only, traversal_timeout_ms, traversal_max_nodes)
      names = strings(0, 1);
      types = strings(0, 1);
      sizes = int32(zeros(0, 1));
      if isempty(symbols)
        return;
      end

      if nargin < 2
        top_level_only = true;
      end
      if nargin < 3 || ~isfinite(traversal_timeout_ms) || traversal_timeout_ms <= 0
        traversal_timeout_ms = inf;
      end
      if nargin < 4 || ~isfinite(traversal_max_nodes) || traversal_max_nodes <= 0
        traversal_max_nodes = inf;
      end

      queue = twincat_ads.internal.SymbolTraversal.collectSymbolsFromCollection(symbols);
      if isempty(queue)
        return;
      end

      visited = containers.Map("KeyType", "char", "ValueType", "logical");
      start_tick = tic;
      processed_count = 0;
      while ~isempty(queue)
        if processed_count >= traversal_max_nodes
          break;
        end
        if toc(start_tick) * 1000 > traversal_timeout_ms
          break;
        end

        symbol = queue{1};
        queue(1) = [];
        processed_count = processed_count + 1;
        if isempty(symbol)
          continue;
        end

        key = twincat_ads.internal.SymbolTraversal.symbolIdentityKey(symbol);
        if isKey(visited, key)
          continue;
        end
        visited(key) = true;

        try
          name = twincat_ads.internal.SymbolTraversal.extractName(symbol);
          type = twincat_ads.internal.SymbolTraversal.extractType(symbol);
          size_bytes = twincat_ads.internal.SymbolTraversal.extractSize(symbol);
        catch
          continue;
        end
        if strlength(name) == 0
          continue;
        end
        names(end + 1, 1) = name; %#ok<AGROW>
        types(end + 1, 1) = type; %#ok<AGROW>
        sizes(end + 1, 1) = size_bytes; %#ok<AGROW>

        if logical(top_level_only)
          continue;
        end
        if twincat_ads.internal.SymbolTraversal.isArraySymbol(name, type)
          continue;
        end

        child_collection = twincat_ads.internal.SymbolTraversal.getChildrenCollection(symbol);
        if isempty(child_collection)
          continue;
        end
        children = twincat_ads.internal.SymbolTraversal.collectSymbolsFromCollection(child_collection);
        if isempty(children)
          continue;
        end
        queue = [children; queue]; %#ok<AGROW>
      end

      keep = names ~= "";
      if logical(top_level_only)
        keep = keep & ~contains(names, ".");
      end
      names = names(keep);
      types = types(keep);
      sizes = sizes(keep);

      if ~isempty(names)
        [~, ia] = unique(names, "stable");
        ia = ia(:);
        names = names(ia);
        types = types(ia);
        sizes = sizes(ia);
      end
      names = names(:);
      types = types(:);
      sizes = sizes(:);
    end

    function tf = isArraySymbol(name, type)
      tf = contains(name, "[");
      if tf
        return;
      end
      type_text = upper(strtrim(char(string(type))));
      tf = startsWith(type_text, "ARRAY ");
    end

    function key = symbolIdentityKey(symbol)
      key = "";
      try
        id = System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(symbol);
        key = "dotnet#" + string(int64(id));
      catch
      end
      if strlength(key) > 0
        key = char(key);
        return;
      end

      name = twincat_ads.internal.SymbolTraversal.extractName(symbol);
      if strlength(name) > 0
        key = char("name#" + name);
        return;
      end

      key = char("fallback#" + string(class(symbol)));
    end

    function children = collectSymbolsFromCollection(collection)
      children = cell(0, 1);
      if isempty(collection)
        return;
      end
      try
        n = double(collection.Count);
      catch
        return;
      end
      if n <= 0
        return;
      end
      children = cell(n, 1);
      count = 0;
      for k = 1:n
        try
          symbol = collection.Item(int32(k - 1));
        catch
          continue;
        end
        if isempty(symbol)
          continue;
        end
        count = count + 1;
        children{count, 1} = symbol;
      end
      children = children(1:count);
    end

    function collection = getChildrenCollection(symbol)
      collection = [];
      try
        collection = symbol.SubSymbols;
      catch
      end
      if ~isempty(collection)
        return;
      end
      try
        collection = symbol.Members;
      catch
        collection = [];
      end
    end

    function name = extractName(symbol)
      name = twincat_ads.internal.SymbolTraversal.safeStringValue(symbol, "InstancePath");
      if strlength(name) > 0
        return;
      end
      name = twincat_ads.internal.SymbolTraversal.safeStringValue(symbol, "InstanceName");
      if strlength(name) > 0
        return;
      end
      name = twincat_ads.internal.SymbolTraversal.safeStringValue(symbol, "PathName");
      if strlength(name) > 0
        return;
      end
      name = twincat_ads.internal.SymbolTraversal.safeStringValue(symbol, "Name");
    end

    function type = extractType(symbol)
      type = twincat_ads.internal.SymbolTraversal.safeStringValue(symbol, "TypeName");
      if strlength(type) > 0
        return;
      end
      type = twincat_ads.internal.SymbolTraversal.safeStringValue(symbol, "DataTypeName");
      if strlength(type) > 0
        return;
      end
      try
        data_type = symbol.DataType;
        type = twincat_ads.internal.SymbolTraversal.safeStringValue(data_type, "Name");
      catch
        type = "";
      end
    end

    function size_bytes = extractSize(symbol)
      size_bytes = twincat_ads.internal.SymbolTraversal.safeInt32Value(symbol, "Size");
    end

    function out = safeStringValue(obj, prop_name)
      out = "";
      prop_name = char(string(prop_name));
      try
        v = obj.(prop_name);
      catch
        return;
      end
      if isempty(v)
        out = "";
        return;
      end
      try
        out = string(char(v));
        return;
      catch
      end
      try
        s = string(v);
        if isscalar(s)
          out = s;
        elseif isempty(s)
          out = "";
        else
          out = join(s, " ");
        end
      catch
        out = "";
      end
    end

    function out = safeInt32Value(obj, prop_name)
      out = int32(0);
      prop_name = char(string(prop_name));
      try
        v = obj.(prop_name);
        if isempty(v)
          return;
        end
        out = int32(v);
      catch
        out = int32(0);
      end
    end
  end
end
