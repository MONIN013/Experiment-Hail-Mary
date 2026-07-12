///////////////////////////////////////////////////////////////////////////////
// VirtualMotorAlgorithm.cpp

#include "VirtualMotorAlgorithm.h"

#include "TcNumeric.h"

#include <cmath>

namespace
{
constexpr double kTwoPi = 6.28318530717958647692;
constexpr double kDefaultRatedTorqueNm = 0.32;
constexpr std::uint32_t kDefaultEncoderResolution = 8388608U;
}

namespace virtualmotor
{
VirtualMotorAlgorithm::VirtualMotorAlgorithm() noexcept
{
	Reset();
}

void VirtualMotorAlgorithm::Reset() noexcept
{
	for (int i = 0; i < kAxisCount; ++i)
	{
		m_drive[i].driveState = DriveState::SWITCH_ON_DISABLED;
		m_drive[i].faultResetBitWasSet = false;
		m_drive[i].internalFault = false;
	}

	m_plantState = {};
}

Outputs VirtualMotorAlgorithm::Step(const Parameters& parameters, const Inputs& inputs) noexcept
{
	UpdateDriveState(kMotorAxis, inputs.motorControlWord);
	UpdateDriveState(kLoadAxis, inputs.loadControlWord);

	const double targetTorquePermille = static_cast<double>(inputs.motorTargetTorque);
	EvaluateMotorCommandFaults(parameters, targetTorquePermille);
	IntegratePlant(parameters, targetTorquePermille);
	return GetOutputs(parameters);
}

Outputs VirtualMotorAlgorithm::GetOutputs(const Parameters& parameters) const noexcept
{
	const double motorScale = static_cast<double>(EffectiveEncoderResolution(parameters.motor.encoderResolution)) / kTwoPi;
	const double loadScale = static_cast<double>(EffectiveEncoderResolution(parameters.load.encoderResolution)) / kTwoPi;

	Outputs outputs = {};
	outputs.motor.positionActualValue = tccommon::numeric::SaturatingRoundToInt32(
		m_plantState.thetaMotor * motorScale);
	outputs.motor.velocityActualValue = tccommon::numeric::SaturatingRoundToInt32(
		m_plantState.omegaMotor * motorScale);
	outputs.motor.torqueActualValue = tccommon::numeric::SaturatingRoundToInt16(
		(m_plantState.lastMotorTorqueNm / EffectiveRatedTorque(parameters.motor.ratedTorque)) * 1000.0);
	outputs.motor.statusWord = ComposeStatusWord(kMotorAxis);

	outputs.load.positionActualValue = tccommon::numeric::SaturatingRoundToInt32(
		m_plantState.thetaLoad * loadScale);
	outputs.load.velocityActualValue = tccommon::numeric::SaturatingRoundToInt32(
		m_plantState.omegaLoad * loadScale);
	outputs.load.torqueActualValue = tccommon::numeric::SaturatingRoundToInt16(
		(m_plantState.lastShaftTorqueNm / EffectiveRatedTorque(parameters.load.ratedTorque)) * 1000.0);
	outputs.load.statusWord = ComposeStatusWord(kLoadAxis);
	return outputs;
}

double VirtualMotorAlgorithm::EffectiveRatedTorque(double ratedTorque) noexcept
{
	return (ratedTorque > 0.0) ? ratedTorque : kDefaultRatedTorqueNm;
}

std::uint32_t VirtualMotorAlgorithm::EffectiveEncoderResolution(std::uint32_t encoderResolution) noexcept
{
	return (encoderResolution > 0U) ? encoderResolution : kDefaultEncoderResolution;
}

void VirtualMotorAlgorithm::EvaluateMotorCommandFaults(
	const Parameters& parameters,
	double targetTorquePermille) noexcept
{
	DriveRuntimeState& motorDrive = Drive(kMotorAxis);
	if (motorDrive.driveState != DriveState::OPERATION_ENABLED || motorDrive.internalFault)
	{
		return;
	}

	const double maxPermille = tccommon::numeric::NonNegativeOrZero(parameters.motor.maxPermille);
	if (maxPermille > 0.0 && std::fabs(targetTorquePermille) > maxPermille)
	{
		motorDrive.internalFault = true;
		motorDrive.driveState = DriveState::FAULT;
		return;
	}

	const double torqueRequestNm =
		(targetTorquePermille / 1000.0) * EffectiveRatedTorque(parameters.motor.ratedTorque);
	const double torqueLimitAbs = std::fabs(parameters.motor.torqueLimit);
	if (torqueLimitAbs > 0.0 && std::fabs(torqueRequestNm) > torqueLimitAbs)
	{
		motorDrive.internalFault = true;
		motorDrive.driveState = DriveState::FAULT;
	}
}

void VirtualMotorAlgorithm::IntegratePlant(
	const Parameters& parameters,
	double targetTorquePermille) noexcept
{
	const double dtS = static_cast<double>(parameters.taskDtNs) * 1e-9;
	const double motorInertia = tccommon::numeric::NonNegativeOrZero(parameters.motor.inertia);
	const double loadInertia = tccommon::numeric::NonNegativeOrZero(parameters.load.inertia);
	if (dtS <= 0.0 || motorInertia <= 0.0 || loadInertia <= 0.0)
	{
		m_plantState.lastMotorTorqueNm = 0.0;
		m_plantState.lastShaftTorqueNm = 0.0;
		return;
	}

	const double motorDamping = tccommon::numeric::NonNegativeOrZero(parameters.motor.damping);
	const double loadDamping = tccommon::numeric::NonNegativeOrZero(parameters.load.damping);
	const double couplingStiffness = tccommon::numeric::NonNegativeOrZero(parameters.couplingStiffness);
	const double couplingDamping = tccommon::numeric::NonNegativeOrZero(parameters.couplingDamping);

	double motorTorqueNm = 0.0;
	if (Drive(kMotorAxis).driveState == DriveState::OPERATION_ENABLED
		&& !Drive(kMotorAxis).internalFault)
	{
		const double torqueRequestNm =
			(targetTorquePermille / 1000.0) * EffectiveRatedTorque(parameters.motor.ratedTorque);
		motorTorqueNm = tccommon::numeric::ApplyOptionalSymmetricLimit(
			torqueRequestNm, parameters.motor.torqueLimit);
	}

	const double thetaDelta = m_plantState.thetaMotor - m_plantState.thetaLoad;
	const double omegaDelta = m_plantState.omegaMotor - m_plantState.omegaLoad;
	const double shaftTorqueNm = couplingStiffness * thetaDelta + couplingDamping * omegaDelta;

	const double motorVelocityNextUnclamped = m_plantState.omegaMotor
		+ dtS * ((motorTorqueNm - shaftTorqueNm - motorDamping * m_plantState.omegaMotor) / motorInertia);
	const double loadVelocityNextUnclamped = m_plantState.omegaLoad
		+ dtS * ((shaftTorqueNm - loadDamping * m_plantState.omegaLoad) / loadInertia);

	const double motorVelocityLimitAbs = std::fabs(parameters.motor.velocityLimit);
	if (motorVelocityLimitAbs > 0.0 && std::fabs(motorVelocityNextUnclamped) > motorVelocityLimitAbs)
	{
		Drive(kMotorAxis).internalFault = true;
		Drive(kMotorAxis).driveState = DriveState::FAULT;
	}

	const double loadVelocityLimitAbs = std::fabs(parameters.load.velocityLimit);
	if (loadVelocityLimitAbs > 0.0 && std::fabs(loadVelocityNextUnclamped) > loadVelocityLimitAbs)
	{
		Drive(kLoadAxis).internalFault = true;
		Drive(kLoadAxis).driveState = DriveState::FAULT;
	}

	double motorVelocityNext = tccommon::numeric::ApplyOptionalSymmetricLimit(
		motorVelocityNextUnclamped, parameters.motor.velocityLimit);
	double loadVelocityNext = tccommon::numeric::ApplyOptionalSymmetricLimit(
		loadVelocityNextUnclamped, parameters.load.velocityLimit);
	if (std::fabs(motorVelocityNext) < 1e-9)
	{
		motorVelocityNext = 0.0;
	}
	if (std::fabs(loadVelocityNext) < 1e-9)
	{
		loadVelocityNext = 0.0;
	}

	m_plantState.thetaMotor += dtS * motorVelocityNext;
	m_plantState.thetaLoad += dtS * loadVelocityNext;
	m_plantState.omegaMotor = motorVelocityNext;
	m_plantState.omegaLoad = loadVelocityNext;

	const double shaftTorqueNextNm = couplingStiffness
		* (m_plantState.thetaMotor - m_plantState.thetaLoad)
		+ couplingDamping * (m_plantState.omegaMotor - m_plantState.omegaLoad);
	const double loadTorqueLimitAbs = std::fabs(parameters.load.torqueLimit);
	if (loadTorqueLimitAbs > 0.0 && std::fabs(shaftTorqueNextNm) > loadTorqueLimitAbs)
	{
		Drive(kLoadAxis).internalFault = true;
		Drive(kLoadAxis).driveState = DriveState::FAULT;
	}

	m_plantState.lastMotorTorqueNm = motorTorqueNm;
	m_plantState.lastShaftTorqueNm = shaftTorqueNextNm;
}

void VirtualMotorAlgorithm::UpdateDriveState(int axisIndex, std::uint16_t controlWord) noexcept
{
	DriveRuntimeState& axis = Drive(axisIndex);
	const bool disableVoltage = (controlWord & 0x0002U) == 0U;
	const bool faultResetBitSet = (controlWord & 0x0080U) != 0U;
	const bool faultResetPulse = faultResetBitSet && !axis.faultResetBitWasSet;
	const bool isShutdown = (controlWord & 0x008FU) == 0x0006U;
	const bool isSwitchOn = (controlWord & 0x008FU) == 0x0007U;
	const bool isEnableOperation = (controlWord & 0x008FU) == 0x000FU;

	axis.faultResetBitWasSet = faultResetBitSet;

	if (axis.driveState == DriveState::FAULT || axis.internalFault)
	{
		axis.driveState = DriveState::FAULT;
		axis.internalFault = true;
		if (faultResetPulse)
		{
			axis.internalFault = false;
			axis.driveState = DriveState::SWITCH_ON_DISABLED;
		}
		return;
	}

	if (disableVoltage)
	{
		axis.driveState = DriveState::SWITCH_ON_DISABLED;
		return;
	}

	switch (axis.driveState)
	{
	case DriveState::SWITCH_ON_DISABLED:
		if (isShutdown)
		{
			axis.driveState = DriveState::READY_TO_SWITCH_ON;
		}
		break;
	case DriveState::READY_TO_SWITCH_ON:
		if (isSwitchOn)
		{
			axis.driveState = DriveState::SWITCHED_ON;
		}
		break;
	case DriveState::SWITCHED_ON:
		if (isEnableOperation)
		{
			axis.driveState = DriveState::OPERATION_ENABLED;
		}
		break;
	case DriveState::OPERATION_ENABLED:
	case DriveState::FAULT:
		break;
	}
}

std::uint16_t VirtualMotorAlgorithm::ComposeStatusWord(int axisIndex) const noexcept
{
	switch (Drive(axisIndex).driveState)
	{
	case DriveState::SWITCH_ON_DISABLED:
		return 0x0060U;
	case DriveState::READY_TO_SWITCH_ON:
		return 0x0021U;
	case DriveState::SWITCHED_ON:
		return 0x0023U;
	case DriveState::OPERATION_ENABLED:
		return 0x0027U;
	case DriveState::FAULT:
		return 0x0028U;
	}
	return 0U;
}

VirtualMotorAlgorithm::DriveRuntimeState& VirtualMotorAlgorithm::Drive(int axisIndex) noexcept
{
	return m_drive[axisIndex];
}

const VirtualMotorAlgorithm::DriveRuntimeState& VirtualMotorAlgorithm::Drive(int axisIndex) const noexcept
{
	return m_drive[axisIndex];
}
} // namespace virtualmotor
