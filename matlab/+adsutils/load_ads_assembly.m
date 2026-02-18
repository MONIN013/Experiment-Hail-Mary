function load_ads_assembly(adsAssembly)
if nargin < 1 || strlength(string(adsAssembly)) == 0
    adsAssembly = "TwinCAT.Ads";
end
adsAssembly = char(adsAssembly);

if exist(adsAssembly, "file") == 2
    NET.addAssembly(adsAssembly);
    return;
end

try
    NET.addAssembly(adsAssembly);
catch e
    error("Failed to load ADS assembly '%s'. Provide a valid assembly name or TwinCAT.Ads.dll path via ads_assembly. Details: %s", ...
        adsAssembly, e.message);
end
end