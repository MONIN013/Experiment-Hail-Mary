///////////////////////////////////////////////////////////////////////////////
// TcNumeric.cpp

#include "TcNumeric.h"

#include <cmath>
#include <limits>

namespace tccommon
{
namespace numeric
{
bool IsFinite(double value) noexcept
{
    return std::isfinite(value);
}

double ClampSymmetric(double value, double limit) noexcept
{
    if (!IsFinite(value))
    {
        return 0.0;
    }

    const double absLimit = std::fabs(limit);
    if (!IsFinite(absLimit) || absLimit <= 0.0)
    {
        return 0.0;
    }

    if (value > absLimit)
    {
        return absLimit;
    }
    if (value < -absLimit)
    {
        return -absLimit;
    }
    return value;
}

double ApplyOptionalSymmetricLimit(double value, double limit) noexcept
{
    if (!IsFinite(value))
    {
        return 0.0;
    }

    const double absLimit = std::fabs(limit);
    if (!IsFinite(absLimit) || absLimit <= 0.0)
    {
        return value;
    }

    if (value > absLimit)
    {
        return absLimit;
    }
    if (value < -absLimit)
    {
        return -absLimit;
    }
    return value;
}

double NonNegativeOrZero(double value) noexcept
{
    return (IsFinite(value) && value > 0.0) ? value : 0.0;
}

std::int16_t SaturatingRoundToInt16(double value) noexcept
{
    if (!IsFinite(value))
    {
        return 0;
    }

    const double rounded = (value >= 0.0) ? std::floor(value + 0.5) : std::ceil(value - 0.5);
    if (rounded > static_cast<double>(std::numeric_limits<std::int16_t>::max()))
    {
        return std::numeric_limits<std::int16_t>::max();
    }
    if (rounded < static_cast<double>(std::numeric_limits<std::int16_t>::min()))
    {
        return std::numeric_limits<std::int16_t>::min();
    }
    return static_cast<std::int16_t>(rounded);
}

std::int32_t SaturatingRoundToInt32(double value) noexcept
{
    if (!IsFinite(value))
    {
        return 0;
    }

    const double rounded = (value >= 0.0) ? std::floor(value + 0.5) : std::ceil(value - 0.5);
    if (rounded > static_cast<double>(std::numeric_limits<std::int32_t>::max()))
    {
        return std::numeric_limits<std::int32_t>::max();
    }
    if (rounded < static_cast<double>(std::numeric_limits<std::int32_t>::min()))
    {
        return std::numeric_limits<std::int32_t>::min();
    }
    return static_cast<std::int32_t>(rounded);
}
} // namespace numeric
} // namespace tccommon
