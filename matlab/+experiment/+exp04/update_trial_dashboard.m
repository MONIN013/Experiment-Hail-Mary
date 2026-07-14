function dashboard = update_trial_dashboard( ...
    dashboard, t, reference, actual, error_signal, feedforward_input, ...
    feedback_input, trial_index, trial_count, varargin)
% update_trial_dashboard  Create or refresh the three-panel ILC trial view.

p = inputParser;
p.addParameter("total_input", [], @is_finite_real_vector);
p.addParameter("visible", "auto", @is_valid_visibility);
p.parse(varargin{:});

[t, reference, actual, error_signal, feedforward_input, feedback_input] = ...
  validate_trial_vectors(t, reference, actual, error_signal, ...
    feedforward_input, feedback_input);
validate_trial_index(trial_index, trial_count);

total_input = p.Results.total_input;
if isempty(total_input)
  total_input = feedforward_input + feedback_input;
else
  total_input = double(total_input(:));
  if numel(total_input) ~= numel(t)
    error("experiment:exp04:dashboardLengthMismatch", ...
      "total_input must have the same length as the trial signals.");
  end
end

visibility = resolve_visibility(p.Results.visible);
if ~is_valid_dashboard(dashboard)
  dashboard = create_dashboard(visibility);
else
  set(dashboard.figure, "Visible", visibility);
end

set(dashboard.lines.reference, "XData", t, "YData", reference);
set(dashboard.lines.actual, "XData", t, "YData", actual);
set(dashboard.lines.error, "XData", t, "YData", error_signal);
set(dashboard.lines.feedforward, "XData", t, "YData", feedforward_input);
set(dashboard.lines.feedback, "XData", t, "YData", feedback_input);

for ax = dashboard.axes
  axis(ax, "tight");
end

error_norm = norm(error_signal);
max_feedforward = max(abs(feedforward_input));
max_total_input = max(abs(total_input));
summary_text = sprintf( ...
  "Trial %d/%d | ||e||_2 = %.6g | max|FF| = %.6g A | max|u| = %.6g A", ...
  trial_index, trial_count, error_norm, max_feedforward, max_total_input);
set(dashboard.title, "String", summary_text);
set(dashboard.figure, "Name", "ILC Trial Dashboard - " + string(trial_index) + ...
  "/" + string(trial_count));

dashboard.trial = double(trial_index);
dashboard.trialCount = double(trial_count);
dashboard.metrics = struct( ...
  "errorNorm", double(error_norm), ...
  "maxAbsFeedforwardA", double(max_feedforward), ...
  "maxAbsTotalInputA", double(max_total_input));

if visibility == "on"
  drawnow limitrate;
end
end

function dashboard = create_dashboard(visibility)
fig = figure( ...
  "Name", "ILC Trial Dashboard", ...
  "NumberTitle", "off", ...
  "Color", "w", ...
  "Visible", visibility, ...
  "Tag", "experiment.exp04.trialDashboard");
layout = tiledlayout(fig, 3, 1, ...
  "Padding", "compact", "TileSpacing", "compact");

tracking_axes = nexttile(layout);
reference_line = plot(tracking_axes, NaN, NaN, ...
  "Color", [0.20 0.35 0.75], "LineWidth", 1.0, ...
  "DisplayName", "Reference");
hold(tracking_axes, "on");
actual_line = plot(tracking_axes, NaN, NaN, ...
  "Color", [0.85 0.30 0.15], "LineWidth", 1.1, ...
  "DisplayName", "Actual");
hold(tracking_axes, "off");
grid(tracking_axes, "on");
xlabel(tracking_axes, "Time [s]");
ylabel(tracking_axes, "Position [rad]");
title(tracking_axes, "Reference vs. Actual");
legend(tracking_axes, "Location", "best");

error_axes = nexttile(layout);
error_line = plot(error_axes, NaN, NaN, ...
  "Color", [0.80 0.20 0.20], "LineWidth", 1.1);
grid(error_axes, "on");
xlabel(error_axes, "Time [s]");
ylabel(error_axes, "Error [rad]");
title(error_axes, "Tracking Error");

input_axes = nexttile(layout);
feedforward_line = plot(input_axes, NaN, NaN, ...
  "Color", [0.20 0.60 0.25], "LineWidth", 1.1, ...
  "DisplayName", "Feedforward");
hold(input_axes, "on");
feedback_line = plot(input_axes, NaN, NaN, ...
  "Color", [0.55 0.25 0.75], "LineWidth", 1.0, ...
  "DisplayName", "Feedback");
hold(input_axes, "off");
grid(input_axes, "on");
xlabel(input_axes, "Time [s]");
ylabel(input_axes, "Current [A]");
title(input_axes, "Feedforward vs. Feedback Input");
legend(input_axes, "Location", "best");

summary_title = title(layout, "ILC Trial Dashboard", "Interpreter", "none");

dashboard = struct( ...
  "figure", fig, ...
  "layout", layout, ...
  "axes", [tracking_axes, error_axes, input_axes], ...
  "title", summary_title, ...
  "lines", struct( ...
    "reference", reference_line, ...
    "actual", actual_line, ...
    "error", error_line, ...
    "feedforward", feedforward_line, ...
    "feedback", feedback_line), ...
  "trial", 0, ...
  "trialCount", 0, ...
  "metrics", struct());
end

function tf = is_valid_dashboard(dashboard)
tf = isstruct(dashboard) && isscalar(dashboard) && ...
  all(isfield(dashboard, ["figure", "layout", "axes", "title", "lines"])) && ...
  isgraphics(dashboard.figure, "figure") && ...
  numel(dashboard.axes) == 3 && all(isgraphics(dashboard.axes, "axes")) && ...
  isgraphics(dashboard.title) && isstruct(dashboard.lines) && ...
  all(isfield(dashboard.lines, ...
    ["reference", "actual", "error", "feedforward", "feedback"]));
if tf
  line_handles = struct2array(dashboard.lines);
  tf = numel(line_handles) == 5 && all(isgraphics(line_handles, "line"));
end
end

function [t, reference, actual, error_signal, feedforward_input, feedback_input] = ...
    validate_trial_vectors(t, reference, actual, error_signal, ...
      feedforward_input, feedback_input)
values = {t, reference, actual, error_signal, feedforward_input, feedback_input};
for index = 1:numel(values)
  if ~is_finite_real_vector(values{index}) || isempty(values{index})
    error("experiment:exp04:invalidDashboardSignal", ...
      "Trial dashboard signals must be nonempty finite real vectors.");
  end
  values{index} = double(values{index}(:));
end
counts = cellfun(@numel, values);
if any(counts ~= counts(1))
  error("experiment:exp04:dashboardLengthMismatch", ...
    "All trial dashboard signals must have the same length.");
end
[t, reference, actual, error_signal, feedforward_input, feedback_input] = ...
  values{:};
end

function validate_trial_index(trial_index, trial_count)
valid_index = isnumeric(trial_index) && isreal(trial_index) && ...
  isscalar(trial_index) && isfinite(trial_index) && ...
  trial_index >= 1 && fix(trial_index) == trial_index;
valid_count = isnumeric(trial_count) && isreal(trial_count) && ...
  isscalar(trial_count) && isfinite(trial_count) && ...
  trial_count >= 1 && fix(trial_count) == trial_count;
if ~valid_index || ~valid_count || trial_index > trial_count
  error("experiment:exp04:invalidDashboardTrial", ...
    "trial_index and trial_count must be positive integers with trial_index <= trial_count.");
end
end

function tf = is_finite_real_vector(value)
tf = isnumeric(value) && isreal(value) && isvector(value) && ...
  all(isfinite(double(value(:))));
end

function tf = is_valid_visibility(value)
tf = (isstring(value) && isscalar(value)) || ...
  (ischar(value) && isrow(value)) || ...
  (islogical(value) && isscalar(value));
if tf && ~islogical(value)
  tf = ismember(lower(string(value)), ["auto", "on", "off"]);
end
end

function visibility = resolve_visibility(value)
if islogical(value)
  if value
    visibility = "on";
  else
    visibility = "off";
  end
  return;
end

visibility = lower(string(value));
if visibility == "auto"
  if usejava("desktop")
    visibility = "on";
  else
    visibility = "off";
  end
end
end
