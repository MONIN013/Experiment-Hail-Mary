function sos = tustin_sos(system, sample_time_s)
% Discretize one continuous design factor with the shared, unwarped Tustin rule.
if ~(isa(system,"tf") && isscalar(system) && isfinite(sample_time_s) && sample_time_s>0)
  error("experiment:controller:invalidDesignFactor","A real SISO transfer function and positive sample period are required.");
end
sampled = c2d(system,sample_time_s,"tustin");
[b,a] = tfdata(sampled,"v");
[sos,gain] = tf2sos(b,a);
sos(1,1:3) = sos(1,1:3)*gain;
sos(:,4) = 1;
end
