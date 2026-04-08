///////////////////////////////////////////////////////////////////////////////
// TcUnits.cpp

#include "TcUnits.h"

#include "TcNumeric.h"

namespace
{
const double kTwoPi = 6.28318530717958647692;
}

namespace tccommon
{
namespace units
{
double NormalizeSign(int sign) noexcept
{
    return (sign < 0) ? -1.0 : 1.0;
}

bool HasValidPositionScale(const AxisScaling& params) noexcept
{
    return params.encoderResolution > 0U;
}

bool HasValidCurrentScale(const AxisScaling& params) noexcept
{
    return tccommon::numeric::IsFinite(params.ratedCurrentA) && (params.ratedCurrentA > 0.0);
}

double ConvertPositionCountsToRad(std::int32_t rawValue, const AxisScaling& params) noexcept
{
    if (!HasValidPositionScale(params))
    {
        return 0.0;
    }

    return NormalizeSign(params.positionSign)
        * static_cast<double>(rawValue)
        * (kTwoPi / static_cast<double>(params.encoderResolution));
}

double ConvertVelocityCountsToRad(std::int32_t rawValue, const AxisScaling& params) noexcept
{
    if (!HasValidPositionScale(params))
    {
        return 0.0;
    }

    return NormalizeSign(params.velocitySign)
        * static_cast<double>(rawValue)
        * (kTwoPi / static_cast<double>(params.encoderResolution));
}

double ConvertPermilleToCurrentA(std::int16_t rawValue, const AxisScaling& params) noexcept
{
    if (!HasValidCurrentScale(params))
    {
        return 0.0;
    }

    return NormalizeSign(params.currentSign)
        * static_cast<double>(rawValue)
        * (params.ratedCurrentA / 1000.0);
}

double ConvertCurrentAToPermille(double currentA, const AxisScaling& params) noexcept
{
    if (!HasValidCurrentScale(params) || !tccommon::numeric::IsFinite(currentA))
    {
        return 0.0;
    }

    return currentA
        * NormalizeSign(params.currentSign)
        * (1000.0 / params.ratedCurrentA);
}

double ComputeRelativePosition(double positionAbs, const AxisScaling& params, double offsetRad) noexcept
{
    if (!HasValidPositionScale(params))
    {
        return 0.0;
    }

    return params.enableRelativePosition ? (positionAbs - offsetRad) : positionAbs;
}
} // namespace units
} // namespace tccommon
