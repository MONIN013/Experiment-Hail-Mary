///////////////////////////////////////////////////////////////////////////////
// TcNumeric.h

#pragma once

#include <cstdint>

namespace tccommon
{
namespace numeric
{
bool IsFinite(double value) noexcept;
double ClampSymmetric(double value, double limit) noexcept;
double ApplyOptionalSymmetricLimit(double value, double limit) noexcept;
double NonNegativeOrZero(double value) noexcept;
std::int16_t SaturatingRoundToInt16(double value) noexcept;
std::int32_t SaturatingRoundToInt32(double value) noexcept;
} // namespace numeric
} // namespace tccommon
