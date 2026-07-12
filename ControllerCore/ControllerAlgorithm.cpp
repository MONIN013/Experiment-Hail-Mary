///////////////////////////////////////////////////////////////////////////////
// ControllerAlgorithm.cpp

#include "ControllerAlgorithm.h"

#include <cmath>

namespace controllercore
{
ControllerAlgorithm::ControllerAlgorithm() noexcept
{
	Reset();
}

void ControllerAlgorithm::Reset() noexcept
{
	m_pidState = { 0.0, 0.0 };
	m_leadState = { 0.0, 0.0 };
	m_notchState = { 0.0, 0.0 };
	m_resoState = { 0.0, 0.0 };
}

double ControllerAlgorithm::ComputeError(double refValue, double positionAct) noexcept
{
	if (!IsFinite(refValue) || !IsFinite(positionAct))
	{
		return 0.0;
	}

	const double error = refValue - positionAct;
	return IsFinite(error) ? error : 0.0;
}

bool ControllerAlgorithm::IsFinite(double value) noexcept
{
	return std::isfinite(value);
}

bool ControllerAlgorithm::TryApplyBiquad(
	double x,
	double b0,
	double b1,
	double b2,
	double a1,
	double a2,
	BiquadState& state,
	double& output) noexcept
{
	if (!IsFinite(x))
	{
		output = 0.0;
		return false;
	}

	const double y = b0 * x + state.s1;
	const double s1Next = b1 * x - a1 * y + state.s2;
	const double s2Next = b2 * x - a2 * y;
	if (!IsFinite(y) || !IsFinite(s1Next) || !IsFinite(s2Next))
	{
		state = { 0.0, 0.0 };
		output = 0.0;
		return false;
	}

	state.s1 = s1Next;
	state.s2 = s2Next;
	output = y;
	return true;
}
} // namespace controllercore
