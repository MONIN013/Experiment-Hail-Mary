#include "ControllerAlgorithm.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>

namespace
{
constexpr std::size_t kMaxSections = controllercore::ControllerAlgorithm::kMaxSections;
constexpr std::size_t kCoefficientCount = controllercore::ControllerAlgorithm::kCoefficientCount;

void SetSection(
	double* coefficients,
	std::size_t section,
	double b0,
	double b1,
	double b2,
	double a1,
	double a2) noexcept
{
	const std::size_t base = section * controllercore::ControllerAlgorithm::kCoefficientsPerSection;
	coefficients[base + 0] = b0;
	coefficients[base + 1] = b1;
	coefficients[base + 2] = b2;
	coefficients[base + 3] = a1;
	coefficients[base + 4] = a2;
}

void FillIdentity(double* coefficients) noexcept
{
	for (std::size_t section = 0; section < kMaxSections; ++section)
	{
		SetSection(coefficients, section, 1.0, 0.0, 0.0, 0.0, 0.0);
	}
}

class ReferenceController
{
public:
	ReferenceController() noexcept
		: m_sectionCount(0)
	{
		FillIdentity(m_coefficients);
		Reset();
	}

	void Configure(const double* coefficients, std::size_t sectionCount) noexcept
	{
		m_sectionCount = sectionCount;
		for (std::size_t i = 0; i < kCoefficientCount; ++i)
		{
			m_coefficients[i] = coefficients[i];
		}
		Reset();
	}

	void Reset() noexcept
	{
		for (std::size_t section = 0; section < kMaxSections; ++section)
		{
			m_s1[section] = 0.0;
			m_s2[section] = 0.0;
		}
	}

	double Step(double refValue, double ffValue, double positionAct) noexcept
	{
		if (!std::isfinite(refValue) || !std::isfinite(ffValue) || !std::isfinite(positionAct))
		{
			return 0.0;
		}

		double y = refValue - positionAct;
		for (std::size_t section = 0; section < m_sectionCount; ++section)
		{
			const std::size_t base = section * controllercore::ControllerAlgorithm::kCoefficientsPerSection;
			const double x = y;
			y = m_coefficients[base + 0] * x + m_s1[section];
			const double s1Next = m_coefficients[base + 1] * x
				- m_coefficients[base + 3] * y + m_s2[section];
			const double s2Next = m_coefficients[base + 2] * x
				- m_coefficients[base + 4] * y;
			m_s1[section] = s1Next;
			m_s2[section] = s2Next;
		}
		return y + ffValue;
	}

private:
	double m_coefficients[kCoefficientCount];
	double m_s1[kMaxSections];
	double m_s2[kMaxSections];
	std::size_t m_sectionCount;
};

double NextInput(std::uint32_t& state) noexcept
{
	state = state * 1664525u + 1013904223u;
	return (static_cast<double>(state & 0xffffu) - 32768.0) / 32768.0;
}

bool VerifyFiniteCharacterization()
{
	double coefficients[kCoefficientCount];
	FillIdentity(coefficients);
	for (std::size_t section = 0; section < kMaxSections; ++section)
	{
		const double scale = static_cast<double>(section + 1);
		SetSection(coefficients, section,
			0.20 + 0.01 * scale,
			-0.04 + 0.001 * scale,
			0.01,
			-0.30 + 0.005 * scale,
			0.08);
	}

	for (std::uint32_t sectionCount = 0; sectionCount <= kMaxSections; ++sectionCount)
	{
		ReferenceController reference;
		reference.Configure(coefficients, sectionCount);
		controllercore::ControllerAlgorithm actual;
		if (!actual.ApplyParameters(coefficients, sectionCount, sectionCount + 1))
		{
			return false;
		}
		std::uint32_t state = 0x12345678u + sectionCount;

		for (unsigned sample = 0; sample < 1000; ++sample)
		{
			if (sample == 500)
			{
				reference.Reset();
				actual.Reset();
			}
			const double refValue = NextInput(state);
			const double ffValue = 0.25 * NextInput(state);
			const double positionAct = 0.5 * NextInput(state);
			const double expected = reference.Step(refValue, ffValue, positionAct);
			const double observed = actual.Step(refValue, ffValue, positionAct);
			if (expected != observed)
			{
				std::cerr << "finite characterization mismatch: sections="
					<< sectionCount << " sample=" << sample << '\n';
				return false;
			}
		}
	}
	return true;
}

bool VerifyRevisionCommitResetsState()
{
	double coefficients[kCoefficientCount];
	FillIdentity(coefficients);
	SetSection(coefficients, 0, 1.0, 0.5, 0.0, 0.0, 0.0);
	controllercore::ControllerAlgorithm actual;
	if (!actual.ApplyParameters(coefficients, 1, 7)
		|| actual.AppliedRevision() != 7
		|| actual.ProcessedRevision() != 7
		|| actual.LastSeenRevision() != 7
		|| actual.ParameterErrorCode() != controllercore::ControllerAlgorithm::ParameterErrorNone)
	{
		return false;
	}
	if (actual.Step(1.0, 0.0, 0.0) != 1.0
		|| actual.Step(0.0, 0.0, 0.0) != 0.5)
	{
		return false;
	}
	return actual.ApplyParameters(coefficients, 1, 8)
		&& actual.Step(0.0, 0.0, 0.0) == 0.0;
}

bool VerifyRejectedPayloadPreservesActiveController()
{
	double coefficients[kCoefficientCount];
	FillIdentity(coefficients);
	SetSection(coefficients, 0, 2.0, 0.0, 0.0, 0.0, 0.0);
	controllercore::ControllerAlgorithm actual;
	if (!actual.ApplyParameters(coefficients, 1, 1))
	{
		return false;
	}
	if (actual.ApplyParameters(coefficients, 11, 2)
		|| actual.AppliedRevision() != 1
		|| actual.ProcessedRevision() != 2
		|| actual.LastSeenRevision() != 2
		|| actual.ParameterErrorCode() != controllercore::ControllerAlgorithm::ParameterErrorSectionCount
		|| actual.Step(3.0, 0.0, 0.0) != 6.0)
	{
		return false;
	}

	coefficients[0] = std::numeric_limits<double>::quiet_NaN();
	return !actual.ApplyParameters(coefficients, 1, 3)
		&& actual.AppliedRevision() == 1
		&& actual.ProcessedRevision() == 3
		&& actual.LastSeenRevision() == 3
		&& actual.ParameterErrorCode() == controllercore::ControllerAlgorithm::ParameterErrorNonFiniteCoefficient
		&& actual.Step(3.0, 0.0, 0.0) == 6.0;
}

bool VerifyIdentityAndZeroControllers()
{
	double coefficients[kCoefficientCount];
	FillIdentity(coefficients);
	controllercore::ControllerAlgorithm actual;
	if (!actual.ApplyParameters(coefficients, 0, 1)
		|| actual.Step(2.0, 0.25, 0.5) != 1.75)
	{
		return false;
	}
	SetSection(coefficients, 0, 0.0, 0.0, 0.0, 0.0, 0.0);
	return actual.ApplyParameters(coefficients, 1, 2)
		&& actual.Step(2.0, 0.25, 0.5) == 0.25;
}

bool VerifyInvalidInputDoesNotMutateState()
{
	double coefficients[kCoefficientCount];
	FillIdentity(coefficients);
	SetSection(coefficients, 0, 1.0, 0.5, 0.0, 0.0, 0.0);
	controllercore::ControllerAlgorithm actual;
	actual.ApplyParameters(coefficients, 1, 1);
	if (actual.Step(1.0, 0.0, 0.0) != 1.0)
	{
		return false;
	}
	if (actual.Step(std::numeric_limits<double>::quiet_NaN(), 0.0, 0.0) != 0.0)
	{
		return false;
	}
	return actual.Step(0.0, 0.0, 0.0) == 0.5;
}

bool VerifyStateUpdateOverflowResetsAffectedStage()
{
	double coefficients[kCoefficientCount];
	FillIdentity(coefficients);
	const double maximum = std::numeric_limits<double>::max();
	SetSection(coefficients, 0, 1.0, maximum, 0.0, 0.0, 0.0);
	controllercore::ControllerAlgorithm actual;
	actual.ApplyParameters(coefficients, 1, 1);
	if (actual.Step(2.0, 0.25, 0.0) != 0.0)
	{
		return false;
	}
	SetSection(coefficients, 0, 1.0, 0.0, 0.0, 0.0, 0.0);
	actual.ApplyParameters(coefficients, 1, 2);
	return actual.Step(1.0, 0.0, 0.0) == 1.0;
}

bool VerifyFinalOutputOverflowPreservesFiniteState()
{
	double coefficients[kCoefficientCount];
	FillIdentity(coefficients);
	SetSection(coefficients, 0, 1.0, 0.5, 0.0, 0.0, 0.0);
	const double maximum = std::numeric_limits<double>::max();
	controllercore::ControllerAlgorithm actual;
	actual.ApplyParameters(coefficients, 1, 1);
	if (actual.Step(maximum, maximum, 0.0) != 0.0)
	{
		return false;
	}
	return actual.Step(0.0, 0.0, 0.0) == (0.5 * maximum);
}

bool VerifyOverflowFailsSafe()
{
	const double maximum = std::numeric_limits<double>::max();
	controllercore::ControllerAlgorithm actual;
	return actual.Step(maximum, maximum, 0.0) == 0.0
		&& actual.Step(maximum, 1.0, -maximum) == 0.0
		&& controllercore::ControllerAlgorithm::ComputeError(maximum, -maximum) == 0.0
		&& controllercore::ControllerAlgorithm::ComputeError(
			std::numeric_limits<double>::quiet_NaN(), 0.0) == 0.0;
}

bool VerifyHigsModes()
{
	controllercore::ControllerAlgorithm actual;
	if (!actual.ApplyParameters(nullptr, 0, 1, { true, 2.0, 0.5, 0 })) return false;
	// Includes the sector boundary, moving boundary, sign change and zero input.
	const double input[] = { 1, 1, 1, 1, 1, 0.25, -0.25, -0.25, 0 };
	const double output[] = { 0.5, 1, 1.5, 2, 2, 0.5, 0, -0.125, 0 };
	const std::uint32_t mode[] = { 1, 1, 1, 1, 2, 2, 3, 1, 2 };
	for (std::size_t i = 0; i < sizeof(input) / sizeof(input[0]); ++i)
	{
		if (actual.Step(input[i], 0, 0) != output[i]
			|| actual.HigsInput() != input[i] || actual.HigsOutput() != output[i]
			|| actual.HigsMode() != mode[i]) return false;
	}
	actual.ApplyParameters(nullptr, 0, 2, { true, 1.0, 0.5, 0 });
	// A crossing is still integrator mode if its candidate is inside the sector.
	return actual.Step(1, 0, 0) == 0.5
		&& actual.Step(-2, 0, 0) == -0.5 && actual.HigsMode() == 1;
}

bool VerifyHigsSectorAndOddSymmetry()
{
	controllercore::ControllerAlgorithm positive, negative;
	const double gain = 1.75, omegaTs = 0.0625;
	positive.ApplyParameters(nullptr, 0, 1, { true, gain, omegaTs, 0 });
	negative.ApplyParameters(nullptr, 0, 1, { true, gain, omegaTs, 0 });
	double state = 0, previous = 0;
	std::uint32_t random = 23;
	for (unsigned i = 0; i < 20000; ++i)
	{
		const double input = i % 17 == 0 ? 0.0 : NextInput(random);
		const double candidate = state + omegaTs * input;
		// Independent quadratic form of book Eqs. (2.43)-(2.44).
		state = candidate * input >= candidate * candidate / gain ? candidate
			: (input * previous >= 0 ? gain * input : 0);
		previous = input;
		const double y = positive.Step(input, 0, 0);
		if (std::abs(y - state) > 1e-14 || negative.Step(-input, 0, 0) != -y
			|| y * input + 1e-14 < y * y / gain) return false;
	}
	return true;
}

bool VerifyHigsInsertionAndReset()
{
	double coefficients[kCoefficientCount];
	FillIdentity(coefficients);
	SetSection(coefficients, 0, 2, 0, 0, 0, 0);
	SetSection(coefficients, 1, 3, 0, 0, 0, 0);
	const double expectedInput[] = { 1, 2, 6 };
	for (std::uint32_t before = 0; before <= 2; ++before)
	{
		controllercore::ControllerAlgorithm actual;
		actual.ApplyParameters(coefficients, 2, 1, { true, 1, 0.5, before });
		if (actual.Step(1, 7, 0) != 10 || actual.HigsInput() != expectedInput[before]
			|| actual.HigsOutput() != expectedInput[before] * 0.5) return false;
		actual.Reset();
		if (actual.HigsInput() != 0 || actual.HigsOutput() != 0 || actual.HigsMode() != 0
			|| actual.Step(1, 7, 0) != 10) return false;
		actual.ApplyParameters(coefficients, 2, 2, { true, 1, 0.5, before });
		if (actual.HigsOutput() != 0 || actual.Step(1, 7, 0) != 10) return false;
		actual.ApplyParameters(coefficients, 2, 3);
		if (actual.Step(1, 7, 0) != 13 || actual.HigsMode() != 0) return false;
	}
	return true;
}

bool VerifyHigsRejectedParametersAndOverflow()
{
	using Algorithm = controllercore::ControllerAlgorithm;
	Algorithm actual;
	actual.ApplyParameters(nullptr, 0, 1, { true, 1, 0.25, 0 });
	actual.Step(1, 0, 0);
	const double nan = std::numeric_limits<double>::quiet_NaN();
	const Algorithm::HigsParameters invalid[] = {
		{ true, 0, 0.25, 0 }, { true, -1, 0.25, 0 }, { true, nan, 0.25, 0 },
		{ true, 1, 0, 0 }, { true, 1, -0.25, 0 }, { true, 1, nan, 0 },
		{ true, 1, 1.25, 0 }, { true, 1, 0.25, 1 }
	};
	for (std::uint32_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); ++i)
	{
		if (actual.ApplyParameters(nullptr, 0, i + 2, invalid[i])
			|| actual.AppliedRevision() != 1 || actual.ProcessedRevision() != i + 2
			|| actual.ParameterErrorCode() != Algorithm::ParameterErrorHigsParameters
			|| actual.HigsOutput() != 0.25) return false;
	}
	if (actual.Step(nan, 0, 0) != 0 || actual.HigsOutput() != 0.25
		|| actual.Step(1, 0, 0) != 0.5) return false;
	actual.ApplyParameters(nullptr, 0, 20, { true, 2, 0.5, 0 });
	if (actual.Step(std::numeric_limits<double>::max(), 0, 0) != 0
		|| actual.HigsOutput() != 0 || actual.Step(1, 0, 0) != 0.5) return false;
	// Equality in Ts <= gain / omega_h is admissible.
	return actual.ApplyParameters(nullptr, 0, 21, { true, 1, 1, 0 })
		&& actual.Step(1, 0, 0) == 1 && actual.HigsMode() == 1;
}
} // namespace

int main()
{
	if (!VerifyFiniteCharacterization()
		|| !VerifyRevisionCommitResetsState()
		|| !VerifyRejectedPayloadPreservesActiveController()
		|| !VerifyIdentityAndZeroControllers()
		|| !VerifyInvalidInputDoesNotMutateState()
		|| !VerifyStateUpdateOverflowResetsAffectedStage()
		|| !VerifyFinalOutputOverflowPreservesFiniteState()
		|| !VerifyOverflowFailsSafe()
		|| !VerifyHigsModes()
		|| !VerifyHigsSectorAndOddSymmetry()
		|| !VerifyHigsInsertionAndReset()
		|| !VerifyHigsRejectedParametersAndOverflow())
	{
		return 1;
	}

	std::cout << "ControllerAlgorithm SOS and HIGS tests passed\n";
	return 0;
}
