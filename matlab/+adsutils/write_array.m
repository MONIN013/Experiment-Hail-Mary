function write_array(client, symbolName, values, netTypeName)
% Write a MATLAB numeric vector to a PLC array variable via ADS.
values = double(values(:));
nDouble = numel(values);
if nDouble == 0
    return;
end

handle = client.CreateVariableHandle(symbolName);
cleanupObj = onCleanup(@()adsutils.safe_delete_handle(client, handle)); %#ok<NASGU>

% Build .NET typed array
switch char(netTypeName)
    case "System.Double"
        netArr = NET.createArray("System.Double", nDouble);
        for k = 1:nDouble
            netArr(k) = values(k);
        end
    case "System.Single"
        netArr = NET.createArray("System.Single", nDouble);
        for k = 1:nDouble
            netArr(k) = single(values(k));
        end
    case "System.Int32"
        netArr = NET.createArray("System.Int32", nDouble);
        for k = 1:nDouble
            netArr(k) = int32(values(k));
        end
    case "System.UInt32"
        netArr = NET.createArray("System.UInt32", nDouble);
        for k = 1:nDouble
            netArr(k) = uint32(values(k));
        end
    case "System.Int64"
        netArr = NET.createArray("System.Int64", nDouble);
        for k = 1:nDouble
            netArr(k) = int64(values(k));
        end
    case "System.UInt64"
        netArr = NET.createArray("System.UInt64", nDouble);
        for k = 1:nDouble
            netArr(k) = uint64(values(k));
        end
    otherwise
        error("Unsupported .NET element type for array write: %s", string(netTypeName));
end

client.WriteAny(handle, netArr);
end