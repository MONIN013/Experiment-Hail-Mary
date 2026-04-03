///////////////////////////////////////////////////////////////////////////////
// TcUnits.h

#pragma once

#include <cstdint>

namespace tccommon
{
namespace units
{
struct AxisScaling
{
    std::uint32_t encoderResolution;
    double ratedCurrentA;
    int positionSign;
    int velocitySign;
    int currentSign;
    bool enableRelativePosition;
};

double NormalizeSign(int sign) noexcept;
bool HasValidPositionScale(const AxisScaling& params) noexcept;
bool HasValidCurrentScale(const AxisScaling& params) noexcept;
double ConvertPositionCountsToRad(std::int32_t rawValue, const AxisScaling& params) noexcept;
double ConvertVelocityCountsToRad(std::int32_t rawValue, const AxisScaling& params) noexcept;
double ConvertPermilleToCurrentA(std::int16_t rawValue, const AxisScaling& params) noexcept;
double ConvertCurrentAToPermille(double currentA, const AxisScaling& params) noexcept;
double ComputeRelativePosition(double positionAbs, const AxisScaling& params, double offsetRad) noexcept;
} // namespace units
} // namespace tccommon
