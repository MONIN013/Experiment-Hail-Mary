function values = read_array(client, symbolName, netTypeName, n)
nDouble = double(n);
if nDouble <= 0
    values = zeros(0, 1);
    return;
end

handle = client.CreateVariableHandle(symbolName);
cleanupObj = onCleanup(@()adsutils.safe_delete_handle(client, handle)); %#ok<NASGU>

elemType = adsutils.resolve_net_type(netTypeName);
if isempty(elemType)
    error("Unsupported .NET element type: %s", string(netTypeName));
end

arrayType = elemType.MakeArrayType();
dims = NET.createArray("System.Int32", 1);
dims(1) = int32(nDouble);

obj = client.ReadAny(handle, arrayType, dims);

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

error("Unexpected ADS array read return type for symbol '%s'.", symbolName);
end