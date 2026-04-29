function phase_wrapped_deg = wrap_phase_at_180(phase_deg)
phase_wrapped_deg = mod(phase_deg + 180, 360) - 180;
end
