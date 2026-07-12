///////////////////////////////////////////////////////////////////////////////
// DriverAdapterAlgorithm.cpp

#include "DriverAdapterAlgorithm.h"

#include "TcNumeric.h"
#include "TcUnits.h"

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
	if (currentGateOpen && tccommon::units::HasValidCurrentScale(motorScaling))
	{
		outputs.targetTorque = tccommon::numeric::SaturatingRoundToInt16(
			tccommon::units::ConvertCurrentAToPermille(outputs.currentCmd, motorScaling));
	}

	outputs.motorControlWordOut = inputs.motorControlWordIn;
	outputs.loadControlWordOut = inputs.loadControlWordIn;
	outputs.motorStatusWordOut = inputs.motorRaw.statusWord;
	outputs.loadStatusWordOut = inputs.loadRaw.statusWord;

	m_prevResetReq = inputs.resetReq;
	return outputs;
}
} // namespace driveradapter
