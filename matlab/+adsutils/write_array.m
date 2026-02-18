function write_array(client, symbolName, values, netTypeName)
% Write a MATLAB numeric vector to a PLC array variable via ADS.
%
% Inputs:
%   client       – connected AdsClient / TcAdsClient
%   symbolName   – fully qualified PLC symbol, e.g. "GVL_VM_LOG.log_x"
%   values       – numeric column or row vector
%   netTypeName  – .NET element type, e.g. "System.Double"

values = double(values(:));
nDouble = numel(values);
if nDouble == 0
    return;
end

handle = client.CreateVariableHandle(symbolName);
cleanupObj = onCleanup(@()adsutils.safe_delete_handle(client, handle)); %#ok<NASGU>

ok = try_write_array_bulk(client, handle, values, netTypeName, nDouble);
if ok
    return;
end

% Fallback: element-wise write (slow but robust).
for k = 1:nDouble
    elemSymbol = sprintf("%s[%d]", symbolName, k - 1);
    adsutils.write_scalar(client, elemSymbol, values(k), netTypeName);
end
end

function ok = try_write_array_bulk(client, handle, values, netTypeName, nDouble)
ok = false;

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
        return;
end

try
    client.WriteAny(handle, netArr);
    ok = true;
catch
    % WriteAny with .NET array failed; caller will use element-wise fallback.
end
end
