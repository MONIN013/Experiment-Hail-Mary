#include "TcNumeric.h"
#include "TcUnits.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>

namespace
{
bool Near(double lhs, double rhs, double tolerance = 1.0e-12)
{
    return std::fabs(lhs - rhs) <= tolerance;
}

bool TestNumericSafety()
{
    using namespace tccommon::numeric;
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double inf = std::numeric_limits<double>::infinity();
    return !IsFinite(nan)
        && !IsFinite(inf)
        && IsFinite(-1.0)
        && ClampSymmetric(nan, 2.0) == 0.0
        && ClampSymmetric(1.0, nan) == 0.0
        && ClampSymmetric(3.0, 2.0) == 2.0
        && ClampSymmetric(-3.0, -2.0) == -2.0
        && ApplyOptionalSymmetricLimit(3.0, 0.0) == 3.0
        && ApplyOptionalSymmetricLimit(inf, 2.0) == 0.0
        && NonNegativeOrZero(2.0) == 2.0
        && NonNegativeOrZero(-1.0) == 0.0
        && NonNegativeOrZero(nan) == 0.0;
}

bool TestRoundingAndSaturation()
{
    using namespace tccommon::numeric;
    return SaturatingRoundToInt16(0.5) == 1
        && SaturatingRoundToInt16(-0.5) == -1
        && SaturatingRoundToInt16(32767.6) == std::numeric_limits<std::int16_t>::max()
        && SaturatingRoundToInt16(-32768.6) == std::numeric_limits<std::int16_t>::min()
        && SaturatingRoundToInt16(std::numeric_limits<double>::quiet_NaN()) == 0
        && SaturatingRoundToInt32(1.5) == 2
        && SaturatingRoundToInt32(-1.5) == -2
        && SaturatingRoundToInt32(1.0e20) == std::numeric_limits<std::int32_t>::max()
        && SaturatingRoundToInt32(-1.0e20) == std::numeric_limits<std::int32_t>::min();
}

bool TestUnits()
{
    using namespace tccommon::units;
    AxisScaling params = { 8388608U, 1.6, -1, 1, -1, true };
    const double pi = 3.14159265358979323846;
    const double position = ConvertPositionCountsToRad(4194304, params);
    const double velocity = ConvertVelocityCountsToRad(4194304, params);
    const double current = ConvertPermilleToCurrentA(500, params);
    const double permille = ConvertCurrentAToPermille(-0.8, params);
    if (!Near(position, -pi) || !Near(velocity, pi) || !Near(current, -0.8) || !Near(permille, 500.0))
    {
        return false;
    }
    if (!Near(ComputeRelativePosition(3.0, params, 1.25), 1.75))
    {
        return false;
    }
    params.enableRelativePosition = false;
    if (!Near(ComputeRelativePosition(3.0, params, 1.25), 3.0))
    {
        return false;
    }
    params.encoderResolution = 0U;
    params.ratedCurrentA = std::numeric_limits<double>::quiet_NaN();
    return !HasValidPositionScale(params)
        && !HasValidCurrentScale(params)
        && ConvertPositionCountsToRad(1, params) == 0.0
        && ConvertVelocityCountsToRad(1, params) == 0.0
        && ConvertPermilleToCurrentA(1000, params) == 0.0
        && ConvertCurrentAToPermille(1.0, params) == 0.0
        && ComputeRelativePosition(3.0, params, 1.0) == 0.0
        && NormalizeSign(0) == 1.0
        && NormalizeSign(-1) == -1.0;
}
}

int main()
{
    if (!TestNumericSafety())
    {
        std::cerr << "numeric safety test failed\n";
        return 1;
    }
    if (!TestRoundingAndSaturation())
    {
        std::cerr << "rounding and saturation test failed\n";
        return 1;
    }
    if (!TestUnits())
    {
        std::cerr << "unit conversion test failed\n";
        return 1;
    }
    std::cout << "CommonLib tests passed\n";
    return 0;
}
