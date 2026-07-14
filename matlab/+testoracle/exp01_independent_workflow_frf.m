function out = exp01_independent_workflow_frf(independent, scenario, options)
% exp01_independent_workflow_frf  Apply the real exp01 estimator to lsim data.
arguments
  independent (1, 1) struct
  scenario (1, 1) struct
  options.frequency_band_hz (1, 2) double = [1, 500]
end
required = ["load_position", "inputs"];
if ~isstruct(independent) || ~isscalar(independent) || ...
    any(~isfield(independent, required)) || ...
    ~isfield(independent.inputs, "ff_profile")
  error("testoracle:exp01:invalidIndependentResponse", ...
    "Independent load position and feedforward input are required.");
end
Ts = double(scenario.Ts);
sample_count = double(scenario.expected_sample_count);
position = double(independent.load_position(:));
feedforward = double(independent.inputs.ff_profile(:));
if numel(position) ~= sample_count || numel(feedforward) ~= sample_count
  error("testoracle:exp01:independentLengthMismatch", ...
    "Independent exp01 response does not match the scenario length.");
end

% The logger ffValue is one sample after the sequencer FF table. The plant
% response is four further samples behind this estimator input, while
% independent_lsim retains the full five-sample table contract.
ff_value = [0; feedforward(1:end-1)];
window_samples = round(double(scenario.Tcycle)/Ts);
start_index = round(double(scenario.transient_cycles)* ...
  double(scenario.Tcycle)/Ts) + 1;
analysis_input = ff_value(start_index:end);
velocity = [position(1)/Ts; diff(position)/Ts];
velocity_segment = velocity(start_index:end);
window = rectwin(window_samples);
fs = 1/Ts;
[velocity_response, frequency_hz] = tfestimate( ...
  analysis_input, velocity_segment, window, 0, window_samples, fs);
band = frequency_hz >= options.frequency_band_hz(1) & ...
  frequency_hz <= options.frequency_band_hz(2);
frequency_hz = frequency_hz(band);
velocity_response = velocity_response(band);
z_inverse = exp(-1i*2*pi*frequency_hz*Ts);
position_response = velocity_response .* Ts ./ (1-z_inverse);
out = struct( ...
  "frequency_hz", frequency_hz(:), ...
  "velocity_response", velocity_response, ...
  "position_response", position_response, ...
  "sample_delay_from_ff_value", 4);
end
