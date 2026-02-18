function typeObj = resolve_net_type(netTypeName)
typeObj = System.Type.GetType(netTypeName);
if ~isempty(typeObj)
    return;
end

switch char(netTypeName)
    case "System.Boolean"
        typeObj = System.Boolean(false).GetType();
    case "System.Double"
        typeObj = System.Double(0).GetType();
    case "System.Single"
        typeObj = System.Single(0).GetType();
    case "System.UInt16"
        typeObj = System.UInt16(0).GetType();
    case "System.UInt32"
        typeObj = System.UInt32(0).GetType();
    case "System.UInt64"
        typeObj = System.UInt64(0).GetType();
    case "System.Int16"
        typeObj = System.Int16(0).GetType();
    case "System.Int32"
        typeObj = System.Int32(0).GetType();
    case "System.Int64"
        typeObj = System.Int64(0).GetType();
    otherwise
        typeObj = [];
end
end
