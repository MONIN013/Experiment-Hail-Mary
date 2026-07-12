///////////////////////////////////////////////////////////////////////////////
// ControllerAlgorithm.h

#pragma once

namespace controllercore
{
class ControllerAlgorithm final
{
public:
	ControllerAlgorithm() noexcept;

	void Reset() noexcept;
	static double ComputeError(double refValue, double positionAct) noexcept;

	template <typename TEnable, typename TPid, typename TLead, typename TNotch, typename TReso>
	double Step(
		double refValue,
		double ffValue,
		double positionAct,
		const TEnable& enable,
		const TPid& pid,
		const TLead& lead,
		const TNotch& notch,
		const TReso& reso) noexcept
	{
		if (!IsFinite(refValue) || !IsFinite(ffValue) || !IsFinite(positionAct))
		{
			return 0.0;
		}

		const double error = refValue - positionAct;
		if (!IsFinite(error))
		{
			return 0.0;
		}
		double y = error;

		if (enable.enablePid)
		{
			if (!TryApplyBiquad(
				y,
				pid.pidB0,
				pid.pidB1,
				pid.pidB2,
				pid.pidA1,
				pid.pidA2,
				m_pidState,
				y))
			{
				return 0.0;
			}
		}

		if (enable.enableLead)
		{
			if (!TryApplyBiquad(
				y,
				lead.leadB0,
				lead.leadB1,
				lead.leadB2,
				lead.leadA1,
				lead.leadA2,
				m_leadState,
				y))
			{
				return 0.0;
			}
		}

		if (enable.enableNotch)
		{
			if (!TryApplyBiquad(
				y,
				notch.notchB0,
				notch.notchB1,
				notch.notchB2,
				notch.notchA1,
				notch.notchA2,
				m_notchState,
				y))
			{
				return 0.0;
			}
		}

		if (enable.enableReso)
		{
			if (!TryApplyBiquad(
				y,
				reso.resoB0,
				reso.resoB1,
				reso.resoB2,
				reso.resoA1,
				reso.resoA2,
				m_resoState,
				y))
			{
				return 0.0;
			}
		}

		const double output = y + ffValue;
		return IsFinite(output) ? output : 0.0;
	}

private:
	struct BiquadState
	{
		double s1;
		double s2;
	};

	static bool IsFinite(double value) noexcept;
	static bool TryApplyBiquad(
		double x,
		double b0,
		double b1,
		double b2,
		double a1,
		double a2,
		BiquadState& state,
		double& output) noexcept;

	BiquadState m_pidState;
	BiquadState m_leadState;
	BiquadState m_notchState;
	BiquadState m_resoState;
};
} // namespace controllercore
