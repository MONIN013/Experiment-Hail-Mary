///////////////////////////////////////////////////////////////////////////////
// ControllerAlgorithm.cpp

#include "ControllerAlgorithm.h"

#include <cmath>

namespace controllercore
{
ControllerAlgorithm::ControllerAlgorithm() noexcept
	: m_sections{ 0, 0, 0, 1, 0, 0 }
	, m_lpParameters{ false, 1.0, 0.0 }
	, m_iParameters{ false, 1.0, 0.0 }
	, m_lpState{ 0.0, 0.0, 0 }
	, m_iState{ 0.0, 0.0, 0 }
	, m_appliedRevision(0)
	, m_lastSeenRevision(0)
	, m_parameterErrorCode(ParameterErrorNone)
{
	for (std::size_t section = 0; section < kMaxSections; ++section)
	{
		m_activeCoefficients[section] = { 1.0, 0.0, 0.0, 0.0, 0.0 };
	}
	// A fresh instance is an identity P controller with zero I contribution.
	m_activeCoefficients[1] = { 0.0, 0.0, 0.0, 0.0, 0.0 };
	m_activeCoefficients[2] = { 1.0, 0.0, 0.0, 0.0, 0.0 };
	Reset();
}

void ControllerAlgorithm::Reset() noexcept
{
	m_lpState = { 0.0, 0.0, 0 };
	m_iState = { 0.0, 0.0, 0 };
	for (std::size_t section = 0; section < kMaxSections; ++section)
	{
		m_states[section] = { 0.0, 0.0 };
	}
}

bool ControllerAlgorithm::ApplyParameters(
	const double* coefficients,
	std::uint32_t sectionCount,
	std::uint32_t revision,
	const SectionCounts& sections,
	const HigsParameters& lp,
	const HigsParameters& i) noexcept
{
	m_lastSeenRevision = revision;
	const std::uint64_t ordinaryCount = static_cast<std::uint64_t>(sections.lpPre)
		+ sections.lpPost + sections.p + sections.iPre + sections.iPost + sections.post;
	const std::uint64_t requiredCount = ordinaryCount + 2u;
	if (requiredCount > kMaxSections || sectionCount != requiredCount)
	{
		m_parameterErrorCode = ParameterErrorSectionCount;
		return false;
	}
	if (coefficients == nullptr)
	{
		m_parameterErrorCode = ParameterErrorNonFiniteCoefficient;
		return false;
	}
	if (!IsValidHigs(lp) || !IsValidHigs(i))
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
			coefficients[base], coefficients[base + 1], coefficients[base + 2],
			coefficients[base + 3], coefficients[base + 4],
		};
	}
	for (std::size_t section = sectionCount; section < kMaxSections; ++section)
	{
		m_activeCoefficients[section] = { 1.0, 0.0, 0.0, 0.0, 0.0 };
	}

	m_sections = sections;
	m_lpParameters = lp;
	m_iParameters = i;
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

	double x = refValue - positionAct;
	if (!IsFinite(x))
	{
		return 0.0;
	}

	std::uint32_t offset = 0;
	if (!TryApplyRows(x, offset, m_sections.lpPre, x)) return 0.0;
	offset += m_sections.lpPre;
	const std::uint32_t lpHSection = offset++;
	if (m_lpParameters.enabled)
	{
		if (!TryApplyHigs(x, x, m_lpParameters, m_lpState)) return 0.0;
	}
	else
	{
		m_lpState.input = x;
		if (!TryApplyRows(x, lpHSection, 1, x))
		{
			m_lpState.output = x;
			m_lpState.mode = 0;
			return 0.0;
		}
		m_lpState.output = x;
		m_lpState.mode = 0;
	}
	if (!TryApplyRows(x, offset, m_sections.lpPost, x)) return 0.0;
	offset += m_sections.lpPost;

	double pOutput = x;
	if (!TryApplyRows(x, offset, m_sections.p, pOutput)) return 0.0;
	offset += m_sections.p;

	double iOutput = x;
	if (!TryApplyRows(x, offset, m_sections.iPre, iOutput)) return 0.0;
	offset += m_sections.iPre;
	const std::uint32_t iHSection = offset++;
	if (m_iParameters.enabled)
	{
		if (!TryApplyHigs(iOutput, iOutput, m_iParameters, m_iState)) return 0.0;
	}
	else
	{
		m_iState.input = iOutput;
		if (!TryApplyRows(iOutput, iHSection, 1, iOutput))
		{
			m_iState.output = iOutput;
			m_iState.mode = 0;
			return 0.0;
		}
		m_iState.output = iOutput;
		m_iState.mode = 0;
	}
	if (!TryApplyRows(iOutput, offset, m_sections.iPost, iOutput)) return 0.0;
	offset += m_sections.iPost;

	double y = pOutput + iOutput;
	if (!IsFinite(y) || !TryApplyRows(y, offset, m_sections.post, y)) return 0.0;
	const double output = y + ffValue;
	return IsFinite(output) ? output : 0.0;
}

std::uint32_t ControllerAlgorithm::AppliedRevision() const noexcept { return m_appliedRevision; }
std::uint32_t ControllerAlgorithm::ProcessedRevision() const noexcept { return m_lastSeenRevision; }
std::uint32_t ControllerAlgorithm::LastSeenRevision() const noexcept { return m_lastSeenRevision; }
std::uint32_t ControllerAlgorithm::ParameterErrorCode() const noexcept { return m_parameterErrorCode; }
double ControllerAlgorithm::HigsLpInput() const noexcept { return m_lpState.input; }
double ControllerAlgorithm::HigsLpOutput() const noexcept { return m_lpState.output; }
std::uint32_t ControllerAlgorithm::HigsLpMode() const noexcept { return m_lpState.mode; }
double ControllerAlgorithm::HigsIInput() const noexcept { return m_iState.input; }
double ControllerAlgorithm::HigsIOutput() const noexcept { return m_iState.output; }
std::uint32_t ControllerAlgorithm::HigsIMode() const noexcept { return m_iState.mode; }

bool ControllerAlgorithm::TryApplyHigs(
	double input,
	double& output,
	const HigsParameters& parameters,
	HigsState& state) noexcept
{
	// Trimodal digital HIGS: book Section 2.4, Eqs. (2.43)-(2.44).
	// Test the candidate first; a sign change alone does not require zeroing.
	const double candidate = state.output + parameters.omegaTs * input;
	const double boundary = parameters.gain * input;
	if (!IsFinite(candidate) || !IsFinite(boundary))
	{
		state = { 0.0, 0.0, 0 };
		output = 0.0;
		return false;
	}
	const bool inside = input >= 0.0
		? (candidate >= 0.0 && candidate <= boundary)
		: (candidate >= boundary && candidate <= 0.0);
	const bool sameSign = (input >= 0.0 && state.input >= 0.0)
		|| (input <= 0.0 && state.input <= 0.0);
	state.mode = inside ? 1u : (sameSign ? 2u : 3u);
	state.output = inside ? candidate : (sameSign ? boundary : 0.0);
	state.input = input;
	output = state.output;
	return true;
}

bool ControllerAlgorithm::TryApplyRows(
	double input,
	std::uint32_t first,
	std::uint32_t count,
	double& output) noexcept
{
	double value = input;
	for (std::uint32_t n = 0; n < count; ++n)
	{
		const std::uint32_t section = first + n;
		if (!TryApplyBiquad(value, m_activeCoefficients[section], m_states[section], value))
		{
			output = 0.0;
			return false;
		}
	}
	output = value;
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

bool ControllerAlgorithm::IsValidHigs(const HigsParameters& parameters) noexcept
{
	if (!IsFinite(parameters.gain) || !IsFinite(parameters.omegaTs)
		|| parameters.gain <= 0.0 || parameters.omegaTs < 0.0)
	{
		return false;
	}
	return !parameters.enabled
		|| (parameters.omegaTs > 0.0 && parameters.omegaTs <= parameters.gain);
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
