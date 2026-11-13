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
		double omegaTs;
	};

	struct SectionCounts
	{
		std::uint32_t lpPre;
		std::uint32_t lpPost;
		std::uint32_t p;
		std::uint32_t iPre;
		std::uint32_t iPost;
		std::uint32_t post;
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
		const SectionCounts& sections,
		const HigsParameters& lp,
		const HigsParameters& i) noexcept;
	double Step(double refValue, double ffValue, double positionAct) noexcept;

	std::uint32_t AppliedRevision() const noexcept;
	std::uint32_t ProcessedRevision() const noexcept;
	std::uint32_t LastSeenRevision() const noexcept;
	std::uint32_t ParameterErrorCode() const noexcept;
	double HigsLpInput() const noexcept;
	double HigsLpOutput() const noexcept;
	std::uint32_t HigsLpMode() const noexcept;
	double HigsIInput() const noexcept;
	double HigsIOutput() const noexcept;
	std::uint32_t HigsIMode() const noexcept;
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

	struct HigsState
	{
		double input;
		double output;
		std::uint32_t mode;
	};

	static bool IsFinite(double value) noexcept;
	static bool IsValidHigs(const HigsParameters& parameters) noexcept;
	bool TryApplyHigs(double input, double& output, const HigsParameters& parameters, HigsState& state) noexcept;
	bool TryApplyRows(
		double input,
		std::uint32_t first,
		std::uint32_t count,
		double& output) noexcept;
	bool TryApplyBiquad(
		double x,
		const BiquadCoefficients& coefficients,
		BiquadState& state,
		double& output) noexcept;

	BiquadCoefficients m_activeCoefficients[kMaxSections];
	BiquadState m_states[kMaxSections];
	SectionCounts m_sections;
	HigsParameters m_lpParameters;
	HigsParameters m_iParameters;
	HigsState m_lpState;
	HigsState m_iState;
	std::uint32_t m_appliedRevision;
	std::uint32_t m_lastSeenRevision;
	std::uint32_t m_parameterErrorCode;
};
} // namespace controllercore
