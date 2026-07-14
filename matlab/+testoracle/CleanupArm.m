classdef CleanupArm < handle
  % CleanupArm  Mutable onCleanup guard for explicit-success disarming.
  properties
    Armed (1, 1) logical = true
  end
end
