function netValue = to_net_scalar(value, netTypeName)
switch char(netTypeName)
    case "System.Boolean"
        netValue = logical(value);
    case "System.Double"
        netValue = double(value);
    case "System.Single"
        netValue = single(value);
    case "System.UInt16"
        netValue = uint16(value);
    case "System.UInt32"
        netValue = uint32(value);
    case "System.UInt64"
        netValue = uint64(value);
    case "System.Int16"
        netValue = int16(value);
    case "System.Int32"
        netValue = int32(value);
    case "System.Int64"
        netValue = int64(value);
    otherwise
        netValue = value;
end
end
