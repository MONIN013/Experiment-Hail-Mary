function p = normalize_polynomial(p)
% normalize_polynomial  Drop leading zeros while preserving scalar zero.
p = double(p(:).');
while numel(p) > 1 && p(1) == 0
  p = p(2:end);
end
end
