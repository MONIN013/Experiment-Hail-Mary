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

	struct HigsParameters
	{
		bool enabled;
		double gain;
		double omegaTs; // omega_h * sample time; both sides use the task sample time.
		std::uint32_t preSectionCount;
	};

	enum ParameterError : std::uint32_t
	{
		ParameterErrorNone = 0,
		ParameterErrorSectionCount = 1,
		ParameterErrorNonFiniteCoefficient = 2,
		ParameterErrorHigsParameters = 3,
	};

	ControllerAlgorithm() noexcept;

	void Reset() noexcept;
	bool ApplyParameters(
		const double* coefficients,
		std::uint32_t sectionCount,
		std::uint32_t revision,
		const HigsParameters& higs = { false, 1.0, 0.0, 0 }) noexcept;
	double Step(double refValue, double ffValue, double positionAct) noexcept;

	std::uint32_t AppliedRevision() const noexcept;
	std::uint32_t ProcessedRevision() const noexcept;
	std::uint32_t LastSeenRevision() const noexcept;
	std::uint32_t ParameterErrorCode() const noexcept;
	double HigsInput() const noexcept;
	double HigsOutput() const noexcept;
	// 0: disabled/reset, 1: integrator, 2: gain, 3: zeroing.
	std::uint32_t HigsMode() const noexcept;
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
	bool TryApplyHigs(double input, double& output) noexcept;
	static bool TryApplyBiquad(
		double x,
		const BiquadCoefficients& coefficients,
		BiquadState& state,
		double& output) noexcept;

	BiquadCoefficients m_activeCoefficients[kMaxSections];
	BiquadState m_states[kMaxSections];
	HigsParameters m_higs;
	double m_higsInput;
	double m_higsState;
	std::uint32_t m_higsMode;
	std::uint32_t m_activeSectionCount;
	std::uint32_t m_appliedRevision;
	std::uint32_t m_lastSeenRevision;
	std::uint32_t m_parameterErrorCode;
};
} // namespace controllercore
