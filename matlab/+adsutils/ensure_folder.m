function ensure_folder(folderPath)
if isempty(folderPath)
    return;
end
if ~exist(folderPath, "dir")
    mkdir(folderPath);
end
end
