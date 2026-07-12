#include "VirtualMotorAlgorithm.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>

namespace
{
virtualmotor::Parameters MakeParameters() noexcept
{
	return {
		{ 1.0, 0.0, 1.0, 0.0, 0.0, 1000.0, 6283185U },
		{ 1.0, 0.0, 1.0, 0.0, 0.0, 6283185U },
		0.0,
		0.0,
		1000000000ULL
	};
}

virtualmotor::Outputs Step(
	virtualmotor::VirtualMotorAlgorithm& algorithm,
	const virtualmotor::Parameters& parameters,
	std::uint16_t motorControlWord,
	std::uint16_t loadControlWord,
	std::int16_t targetTorque = 0) noexcept
{
	return algorithm.Step(parameters, { targetTorque, motorControlWord, loadControlWord });
}

virtualmotor::Outputs EnableBoth(
	virtualmotor::VirtualMotorAlgorithm& algorithm,
	const virtualmotor::Parameters& parameters,
	std::int16_t targetTorque = 0) noexcept
{
	(void)Step(algorithm, parameters, 0x0006U, 0x0006U);
	(void)Step(algorithm, parameters, 0x0007U, 0x0007U);
	return Step(algorithm, parameters, 0x000FU, 0x000FU, targetTorque);
}

bool Equal(const virtualmotor::AxisOutputs& left, const virtualmotor::AxisOutputs& right) noexcept
{
	return left.positionActualValue == right.positionActualValue
		&& left.velocityActualValue == right.velocityActualValue
		&& left.torqueActualValue == right.torqueActualValue
		&& left.statusWord == right.statusWord;
}

bool VerifyInitialAndCiaSequence()
{
	virtualmotor::VirtualMotorAlgorithm algorithm;
	const virtualmotor::Parameters parameters = MakeParameters();
	virtualmotor::Outputs outputs = algorithm.GetOutputs(parameters);
	if (outputs.motor.statusWord != 0x0060U || outputs.load.statusWord != 0x0060U
		|| outputs.motor.positionActualValue != 0 || outputs.load.positionActualValue != 0)
	{
		return false;
	}

	outputs = Step(algorithm, parameters, 0x0006U, 0x0006U);
	if (outputs.motor.statusWord != 0x0021U || outputs.load.statusWord != 0x0021U)
	{
		return false;
	}
	outputs = Step(algorithm, parameters, 0x0007U, 0x0007U);
	if (outputs.motor.statusWord != 0x0023U || outputs.load.statusWord != 0x0023U)
	{
		return false;
	}
	outputs = Step(algorithm, parameters, 0x000FU, 0x000FU);
	if (outputs.motor.statusWord != 0x0027U || outputs.load.statusWord != 0x0027U)
	{
		return false;
	}
	outputs = Step(algorithm, parameters, 0x0000U, 0x000FU);
	return outputs.motor.statusWord == 0x0060U && outputs.load.statusWord == 0x0027U;
}

bool VerifyGoldenIntegrationAndReset()
{
	virtualmotor::VirtualMotorAlgorithm algorithm;
	virtualmotor::Parameters parameters = MakeParameters();
	parameters.motor.maxPermille = 0.0;
	virtualmotor::Outputs outputs = EnableBoth(algorithm, parameters, 1000);
	if (outputs.motor.statusWord != 0x0027U
		|| outputs.motor.positionActualValue != 1000000
		|| outputs.motor.velocityActualValue != 1000000
		|| outputs.motor.torqueActualValue != 1000
		|| outputs.load.positionActualValue != 0
		|| outputs.load.velocityActualValue != 0
		|| outputs.load.torqueActualValue != 0)
	{
		return false;
	}

	outputs = Step(algorithm, parameters, 0x000FU, 0x000FU, 0);
	if (outputs.motor.positionActualValue != 2000000
		|| outputs.motor.velocityActualValue != 1000000
		|| outputs.motor.torqueActualValue != 0)
	{
		return false;
	}

	algorithm.Reset();
	outputs = algorithm.GetOutputs(parameters);
	return outputs.motor.statusWord == 0x0060U
		&& outputs.load.statusWord == 0x0060U
		&& outputs.motor.positionActualValue == 0
		&& outputs.motor.velocityActualValue == 0;
}

bool VerifyPlantStateCarriesAcrossDriveDisable()
{
	virtualmotor::VirtualMotorAlgorithm algorithm;
	virtualmotor::Parameters parameters = MakeParameters();
	parameters.motor.maxPermille = 0.0;
	virtualmotor::Outputs outputs = EnableBoth(algorithm, parameters, 1000);
	if (outputs.motor.positionActualValue != 1000000 || outputs.motor.velocityActualValue != 1000000)
	{
		return false;
	}

	outputs = Step(algorithm, parameters, 0x0000U, 0x000FU);
	if (outputs.motor.statusWord != 0x0060U
		|| outputs.motor.positionActualValue != 2000000
		|| outputs.motor.velocityActualValue != 1000000
		|| outputs.motor.torqueActualValue != 0)
	{
		return false;
	}

	(void)Step(algorithm, parameters, 0x0006U, 0x000FU);
	(void)Step(algorithm, parameters, 0x0007U, 0x000FU);
	outputs = Step(algorithm, parameters, 0x000FU, 0x000FU);
	return outputs.motor.statusWord == 0x0027U
		&& outputs.motor.positionActualValue == 5000000
		&& outputs.motor.velocityActualValue == 1000000;
}

bool VerifyCommandFaultsAndResetEdges()
{
	virtualmotor::VirtualMotorAlgorithm algorithm;
	virtualmotor::Parameters parameters = MakeParameters();
	virtualmotor::Outputs outputs = EnableBoth(algorithm, parameters, 1001);
	if (outputs.motor.statusWord != 0x0028U || outputs.motor.torqueActualValue != 0)
	{
		return false;
	}

	outputs = Step(algorithm, parameters, 0x0080U, 0x000FU);
	if (outputs.motor.statusWord != 0x0060U)
	{
		return false;
	}
	outputs = Step(algorithm, parameters, 0x0080U, 0x000FU);
	if (outputs.motor.statusWord != 0x0060U)
	{
		return false;
	}

	(void)Step(algorithm, parameters, 0x0000U, 0x000FU);
	(void)Step(algorithm, parameters, 0x0006U, 0x000FU);
	(void)Step(algorithm, parameters, 0x0007U, 0x000FU);
	outputs = Step(algorithm, parameters, 0x000FU, 0x000FU, 1001);
	if (outputs.motor.statusWord != 0x0028U)
	{
		return false;
	}
	outputs = Step(algorithm, parameters, 0x0080U, 0x000FU);
	if (outputs.motor.statusWord != 0x0060U)
	{
		return false;
	}

	virtualmotor::VirtualMotorAlgorithm torqueLimitAlgorithm;
	parameters.motor.maxPermille = 0.0;
	parameters.motor.torqueLimit = 0.1;
	outputs = EnableBoth(torqueLimitAlgorithm, parameters, 1000);
	return outputs.motor.statusWord == 0x0028U && outputs.motor.torqueActualValue == 0;
}

bool VerifyFaultScanOrdering()
{
	virtualmotor::Parameters parameters = MakeParameters();
	parameters.motor.maxPermille = 0.0;
	parameters.motor.velocityLimit = 0.5;
	virtualmotor::VirtualMotorAlgorithm velocityAlgorithm;
	virtualmotor::Outputs outputs = EnableBoth(velocityAlgorithm, parameters, 1000);
	if (outputs.motor.statusWord != 0x0028U
		|| outputs.motor.positionActualValue != 500000
		|| outputs.motor.velocityActualValue != 500000
		|| outputs.motor.torqueActualValue != 1000)
	{
		return false;
	}

	parameters = MakeParameters();
	parameters.motor.maxPermille = 0.0;
	parameters.couplingStiffness = 1.0;
	parameters.load.torqueLimit = 0.1;
	virtualmotor::VirtualMotorAlgorithm shaftAlgorithm;
	outputs = EnableBoth(shaftAlgorithm, parameters, 1000);
	return outputs.motor.statusWord == 0x0027U
		&& outputs.load.statusWord == 0x0028U
		&& outputs.motor.torqueActualValue == 1000
		&& outputs.load.torqueActualValue == 1000;
}

bool VerifyInvalidPlantIsInert()
{
	virtualmotor::Parameters parameters = MakeParameters();
	parameters.motor.maxPermille = 0.0;
	parameters.taskDtNs = 0U;
	virtualmotor::VirtualMotorAlgorithm zeroDtAlgorithm;
	virtualmotor::Outputs outputs = EnableBoth(zeroDtAlgorithm, parameters, 1000);
	if (outputs.motor.statusWord != 0x0027U
		|| outputs.motor.positionActualValue != 0
		|| outputs.motor.velocityActualValue != 0
		|| outputs.motor.torqueActualValue != 0)
	{
		return false;
	}

	parameters = MakeParameters();
	parameters.motor.maxPermille = 0.0;
	parameters.motor.inertia = std::numeric_limits<double>::quiet_NaN();
	virtualmotor::VirtualMotorAlgorithm invalidInertiaAlgorithm;
	outputs = EnableBoth(invalidInertiaAlgorithm, parameters, 1000);
	return outputs.motor.statusWord == 0x0027U
		&& outputs.motor.positionActualValue == 0
		&& outputs.motor.velocityActualValue == 0
		&& outputs.motor.torqueActualValue == 0;
}

bool VerifyCurrentRatedTorqueFallback()
{
	virtualmotor::Parameters parameters = MakeParameters();
	parameters.motor.ratedTorque = 0.0;
	parameters.motor.maxPermille = 0.0;

	parameters.motor.torqueLimit = std::nextafter(0.32, 0.0);
	virtualmotor::VirtualMotorAlgorithm belowLimitAlgorithm;
	const virtualmotor::Outputs belowLimitOutputs = EnableBoth(belowLimitAlgorithm, parameters, 1000);
	if (belowLimitOutputs.motor.statusWord != 0x0028U)
	{
		return false;
	}

	parameters.motor.torqueLimit = std::nextafter(0.32, std::numeric_limits<double>::infinity());
	virtualmotor::VirtualMotorAlgorithm aboveLimitAlgorithm;
	const virtualmotor::Outputs aboveLimitOutputs = EnableBoth(aboveLimitAlgorithm, parameters, 1000);
	return aboveLimitOutputs.motor.statusWord == 0x0027U
		&& aboveLimitOutputs.motor.torqueActualValue == 1000;
}

bool VerifyDeterministicStress()
{
	virtualmotor::Parameters parameters = MakeParameters();
	parameters.motor.inertia = 0.01;
	parameters.load.inertia = 0.02;
	parameters.motor.damping = 0.05;
	parameters.load.damping = 0.04;
	parameters.motor.maxPermille = 0.0;
	parameters.couplingStiffness = 2.0;
	parameters.couplingDamping = 0.01;
	parameters.taskDtNs = 125000U;
	virtualmotor::VirtualMotorAlgorithm left;
	virtualmotor::VirtualMotorAlgorithm right;
	(void)EnableBoth(left, parameters);
	(void)EnableBoth(right, parameters);

	virtualmotor::Outputs leftOutputs = {};
	virtualmotor::Outputs rightOutputs = {};
	for (std::uint32_t i = 0U; i < 1000000U; ++i)
	{
		const std::int16_t target = static_cast<std::int16_t>(static_cast<int>(i % 401U) - 200);
		leftOutputs = Step(left, parameters, 0x000FU, 0x000FU, target);
		rightOutputs = Step(right, parameters, 0x000FU, 0x000FU, target);
	}

	return Equal(leftOutputs.motor, rightOutputs.motor)
		&& Equal(leftOutputs.load, rightOutputs.load);
}
} // namespace

int main()
{
	if (!VerifyInitialAndCiaSequence()
		|| !VerifyGoldenIntegrationAndReset()
		|| !VerifyPlantStateCarriesAcrossDriveDisable()
		|| !VerifyCommandFaultsAndResetEdges()
		|| !VerifyFaultScanOrdering()
		|| !VerifyInvalidPlantIsInert()
		|| !VerifyCurrentRatedTorqueFallback()
		|| !VerifyDeterministicStress())
	{
		return 1;
	}

	std::cout << "VirtualMotorAlgorithm tests passed\n";
	return 0;
}
