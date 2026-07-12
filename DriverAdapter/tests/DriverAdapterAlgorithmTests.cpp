#include "DriverAdapterAlgorithm.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>

namespace
{
constexpr double kTwoPi = 6.28318530717958647692;

driveradapter::AxisParameters MakeAxisParameters() noexcept
{
	return { 1000U, 1.6, 1.6, 1, 1, 1, true };
}

driveradapter::Parameters MakeParameters() noexcept
{
	return { MakeAxisParameters(), MakeAxisParameters() };
}

driveradapter::Inputs MakeInputs() noexcept
{
	return {
		{ 0, 0, 0, 0x1234U },
		{ 0, 0, 0, 0xABCDU },
		0.0,
		0.0,
		0x000FU,
		0x0006U,
		true,
		false,
		false
	};
}

bool Near(double actual, double expected, double tolerance = 1e-12) noexcept
{
	return std::fabs(actual - expected) <= tolerance;
}

bool Equal(const driveradapter::Outputs& left, const driveradapter::Outputs& right) noexcept
{
	return left.motor.positionAbs == right.motor.positionAbs
		&& left.motor.positionRel == right.motor.positionRel
		&& left.motor.velocityAct == right.motor.velocityAct
		&& left.motor.currentAct == right.motor.currentAct
		&& left.load.positionAbs == right.load.positionAbs
		&& left.load.positionRel == right.load.positionRel
		&& left.load.velocityAct == right.load.velocityAct
		&& left.load.currentAct == right.load.currentAct
		&& left.currentCmd == right.currentCmd
		&& left.targetTorque == right.targetTorque
		&& left.motorControlWordOut == right.motorControlWordOut
		&& left.loadControlWordOut == right.loadControlWordOut
		&& left.motorStatusWordOut == right.motorStatusWordOut
		&& left.loadStatusWordOut == right.loadStatusWordOut;
}

bool VerifyCurrentPresetAndRelays()
{
	driveradapter::DriverAdapterAlgorithm algorithm;
	const driveradapter::Parameters parameters = MakeParameters();
	driveradapter::Inputs inputs = MakeInputs();
	inputs.motorRaw = { 100, 200, 1000, 0x1357U };
	inputs.loadRaw = { -50, -300, 1000, 0x2468U };
	inputs.controlInput = 1.2;
	inputs.distValue = 0.8;
	inputs.motorControlWordIn = 0x1111U;
	inputs.loadControlWordIn = 0x2222U;

	const driveradapter::Outputs outputs = algorithm.Step(parameters, inputs);
	return Near(outputs.motor.positionAbs, 0.1 * kTwoPi)
		&& Near(outputs.motor.positionRel, 0.1 * kTwoPi)
		&& Near(outputs.motor.velocityAct, 0.2 * kTwoPi)
		&& Near(outputs.motor.currentAct, 1.6)
		&& Near(outputs.load.positionAbs, -0.05 * kTwoPi)
		&& Near(outputs.load.velocityAct, -0.3 * kTwoPi)
		&& Near(outputs.load.currentAct, 1.6)
		&& outputs.currentCmd == 1.6
		&& outputs.targetTorque == 1000
		&& outputs.motorControlWordOut == 0x1111U
		&& outputs.loadControlWordOut == 0x2222U
		&& outputs.motorStatusWordOut == 0x1357U
		&& outputs.loadStatusWordOut == 0x2468U;
}

bool VerifyResetEdgeAndRelativePosition()
{
	driveradapter::DriverAdapterAlgorithm algorithm;
	driveradapter::Parameters parameters = MakeParameters();
	driveradapter::Inputs inputs = MakeInputs();
	inputs.motorRaw.positionActualValue = 100;
	inputs.loadRaw.positionActualValue = 200;
	inputs.resetReq = true;
	driveradapter::Outputs outputs = algorithm.Step(parameters, inputs);
	if (outputs.motor.positionRel != 0.0 || outputs.load.positionRel != 0.0)
	{
		return false;
	}

	inputs.motorRaw.positionActualValue = 150;
	inputs.loadRaw.positionActualValue = 250;
	outputs = algorithm.Step(parameters, inputs);
	if (!Near(outputs.motor.positionRel, 0.05 * kTwoPi)
		|| !Near(outputs.load.positionRel, 0.05 * kTwoPi))
	{
		return false;
	}

	inputs.resetReq = false;
	(void)algorithm.Step(parameters, inputs);
	inputs.resetReq = true;
	inputs.motorRaw.positionActualValue = 300;
	inputs.loadRaw.positionActualValue = -100;
	outputs = algorithm.Step(parameters, inputs);
	if (outputs.motor.positionRel != 0.0 || outputs.load.positionRel != 0.0)
	{
		return false;
	}

	algorithm.Reset();
	inputs.motorRaw.positionActualValue = 400;
	outputs = algorithm.Step(parameters, inputs);
	if (outputs.motor.positionRel != 0.0)
	{
		return false;
	}

	parameters.motor.enableRelativePosition = false;
	inputs.resetReq = false;
	(void)algorithm.Step(parameters, inputs);
	inputs.resetReq = true;
	inputs.motorRaw.positionActualValue = 500;
	outputs = algorithm.Step(parameters, inputs);
	return Near(outputs.motor.positionRel, outputs.motor.positionAbs);
}

bool VerifySignsAndInvalidScales()
{
	driveradapter::DriverAdapterAlgorithm algorithm;
	driveradapter::Parameters parameters = MakeParameters();
	parameters.motor.positionSign = -1;
	parameters.motor.velocitySign = -1;
	parameters.motor.currentSign = -1;
	driveradapter::Inputs inputs = MakeInputs();
	inputs.motorRaw = { 100, -200, 500, 0U };
	inputs.controlInput = 0.8;
	driveradapter::Outputs outputs = algorithm.Step(parameters, inputs);
	if (!Near(outputs.motor.positionAbs, -0.1 * kTwoPi)
		|| !Near(outputs.motor.velocityAct, 0.2 * kTwoPi)
		|| outputs.motor.currentAct != -0.8
		|| outputs.targetTorque != -500)
	{
		return false;
	}

	parameters.motor.encoderResolution = 0U;
	parameters.motor.ratedCurrentA = 0.0;
	inputs.resetReq = true;
	outputs = algorithm.Step(parameters, inputs);
	return outputs.motor.positionAbs == 0.0
		&& outputs.motor.positionRel == 0.0
		&& outputs.motor.velocityAct == 0.0
		&& outputs.motor.currentAct == 0.0
		&& outputs.targetTorque == 0;
}

bool VerifyCurrentGateRoundingAndSaturation()
{
	driveradapter::DriverAdapterAlgorithm algorithm;
	driveradapter::Parameters parameters = MakeParameters();
	driveradapter::Inputs inputs = MakeInputs();
	inputs.controlInput = 1.2;
	inputs.distValue = 0.8;
	inputs.enableCurrentOutput = false;
	driveradapter::Outputs outputs = algorithm.Step(parameters, inputs);
	if (outputs.currentCmd != 1.6 || outputs.targetTorque != 0)
	{
		return false;
	}

	inputs.enableCurrentOutput = true;
	inputs.playbackDone = true;
	outputs = algorithm.Step(parameters, inputs);
	if (outputs.currentCmd != 1.6 || outputs.targetTorque != 0)
	{
		return false;
	}

	inputs.playbackDone = false;
	inputs.controlInput = 0.0008;
	inputs.distValue = 0.0;
	outputs = algorithm.Step(parameters, inputs);
	if (outputs.targetTorque != 1)
	{
		return false;
	}
	inputs.controlInput = -0.0008;
	outputs = algorithm.Step(parameters, inputs);
	if (outputs.targetTorque != -1)
	{
		return false;
	}

	parameters.motor.ratedCurrentA = 1.0;
	parameters.motor.maxCurrentA = 100.0;
	inputs.controlInput = 100.0;
	outputs = algorithm.Step(parameters, inputs);
	if (outputs.targetTorque != std::numeric_limits<std::int16_t>::max())
	{
		return false;
	}
	inputs.controlInput = -100.0;
	outputs = algorithm.Step(parameters, inputs);
	return outputs.targetTorque == std::numeric_limits<std::int16_t>::min();
}

bool VerifyNonFiniteCurrentPath()
{
	driveradapter::DriverAdapterAlgorithm algorithm;
	driveradapter::Parameters parameters = MakeParameters();
	driveradapter::Inputs inputs = MakeInputs();
	inputs.controlInput = std::numeric_limits<double>::quiet_NaN();
	driveradapter::Outputs outputs = algorithm.Step(parameters, inputs);
	if (outputs.currentCmd != 0.0 || outputs.targetTorque != 0)
	{
		return false;
	}

	inputs.controlInput = 1.0;
	parameters.motor.maxCurrentA = std::numeric_limits<double>::infinity();
	outputs = algorithm.Step(parameters, inputs);
	if (outputs.currentCmd != 0.0 || outputs.targetTorque != 0)
	{
		return false;
	}

	parameters.motor.maxCurrentA = -1.6;
	outputs = algorithm.Step(parameters, inputs);
	return outputs.currentCmd == 1.0 && outputs.targetTorque == 625;
}

bool VerifyDeterministicStress()
{
	driveradapter::DriverAdapterAlgorithm left;
	driveradapter::DriverAdapterAlgorithm right;
	driveradapter::Parameters parameters = MakeParameters();
	driveradapter::Inputs inputs = MakeInputs();
	driveradapter::Outputs leftOutputs = {};
	driveradapter::Outputs rightOutputs = {};
	for (std::uint32_t i = 0U; i < 1000000U; ++i)
	{
		inputs.motorRaw.positionActualValue = static_cast<std::int32_t>(i * 17U);
		inputs.loadRaw.positionActualValue = -static_cast<std::int32_t>(i * 11U);
		inputs.motorRaw.velocityActualValue = static_cast<std::int32_t>(i % 20001U) - 10000;
		inputs.loadRaw.velocityActualValue = static_cast<std::int32_t>(i % 10001U) - 5000;
		inputs.motorRaw.torqueActualValue = static_cast<std::int16_t>(i % 2001U) - 1000;
		inputs.loadRaw.torqueActualValue = static_cast<std::int16_t>(i % 1001U) - 500;
		inputs.controlInput = static_cast<double>(static_cast<int>(i % 41U) - 20) * 0.05;
		inputs.distValue = static_cast<double>(static_cast<int>(i % 13U) - 6) * 0.01;
		inputs.enableCurrentOutput = (i % 3U) != 0U;
		inputs.playbackDone = (i % 101U) == 0U;
		inputs.resetReq = (i % 997U) == 0U;
		leftOutputs = left.Step(parameters, inputs);
		rightOutputs = right.Step(parameters, inputs);
		if (!Equal(leftOutputs, rightOutputs))
		{
			return false;
		}
	}
	return true;
}
} // namespace

int main()
{
	if (!VerifyCurrentPresetAndRelays()
		|| !VerifyResetEdgeAndRelativePosition()
		|| !VerifySignsAndInvalidScales()
		|| !VerifyCurrentGateRoundingAndSaturation()
		|| !VerifyNonFiniteCurrentPath()
		|| !VerifyDeterministicStress())
	{
		return 1;
	}

	std::cout << "DriverAdapterAlgorithm tests passed\n";
	return 0;
}
