///////////////////////////////////////////////////////////////////////////////
// ControllerAlgorithm.cpp

#include "ControllerAlgorithm.h"

#include <cmath>

namespace controllercore
{
ControllerAlgorithm::ControllerAlgorithm() noexcept
	: m_higs{ false, 1.0, 0.0, 0 }
	, m_activeSectionCount(0)
	, m_appliedRevision(0)
	, m_lastSeenRevision(0)
	, m_parameterErrorCode(ParameterErrorNone)
{
	for (std::size_t i = 0; i < kMaxSections; ++i)
	{
		m_activeCoefficients[i] = { 1.0, 0.0, 0.0, 0.0, 0.0 };
	}
	Reset();
}

void ControllerAlgorithm::Reset() noexcept
{
	m_higsInput = 0.0;
	m_higsState = 0.0;
	m_higsMode = 0;
	for (std::size_t i = 0; i < kMaxSections; ++i)
	{
		m_states[i] = { 0.0, 0.0 };
	}
}

bool ControllerAlgorithm::ApplyParameters(
	const double* coefficients,
	std::uint32_t sectionCount,
	std::uint32_t revision,
	const HigsParameters& higs) noexcept
{
	m_lastSeenRevision = revision;

	if (sectionCount > kMaxSections)
	{
		m_parameterErrorCode = ParameterErrorSectionCount;
		return false;
	}

	if (sectionCount > 0 && coefficients == nullptr)
	{
		m_parameterErrorCode = ParameterErrorNonFiniteCoefficient;
		return false;
	}
	if (higs.enabled && (!IsFinite(higs.gain) || !IsFinite(higs.omegaTs)
		|| higs.gain <= 0.0 || higs.omegaTs <= 0.0 || higs.omegaTs > higs.gain
		|| higs.preSectionCount > sectionCount))
	{
		m_parameterErrorCode = ParameterErrorHigsParameters;
		return false;
	}

	for (std::size_t section = 0; section < sectionCount; ++section)
	{
		const std::size_t base = section * kCoefficientsPerSection;
		for (std::size_t coefficient = 0; coefficient < kCoefficientsPerSection; ++coefficient)
		{
			if (!IsFinite(coefficients[base + coefficient]))
			{
				m_parameterErrorCode = ParameterErrorNonFiniteCoefficient;
				return false;
			}
		}
	}

	for (std::size_t section = 0; section < sectionCount; ++section)
	{
		const std::size_t base = section * kCoefficientsPerSection;
		m_activeCoefficients[section] = {
			coefficients[base + 0],
			coefficients[base + 1],
			coefficients[base + 2],
			coefficients[base + 3],
			coefficients[base + 4],
		};
	}

	for (std::size_t section = sectionCount; section < kMaxSections; ++section)
	{
		m_activeCoefficients[section] = { 1.0, 0.0, 0.0, 0.0, 0.0 };
	}

	m_activeSectionCount = sectionCount;
	m_higs = higs;
	m_appliedRevision = revision;
	m_parameterErrorCode = ParameterErrorNone;
	Reset();
	return true;
}

double ControllerAlgorithm::Step(double refValue, double ffValue, double positionAct) noexcept
{
	if (!IsFinite(refValue) || !IsFinite(ffValue) || !IsFinite(positionAct))
	{
		return 0.0;
	}

	double y = refValue - positionAct;
	if (!IsFinite(y))
	{
		return 0.0;
	}

	for (std::size_t section = 0; section <= m_activeSectionCount; ++section)
	{
		if (m_higs.enabled && section == m_higs.preSectionCount && !TryApplyHigs(y, y))
		{
			return 0.0;
		}
		if (section < m_activeSectionCount
			&& !TryApplyBiquad(y, m_activeCoefficients[section], m_states[section], y))
		{
			return 0.0;
		}
	}

	const double output = y + ffValue;
	return IsFinite(output) ? output : 0.0;
}

std::uint32_t ControllerAlgorithm::AppliedRevision() const noexcept
{
	return m_appliedRevision;
}

std::uint32_t ControllerAlgorithm::ProcessedRevision() const noexcept
{
	return m_lastSeenRevision;
}

std::uint32_t ControllerAlgorithm::LastSeenRevision() const noexcept
{
	return m_lastSeenRevision;
}

std::uint32_t ControllerAlgorithm::ParameterErrorCode() const noexcept
{
	return m_parameterErrorCode;
}

double ControllerAlgorithm::HigsInput() const noexcept { return m_higsInput; }
double ControllerAlgorithm::HigsOutput() const noexcept { return m_higsState; }
std::uint32_t ControllerAlgorithm::HigsMode() const noexcept { return m_higsMode; }

bool ControllerAlgorithm::TryApplyHigs(double input, double& output) noexcept
{
	// Trimodal digital HIGS: book Section 2.4, Eqs. (2.43)-(2.44).
	// Test the candidate first; a sign change alone does not require zeroing.
	const double candidate = m_higsState + m_higs.omegaTs * input;
	const double boundary = m_higs.gain * input;
	if (!IsFinite(candidate) || !IsFinite(boundary))
	{
		m_higsInput = m_higsState = output = 0.0;
		m_higsMode = 0;
		return false;
	}
	const bool inside = input >= 0.0
		? (candidate >= 0.0 && candidate <= boundary)
		: (candidate >= boundary && candidate <= 0.0);
	const bool sameSign = (input >= 0.0 && m_higsInput >= 0.0)
		|| (input <= 0.0 && m_higsInput <= 0.0);
	m_higsMode = inside ? 1u : (sameSign ? 2u : 3u);
	m_higsState = inside ? candidate : (sameSign ? boundary : 0.0);
	m_higsInput = input;
	output = m_higsState;
	return true;
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
	const BiquadCoefficients& coefficients,
	BiquadState& state,
	double& output) noexcept
{
	if (!IsFinite(x))
	{
		output = 0.0;
		return false;
	}

	const double y = coefficients.b0 * x + state.s1;
	const double s1Next = coefficients.b1 * x - coefficients.a1 * y + state.s2;
	const double s2Next = coefficients.b2 * x - coefficients.a2 * y;
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
