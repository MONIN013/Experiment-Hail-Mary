///////////////////////////////////////////////////////////////////////////////
// ControllerAlgorithm.h

#pragma once

#include <cstddef>
#include <cstdint>

namespace controllercore
{
class ControllerAlgorithm final
{
public:
	static constexpr std::size_t kMaxSections = 10;
	static constexpr std::size_t kCoefficientsPerSection = 5;
	static constexpr std::size_t kCoefficientCount = kMaxSections * kCoefficientsPerSection;

	enum ParameterError : std::uint32_t
	{
		ParameterErrorNone = 0,
		ParameterErrorSectionCount = 1,
		ParameterErrorNonFiniteCoefficient = 2,
	};

	ControllerAlgorithm() noexcept;

	void Reset() noexcept;
	bool ApplyParameters(
		const double* coefficients,
		std::uint32_t sectionCount,
		std::uint32_t revision) noexcept;
	double Step(double refValue, double ffValue, double positionAct) noexcept;

	std::uint32_t AppliedRevision() const noexcept;
	std::uint32_t ProcessedRevision() const noexcept;
	std::uint32_t LastSeenRevision() const noexcept;
	std::uint32_t ParameterErrorCode() const noexcept;
	static double ComputeError(double refValue, double positionAct) noexcept;

private:
	struct BiquadCoefficients
	{
		double b0;
		double b1;
		double b2;
		double a1;
		double a2;
	};

	struct BiquadState
	{
		double s1;
		double s2;
	};

	static bool IsFinite(double value) noexcept;
	static bool TryApplyBiquad(
		double x,
		const BiquadCoefficients& coefficients,
		BiquadState& state,
		double& output) noexcept;

	BiquadCoefficients m_activeCoefficients[kMaxSections];
	BiquadState m_states[kMaxSections];
	std::uint32_t m_activeSectionCount;
	std::uint32_t m_appliedRevision;
	std::uint32_t m_lastSeenRevision;
	std::uint32_t m_parameterErrorCode;
};
} // namespace controllercore
