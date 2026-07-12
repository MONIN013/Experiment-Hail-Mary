///////////////////////////////////////////////////////////////////////////////
// LoggerRecord.h

#pragma once

#include <cstddef>
#include <cstdint>

namespace experimentlogger
{
constexpr std::uint32_t kLogSchemaVersion = 2U;

#pragma pack(push, 1)
struct LogRecord
{
	std::uint32_t seq;
	std::uint32_t reservedPad0;
	std::uint64_t tNs;
	double motorPosition;
	double motorVelocity;
	double motorCurrentAct;
	double loadPosition;
	double loadVelocity;
	double currentCmd;
	double error;
	double refValue;
	double ffValue;
	double distValue;
	double controlInput;
};
#pragma pack(pop)

struct LogSample
{
	double motorPosition;
	double motorVelocity;
	double motorCurrentAct;
	double loadPosition;
	double loadVelocity;
	double currentCmd;
	double error;
	double refValue;
	double ffValue;
	double distValue;
	double controlInput;
};

inline LogRecord BuildLogRecord(
	std::uint32_t seq,
	std::uint64_t timestampStepNs,
	const LogSample& sample) noexcept
{
	LogRecord record = {};
	record.seq = seq;
	record.reservedPad0 = kLogSchemaVersion;
	record.tNs = static_cast<std::uint64_t>(seq) * timestampStepNs;
	record.motorPosition = sample.motorPosition;
	record.motorVelocity = sample.motorVelocity;
	record.motorCurrentAct = sample.motorCurrentAct;
	record.loadPosition = sample.loadPosition;
	record.loadVelocity = sample.loadVelocity;
	record.currentCmd = sample.currentCmd;
	record.error = sample.error;
	record.refValue = sample.refValue;
	record.ffValue = sample.ffValue;
	record.distValue = sample.distValue;
	record.controlInput = sample.controlInput;
	return record;
}

static_assert(sizeof(LogRecord) == 104U, "LogRecord must be 104 bytes");
static_assert(offsetof(LogRecord, seq) == 0U, "LogRecord.seq offset changed");
static_assert(offsetof(LogRecord, reservedPad0) == 4U, "LogRecord.reservedPad0 offset changed");
static_assert(offsetof(LogRecord, tNs) == 8U, "LogRecord.tNs offset changed");
static_assert(offsetof(LogRecord, motorPosition) == 16U, "LogRecord.motorPosition offset changed");
static_assert(offsetof(LogRecord, motorVelocity) == 24U, "LogRecord.motorVelocity offset changed");
static_assert(offsetof(LogRecord, motorCurrentAct) == 32U, "LogRecord.motorCurrentAct offset changed");
static_assert(offsetof(LogRecord, loadPosition) == 40U, "LogRecord.loadPosition offset changed");
static_assert(offsetof(LogRecord, loadVelocity) == 48U, "LogRecord.loadVelocity offset changed");
static_assert(offsetof(LogRecord, currentCmd) == 56U, "LogRecord.currentCmd offset changed");
static_assert(offsetof(LogRecord, error) == 64U, "LogRecord.error offset changed");
static_assert(offsetof(LogRecord, refValue) == 72U, "LogRecord.refValue offset changed");
static_assert(offsetof(LogRecord, ffValue) == 80U, "LogRecord.ffValue offset changed");
static_assert(offsetof(LogRecord, distValue) == 88U, "LogRecord.distValue offset changed");
static_assert(offsetof(LogRecord, controlInput) == 96U, "LogRecord.controlInput offset changed");
} // namespace experimentlogger
