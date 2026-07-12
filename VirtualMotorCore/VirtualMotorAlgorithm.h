///////////////////////////////////////////////////////////////////////////////
// VirtualMotorAlgorithm.h

#pragma once

#include <cstdint>

namespace virtualmotor
{
struct MotorParameters
{
	double inertia;
	double damping;
	double ratedTorque;
	double torqueLimit;
	double velocityLimit;
	double maxPermille;
	std::uint32_t encoderResolution;
};

struct LoadParameters
{
	double inertia;
	double damping;
	double ratedTorque;
	double torqueLimit;
	double velocityLimit;
	std::uint32_t encoderResolution;
};

struct Parameters
{
	MotorParameters motor;
	LoadParameters load;
	double couplingStiffness;
	double couplingDamping;
	std::uint64_t taskDtNs;
};

struct Inputs
{
	std::int16_t motorTargetTorque;
	std::uint16_t motorControlWord;
	std::uint16_t loadControlWord;
};

struct AxisOutputs
{
	std::int32_t positionActualValue;
	std::int32_t velocityActualValue;
	std::int16_t torqueActualValue;
	std::uint16_t statusWord;
};

struct Outputs
{
	AxisOutputs motor;
	AxisOutputs load;
};

class VirtualMotorAlgorithm final
{
public:
	VirtualMotorAlgorithm() noexcept;
	VirtualMotorAlgorithm(const VirtualMotorAlgorithm&) = delete;
	VirtualMotorAlgorithm& operator=(const VirtualMotorAlgorithm&) = delete;

	void Reset() noexcept;
	Outputs Step(const Parameters& parameters, const Inputs& inputs) noexcept;
	Outputs GetOutputs(const Parameters& parameters) const noexcept;

private:
	enum class DriveState
	{
		SWITCH_ON_DISABLED,
		READY_TO_SWITCH_ON,
		SWITCHED_ON,
		OPERATION_ENABLED,
		FAULT
	};

	enum AxisIndex
	{
		kMotorAxis = 0,
		kLoadAxis = 1,
		kAxisCount = 2
	};

	struct DriveRuntimeState
	{
		DriveState driveState;
		bool faultResetBitWasSet;
		bool internalFault;
	};

	struct PlantRuntimeState
	{
		double thetaMotor;
		double omegaMotor;
		double thetaLoad;
		double omegaLoad;
		double lastMotorTorqueNm;
		double lastShaftTorqueNm;
	};

	static double EffectiveRatedTorque(double ratedTorque) noexcept;
	static std::uint32_t EffectiveEncoderResolution(std::uint32_t encoderResolution) noexcept;
	void UpdateDriveState(int axisIndex, std::uint16_t controlWord) noexcept;
	std::uint16_t ComposeStatusWord(int axisIndex) const noexcept;
	void EvaluateMotorCommandFaults(const Parameters& parameters, double targetTorquePermille) noexcept;
	void IntegratePlant(const Parameters& parameters, double targetTorquePermille) noexcept;
	DriveRuntimeState& Drive(int axisIndex) noexcept;
	const DriveRuntimeState& Drive(int axisIndex) const noexcept;

	DriveRuntimeState m_drive[kAxisCount];
	PlantRuntimeState m_plantState;
};
} // namespace virtualmotor
