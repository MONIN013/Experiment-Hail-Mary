function out = wait_for_settle(module_transport, timeout_s, varargin)
% wait_for_settle  Require a stationary, observable VM state before reset.
%
% ModeManager reset captures DriverAdapter relative-position offsets but does
% not reset VirtualMotor hidden state. Waiting here makes the subsequent
% relative experiment deterministic; raw DINT saturation is rejected because
% the hidden absolute angle can no longer be reconstructed.

arguments
  module_transport twincat_ads.IAdsTransport
  timeout_s (1, 1) double {mustBePositive}
end
arguments (Repeating)
  varargin
end

p = inputParser;
p.addParameter("poll_period_s", 0.02, @is_positive_scalar);
p.addParameter("max_position_delta_counts", 2, @is_nonnegative_integer);
p.parse(varargin{:});
opts = p.Results;

t = twincat_ads.AdsTransport.net_types();
prefix = "VirtualMotorCore_Obj1 (Module1).Outputs.";
symbols = struct( ...
  "motor_position", prefix + "motor.positionActualValue", ...
  "motor_velocity", prefix + "motor.velocityActualValue", ...
  "load_position", prefix + "load.positionActualValue", ...
  "load_velocity", prefix + "load.velocityActualValue");

t0 = tic;
last = read_state();
while true
  saturated = any([last.motor_position, last.load_position] >= double(intmax("int32"))) || ...
    any([last.motor_position, last.load_position] <= double(intmin("int32")));
  if saturated
    error("virtualMotor:settle:positionSaturated", ...
      "VirtualMotor raw position is saturated; restart the TwinCAT System Service before a deterministic experiment.");
  end
  stationary = last.motor_velocity == 0 && last.load_velocity == 0;
  aligned = abs(last.motor_position - last.load_position) <= ...
    double(opts.max_position_delta_counts);
  if stationary && aligned
    out = struct( ...
      "settled", true, "elapsed_s", toc(t0), ...
      "motor_position_count", last.motor_position, ...
      "load_position_count", last.load_position, ...
      "motor_velocity_count", last.motor_velocity, ...
      "load_velocity_count", last.load_velocity);
    return;
  end
  if toc(t0) >= timeout_s
    break;
  end
  pause(min(double(opts.poll_period_s), max(timeout_s - toc(t0), 0)));
  last = read_state();
end

error("virtualMotor:settle:timeout", ...
  "VirtualMotor did not settle within %.3f s (motor/load position=%g/%g, velocity=%g/%g counts).", ...
  timeout_s, last.motor_position, last.load_position, ...
  last.motor_velocity, last.load_velocity);

  function state = read_state()
    state = struct( ...
      "motor_position", double(module_transport.read_scalar(symbols.motor_position, t.i32)), ...
      "motor_velocity", double(module_transport.read_scalar(symbols.motor_velocity, t.i32)), ...
      "load_position", double(module_transport.read_scalar(symbols.load_position, t.i32)), ...
      "load_velocity", double(module_transport.read_scalar(symbols.load_velocity, t.i32)));
  end
end

function tf = is_positive_scalar(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && double(value) > 0;
end

function tf = is_nonnegative_integer(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value)) && ...
  double(value) >= 0 && floor(double(value)) == double(value);
end
