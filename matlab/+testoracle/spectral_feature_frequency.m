function frequency_hz = spectral_feature_frequency(frequency, response, band)
%SPECTRAL_FEATURE_FREQUENCY Locate the strongest finite response in a band.
frequency = double(frequency(:));
response = double(response(:));
band = double(band(:).');
if numel(frequency) ~= numel(response) || numel(band) ~= 2 || ...
    any(~isfinite(frequency)) || any(~isfinite(band)) || ...
    band(1) > band(2)
  error("testoracle:feature:invalidInput", ...
    "Frequency, response, and the ordered two-value band must align.");
end
finite_response = isfinite(real(response)) & isfinite(imag(response));
mask = frequency >= band(1) & frequency <= band(2) & finite_response;
if ~any(mask)
  frequency_hz = NaN;
  return;
end
indices = find(mask);
[~, local] = max(abs(response(mask)));
frequency_hz = frequency(indices(local));
end
