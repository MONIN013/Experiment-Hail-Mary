function result = default_entry_executor(entry, expected, context)
% default_entry_executor  Execute and verify one registry entry in MATLAB.
result = testoracle.launch_child_entry(entry, expected, context);
end
