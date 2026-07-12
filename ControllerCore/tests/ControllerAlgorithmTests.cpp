#include "ControllerAlgorithm.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>

namespace
{
struct EnableParams
{
	bool enablePid;
	bool enableLead;
	bool enableNotch;
	bool enableReso;
};

struct PidParams
{
	double pidB0;
	double pidB1;
	double pidB2;
	double pidA1;
	double pidA2;
};

struct LeadParams
{
	double leadB0;
	double leadB1;
	double leadB2;
	double leadA1;
	double leadA2;
};

struct NotchParams
{
	double notchB0;
	double notchB1;
	double notchB2;
	double notchA1;
	double notchA2;
};

struct ResoParams
{
	double resoB0;
	double resoB1;
	double resoB2;
	double resoA1;
	double resoA2;
};

class ReferenceController
{
public:
	ReferenceController() noexcept
	{
		Reset();
	}

	void Reset() noexcept
	{
		m_pidS1 = 0.0;
		m_pidS2 = 0.0;
		m_leadS1 = 0.0;
		m_leadS2 = 0.0;
		m_notchS1 = 0.0;
		m_notchS2 = 0.0;
		m_resoS1 = 0.0;
		m_resoS2 = 0.0;
	}

	double Step(
		double refValue,
		double ffValue,
		double positionAct,
		const EnableParams& enable,
		const PidParams& pid,
		const LeadParams& lead,
		const NotchParams& notch,
		const ResoParams& reso) noexcept
	{
		if (!std::isfinite(refValue) || !std::isfinite(ffValue) || !std::isfinite(positionAct))
		{
			return 0.0;
		}

		double y = refValue - positionAct;
		if (enable.enablePid)
		{
			y = ApplyBiquad(y, pid.pidB0, pid.pidB1, pid.pidB2, pid.pidA1, pid.pidA2, m_pidS1, m_pidS2);
		}
		if (enable.enableLead)
		{
			y = ApplyBiquad(y, lead.leadB0, lead.leadB1, lead.leadB2, lead.leadA1, lead.leadA2, m_leadS1, m_leadS2);
		}
		if (enable.enableNotch)
		{
			y = ApplyBiquad(y, notch.notchB0, notch.notchB1, notch.notchB2, notch.notchA1, notch.notchA2, m_notchS1, m_notchS2);
		}
		if (enable.enableReso)
		{
			y = ApplyBiquad(y, reso.resoB0, reso.resoB1, reso.resoB2, reso.resoA1, reso.resoA2, m_resoS1, m_resoS2);
		}
		return y + ffValue;
	}

private:
	static double ApplyBiquad(
		double x,
		double b0,
		double b1,
		double b2,
		double a1,
		double a2,
		double& s1,
		double& s2) noexcept
	{
		if (!std::isfinite(x))
		{
			return 0.0;
		}
		const double y = b0 * x + s1;
		const double s1Next = b1 * x - a1 * y + s2;
		const double s2Next = b2 * x - a2 * y;
		s1 = s1Next;
		s2 = s2Next;
		if (!std::isfinite(y))
		{
			return 0.0;
		}
		return y;
	}

	double m_pidS1;
	double m_pidS2;
	double m_leadS1;
	double m_leadS2;
	double m_notchS1;
	double m_notchS2;
	double m_resoS1;
	double m_resoS2;
};

const PidParams kPid = { 0.31, -0.08, 0.02, -0.37, 0.11 };
const LeadParams kLead = { 0.42, -0.17, 0.04, -0.29, 0.07 };
const NotchParams kNotch = { 0.73, -0.51, 0.19, -0.22, 0.05 };
const ResoParams kReso = { 0.27, 0.09, -0.03, -0.18, 0.04 };

double NextInput(std::uint32_t& state) noexcept
{
	state = state * 1664525u + 1013904223u;
	return (static_cast<double>(state & 0xffffu) - 32768.0) / 32768.0;
}

bool VerifyFiniteCharacterization()
{
	for (unsigned mask = 0; mask < 16; ++mask)
	{
		const EnableParams enable = {
			(mask & 1u) != 0,
			(mask & 2u) != 0,
			(mask & 4u) != 0,
			(mask & 8u) != 0
		};
		ReferenceController reference;
		controllercore::ControllerAlgorithm actual;
		std::uint32_t state = 0x12345678u + mask;

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
			const double expected = reference.Step(refValue, ffValue, positionAct, enable, kPid, kLead, kNotch, kReso);
			const double observed = actual.Step(refValue, ffValue, positionAct, enable, kPid, kLead, kNotch, kReso);
			if (expected != observed)
			{
				std::cerr << "finite characterization mismatch: mask=" << mask << " sample=" << sample << '\n';
				return false;
			}
		}
	}
	return true;
}

bool VerifyInvalidInputDoesNotMutateState()
{
	const EnableParams pidOnly = { true, false, false, false };
	const PidParams statefulPid = { 1.0, 0.5, 0.0, 0.0, 0.0 };
	controllercore::ControllerAlgorithm actual;
	if (actual.Step(1.0, 0.0, 0.0, pidOnly, statefulPid, kLead, kNotch, kReso) != 1.0)
	{
		return false;
	}
	if (actual.Step(std::numeric_limits<double>::quiet_NaN(), 0.0, 0.0, pidOnly, statefulPid, kLead, kNotch, kReso) != 0.0)
	{
		return false;
	}
	return actual.Step(0.0, 0.0, 0.0, pidOnly, statefulPid, kLead, kNotch, kReso) == 0.5;
}

bool VerifyInvalidCoefficientsResetAffectedStage()
{
	const EnableParams pidOnly = { true, false, false, false };
	const double infinity = std::numeric_limits<double>::infinity();
	const PidParams invalidPid = { infinity, 0.0, 0.0, 0.0, 0.0 };
	const PidParams identityPid = { 1.0, 0.0, 0.0, 0.0, 0.0 };
	controllercore::ControllerAlgorithm actual;
	if (actual.Step(1.0, 0.25, 0.0, pidOnly, invalidPid, kLead, kNotch, kReso) != 0.0)
	{
		return false;
	}
	return actual.Step(1.0, 0.0, 0.0, pidOnly, identityPid, kLead, kNotch, kReso) == 1.0;
}

bool VerifyStateUpdateOverflowResetsAffectedStage()
{
	const EnableParams pidOnly = { true, false, false, false };
	const double maximum = std::numeric_limits<double>::max();
	const PidParams stateOverflowPid = { 1.0, maximum, 0.0, 0.0, 0.0 };
	const PidParams identityPid = { 1.0, 0.0, 0.0, 0.0, 0.0 };
	controllercore::ControllerAlgorithm actual;
	if (actual.Step(2.0, 0.25, 0.0, pidOnly, stateOverflowPid, kLead, kNotch, kReso) != 0.0)
	{
		return false;
	}
	return actual.Step(1.0, 0.0, 0.0, pidOnly, identityPid, kLead, kNotch, kReso) == 1.0;
}

bool VerifyFinalOutputOverflowPreservesFiniteState()
{
	const EnableParams pidOnly = { true, false, false, false };
	const double maximum = std::numeric_limits<double>::max();
	const PidParams statefulPid = { 1.0, 0.5, 0.0, 0.0, 0.0 };
	controllercore::ControllerAlgorithm actual;
	if (actual.Step(maximum, maximum, 0.0, pidOnly, statefulPid, kLead, kNotch, kReso) != 0.0)
	{
		return false;
	}
	return actual.Step(0.0, 0.0, 0.0, pidOnly, statefulPid, kLead, kNotch, kReso) == (0.5 * maximum);
}

bool VerifyOverflowFailsSafe()
{
	const EnableParams disabled = { false, false, false, false };
	const double maximum = std::numeric_limits<double>::max();
	controllercore::ControllerAlgorithm actual;
	return actual.Step(maximum, maximum, 0.0, disabled, kPid, kLead, kNotch, kReso) == 0.0
		&& actual.Step(maximum, 1.0, -maximum, disabled, kPid, kLead, kNotch, kReso) == 0.0
		&& controllercore::ControllerAlgorithm::ComputeError(maximum, -maximum) == 0.0
		&& controllercore::ControllerAlgorithm::ComputeError(
			std::numeric_limits<double>::quiet_NaN(), 0.0) == 0.0;
}
} // namespace

int main()
{
	if (!VerifyFiniteCharacterization()
		|| !VerifyInvalidInputDoesNotMutateState()
		|| !VerifyInvalidCoefficientsResetAffectedStage()
		|| !VerifyStateUpdateOverflowResetsAffectedStage()
		|| !VerifyFinalOutputOverflowPreservesFiniteState()
		|| !VerifyOverflowFailsSafe())
	{
		return 1;
	}

	std::cout << "ControllerAlgorithm tests passed\n";
	return 0;
}
