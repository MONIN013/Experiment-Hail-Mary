function checkpoint_ledger(ledger, file_path)
% checkpoint_ledger  Atomically save partial execution history.
file_path = string(file_path);
parent = string(fileparts(file_path));
if strlength(parent) > 0 && ~isfolder(parent), mkdir(parent); end
temporary = file_path + "." + string(char(java.util.UUID.randomUUID())) + ".tmp";
cleanup = onCleanup(@() delete_if_exists(temporary));
save(char(temporary), "ledger", "-v7.3");
if ~movefile(temporary, file_path, "f")
  error("testoracle:ledger:checkpointFailed", ...
    "Could not publish ledger checkpoint %s.", file_path);
end
end

function delete_if_exists(path_value)
if isfile(path_value), delete(path_value); end
end
