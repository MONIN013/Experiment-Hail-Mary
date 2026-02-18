function values = read_array(client, symbolName, netTypeName, n)
nDouble = double(n);
if nDouble <= 0
    values = zeros(0, 1);
    return;
end

handle = client.CreateVariableHandle(symbolName);
cleanupObj = onCleanup(@()adsutils.safe_delete_handle(client, handle)); %#ok<NASGU>

values = try_read_array_bulk(client, handle, netTypeName, nDouble);
if ~isempty(values)
    return;
end

% Some TwinCAT.Ads builds fail marshalling ULINT arrays.
if strcmp(char(netTypeName), "System.UInt64")
    values = try_read_array_bulk(client, handle, "System.Int64", nDouble);
    if ~isempty(values)
        return;
    end
end

% Final fallback: read each element as scalar symbol (slower but robust).
values = zeros(nDouble, 1);
for k = 1:nDouble
    elemSymbol = sprintf("%s[%d]", symbolName, k - 1);
    values(k) = adsutils.read_scalar(client, elemSymbol, netTypeName);
end
end

function values = try_read_array_bulk(client, handle, netTypeName, nDouble)
values = [];
elemType = adsutils.resolve_net_type(netTypeName);
if isempty(elemType)
    return;
end

arrayType = elemType.MakeArrayType();
dims = NET.createArray("System.Int32", 1);
dims(1) = int32(nDouble);

obj = [];
try
    obj = client.ReadAny(handle, arrayType, dims);
catch
    try
        obj = client.ReadAny(handle, arrayType, int32([nDouble]));
    catch
        try
            obj = client.ReadAny(handle, arrayType, int32(nDouble));
        catch
            return;
        end
    end
end

if isnumeric(obj) || islogical(obj)
    values = double(obj(:));
    return;
end

if isa(obj, "System.Array")
    values = zeros(nDouble, 1);
    for k = 1:nDouble
        values(k) = adsutils.convert_net_object(obj.GetValue(int32(k - 1)));
    end
    return;
end

try
    values = zeros(nDouble, 1);
    for k = 1:nDouble
        values(k) = adsutils.convert_net_object(obj(k));
    end
catch
    values = [];
end
end
