///////////////////////////////////////////////////////////////////////////////
// DriverAdapterAlgorithm.cpp

#include "DriverAdapterAlgorithm.h"

#include "TcNumeric.h"
#include "TcUnits.h"

#include <cmath>

namespace
{
tccommon::units::AxisScaling MakeAxisScaling(const driveradapter::AxisParameters& parameters) noexcept
{
	return {
		parameters.encoderResolution,
		parameters.ratedCurrentA,
		static_cast<int>(parameters.positionSign),
		static_cast<int>(parameters.velocitySign),
		static_cast<int>(parameters.currentSign),
		parameters.enableRelativePosition
	};
}
}

namespace driveradapter
{
DriverAdapterAlgorithm::DriverAdapterAlgorithm() noexcept
{
	Reset();
}

void DriverAdapterAlgorithm::Reset() noexcept
{
	m_prevResetReq = false;
	m_motorPositionOffsetRad = 0.0;
	m_loadPositionOffsetRad = 0.0;
	m_safetyCode = 0;
	m_lastSeenSafetyResetRevision = 0;
}

Outputs DriverAdapterAlgorithm::Step(const Parameters& parameters, const Inputs& inputs) noexcept
{
	const bool resetEdge = inputs.resetReq && !m_prevResetReq;
	const tccommon::units::AxisScaling motorScaling = MakeAxisScaling(parameters.motor);
	const tccommon::units::AxisScaling loadScaling = MakeAxisScaling(parameters.load);

	const double motorPositionAbs = tccommon::units::ConvertPositionCountsToRad(
		inputs.motorRaw.positionActualValue, motorScaling);
	const double motorVelocityAct = tccommon::units::ConvertVelocityCountsToRad(
		inputs.motorRaw.velocityActualValue, motorScaling);
	const double motorCurrentAct = tccommon::units::ConvertPermilleToCurrentA(
		inputs.motorRaw.torqueActualValue, motorScaling);

	const double loadPositionAbs = tccommon::units::ConvertPositionCountsToRad(
		inputs.loadRaw.positionActualValue, loadScaling);
	const double loadVelocityAct = tccommon::units::ConvertVelocityCountsToRad(
		inputs.loadRaw.velocityActualValue, loadScaling);
	const double loadCurrentAct = tccommon::units::ConvertPermilleToCurrentA(
		inputs.loadRaw.torqueActualValue, loadScaling);

	if (resetEdge)
	{
		m_motorPositionOffsetRad =
			(motorScaling.enableRelativePosition && tccommon::units::HasValidPositionScale(motorScaling))
			? motorPositionAbs
			: 0.0;
		m_loadPositionOffsetRad =
			(loadScaling.enableRelativePosition && tccommon::units::HasValidPositionScale(loadScaling))
			? loadPositionAbs
			: 0.0;
	}

	Outputs outputs = {};
	outputs.motor.positionAbs = motorPositionAbs;
	outputs.motor.positionRel = tccommon::units::ComputeRelativePosition(
		motorPositionAbs, motorScaling, m_motorPositionOffsetRad);
	outputs.motor.velocityAct = motorVelocityAct;
	outputs.motor.currentAct = motorCurrentAct;

	outputs.load.positionAbs = loadPositionAbs;
	outputs.load.positionRel = tccommon::units::ComputeRelativePosition(
		loadPositionAbs, loadScaling, m_loadPositionOffsetRad);
	outputs.load.velocityAct = loadVelocityAct;
	outputs.load.currentAct = loadCurrentAct;

	outputs.currentCmd = tccommon::numeric::ClampSymmetric(
		inputs.controlInput + inputs.distValue, parameters.motor.maxCurrentA);
	const bool currentGateOpen = inputs.enableCurrentOutput && !inputs.playbackDone;
	if (parameters.safetyResetRevision != m_lastSeenSafetyResetRevision)
	{
		// Consume unsafe clear requests too: disabling later requires a new revision.
		m_lastSeenSafetyResetRevision = parameters.safetyResetRevision;
		if (!inputs.enableCurrentOutput
			&& (inputs.motorControlWordIn & 0x000FU) != 0x000FU
			&& (inputs.loadControlWordIn & 0x000FU) != 0x000FU)
			m_safetyCode = 0;
	}
	const auto& limit = parameters.safety;
	if (currentGateOpen && m_safetyCode == 0)
	{
		const bool invalid = !std::isfinite(limit.maxPositionRad) || limit.maxPositionRad < 0.0
			|| !std::isfinite(limit.maxVelocityRadS) || limit.maxVelocityRadS < 0.0
			|| !std::isfinite(limit.maxTwistRad) || limit.maxTwistRad < 0.0;
		const bool active = limit.maxPositionRad > 0.0 || limit.maxVelocityRadS > 0.0
			|| limit.maxTwistRad > 0.0;
		if (invalid || (active && (!tccommon::units::HasValidPositionScale(motorScaling)
			|| !tccommon::units::HasValidPositionScale(loadScaling))))
			m_safetyCode = 4;
		else if (limit.maxPositionRad > 0.0 && (std::fabs(outputs.motor.positionRel) > limit.maxPositionRad
			|| std::fabs(outputs.load.positionRel) > limit.maxPositionRad))
			m_safetyCode = 1;
		else if (limit.maxVelocityRadS > 0.0 && (std::fabs(motorVelocityAct) > limit.maxVelocityRadS
			|| std::fabs(loadVelocityAct) > limit.maxVelocityRadS))
			m_safetyCode = 2;
		else if (limit.maxTwistRad > 0.0
			&& std::fabs(outputs.motor.positionRel - outputs.load.positionRel) > limit.maxTwistRad)
			m_safetyCode = 3;
	}
	if (currentGateOpen && tccommon::units::HasValidCurrentScale(motorScaling))
	{
		outputs.targetTorque = tccommon::numeric::SaturatingRoundToInt16(
			tccommon::units::ConvertCurrentAToPermille(outputs.currentCmd, motorScaling));
	}

	outputs.motorControlWordOut = inputs.motorControlWordIn;
	outputs.loadControlWordOut = inputs.loadControlWordIn;
	outputs.motorStatusWordOut = inputs.motorRaw.statusWord;
	outputs.loadStatusWordOut = inputs.loadRaw.statusWord;
	outputs.safetyCode = m_safetyCode;
	outputs.safetyTrip = m_safetyCode != 0;
	if (outputs.safetyTrip)
	{
		// Latch in the fast task; later PLC enable requests cannot re-enable a drive.
		outputs.currentCmd = 0.0;
		outputs.targetTorque = 0;
		outputs.motorControlWordOut = 0;
		outputs.loadControlWordOut = 0;
	}

	m_prevResetReq = inputs.resetReq;
	return outputs;
}
} // namespace driveradapter
