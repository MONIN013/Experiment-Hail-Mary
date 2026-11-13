///////////////////////////////////////////////////////////////////////////////
// DriverAdapterAlgorithm.h

#pragma once

#include <cstdint>

namespace driveradapter
{
struct AxisParameters
{
	std::uint32_t encoderResolution;
	double ratedCurrentA;
	double maxCurrentA;
	std::int32_t positionSign;
	std::int32_t velocitySign;
	std::int32_t currentSign;
	bool enableRelativePosition;
};

struct SafetyLimits
{
	double maxPositionRad;
	double maxVelocityRadS;
	double maxTwistRad;
};

struct Parameters
{
	AxisParameters motor;
	AxisParameters load;
	SafetyLimits safety;
	std::uint32_t safetyResetRevision;
};

struct RawSignals
{
	std::int32_t positionActualValue;
	std::int32_t velocityActualValue;
	std::int16_t torqueActualValue;
	std::uint16_t statusWord;
};

struct Inputs
{
	RawSignals motorRaw;
	RawSignals loadRaw;
	double controlInput;
	double distValue;
	std::uint16_t motorControlWordIn;
	std::uint16_t loadControlWordIn;
	bool enableCurrentOutput;
	bool playbackDone;
	bool resetReq;
};

struct EngineeringSignals
{
	double positionAbs;
	double positionRel;
	double velocityAct;
	double currentAct;
};

struct Outputs
{
	EngineeringSignals motor;
	EngineeringSignals load;
	double currentCmd;
	std::int16_t targetTorque;
	std::uint16_t motorControlWordOut;
	std::uint16_t loadControlWordOut;
	std::uint16_t motorStatusWordOut;
	std::uint16_t loadStatusWordOut;
	bool safetyTrip;
	std::uint32_t safetyCode; // 0: clear, 1: position, 2: speed, 3: twist, 4: settings.
};

class DriverAdapterAlgorithm final
{
public:
	DriverAdapterAlgorithm() noexcept;
	DriverAdapterAlgorithm(const DriverAdapterAlgorithm&) = delete;
	DriverAdapterAlgorithm& operator=(const DriverAdapterAlgorithm&) = delete;

	void Reset() noexcept;
	Outputs Step(const Parameters& parameters, const Inputs& inputs) noexcept;

private:
	bool m_prevResetReq;
	double m_motorPositionOffsetRad;
	double m_loadPositionOffsetRad;
	std::uint32_t m_safetyCode;
	std::uint32_t m_lastSeenSafetyResetRevision;
};
} // namespace driveradapter
