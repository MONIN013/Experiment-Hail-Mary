#include "LoggerRecord.h"
#include "LoggerRecordBuffer.h"

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <memory>

namespace
{
bool VerifyRecordFields()
{
	const experimentlogger::LogSample sample = {
		1.0,
		2.0,
		3.0,
		4.0,
		5.0,
		6.0,
		7.0,
		8.0,
		9.0,
		10.0,
		11.0
	};
	const experimentlogger::LogRecord record = experimentlogger::BuildLogRecord(4U, 125000U, sample);
	return record.seq == 4U
		&& record.reservedPad0 == experimentlogger::kLogSchemaVersion
		&& record.tNs == 500000U
		&& record.motorPosition == 1.0
		&& record.motorVelocity == 2.0
		&& record.motorCurrentAct == 3.0
		&& record.loadPosition == 4.0
		&& record.loadVelocity == 5.0
		&& record.currentCmd == 6.0
		&& record.error == 7.0
		&& record.refValue == 8.0
		&& record.ffValue == 9.0
		&& record.distValue == 10.0
		&& record.controlInput == 11.0;
}

bool VerifySerializedOffsets()
{
	const experimentlogger::LogSample sample = {
		-1.0,
		-2.0,
		-3.0,
		-4.0,
		-5.0,
		-6.0,
		-7.0,
		-8.0,
		-9.0,
		-10.0,
		-11.0
	};
	const experimentlogger::LogRecord record = experimentlogger::BuildLogRecord(7U, 10U, sample);
	std::uint8_t bytes[sizeof(record)] = {};
	std::memcpy(bytes, &record, sizeof(record));

	std::uint32_t seq = 0;
	std::uint32_t schemaVersion = 0;
	std::uint64_t timestamp = 0;
	double controlInput = 0.0;
	std::memcpy(&seq, bytes + 0U, sizeof(seq));
	std::memcpy(&schemaVersion, bytes + 4U, sizeof(schemaVersion));
	std::memcpy(&timestamp, bytes + 8U, sizeof(timestamp));
	std::memcpy(&controlInput, bytes + 96U, sizeof(controlInput));
	return sizeof(record) == 104U
		&& seq == 7U
		&& schemaVersion == 2U
		&& timestamp == 70U
		&& controlInput == -11.0;
}

experimentlogger::LogSample MakeSample(double base) noexcept
{
	return {
		base + 0.0,
		base + 1.0,
		base + 2.0,
		base + 3.0,
		base + 4.0,
		base + 5.0,
		base + 6.0,
		base + 7.0,
		base + 8.0,
		base + 9.0,
		base + 10.0
	};
}

bool VerifyPingPongBufferLifecycle()
{
	auto buffer = std::make_unique<experimentlogger::LoggerRecordBuffer>();
	for (std::uint32_t i = 0U; i < experimentlogger::LoggerRecordBuffer::kBufferRecords; ++i)
	{
		if (!buffer->Append(MakeSample(static_cast<double>(i)), 125000U))
		{
			return false;
		}
	}

	if (!buffer->CurrentBufferFull()
		|| buffer->CurrentBufferIndex() != 0U
		|| buffer->RecordsAppended() != experimentlogger::LoggerRecordBuffer::kBufferRecords
		|| buffer->NextSequence() != experimentlogger::LoggerRecordBuffer::kBufferRecords
		|| buffer->RecordAt(0U, 7999U).seq != 7999U
		|| buffer->RecordAt(0U, 7999U).tNs != (7999ULL * 125000ULL)
		|| buffer->Append(MakeSample(0.0), 125000U))
	{
		return false;
	}

	experimentlogger::LoggerRecordBuffer::WriteBatch firstBatch = {};
	if (!buffer->BeginWrite(firstBatch)
		|| firstBatch.bufferIndex != 0U
		|| firstBatch.recordCount != experimentlogger::LoggerRecordBuffer::kBufferRecords
		|| firstBatch.records == nullptr
		|| !buffer->HasPendingWrite()
		|| buffer->CurrentBufferIndex() != 1U)
	{
		return false;
	}

	for (std::uint32_t i = 0U; i < 3U; ++i)
	{
		if (!buffer->Append(MakeSample(9000.0 + i), 125000U))
		{
			return false;
		}
	}
	experimentlogger::LoggerRecordBuffer::WriteBatch rejectedBatch = {};
	if (buffer->BeginWrite(rejectedBatch)
		|| buffer->RollbackWrite()
		|| !buffer->HasPendingWrite()
		|| buffer->BufferRecordCount(0U) != experimentlogger::LoggerRecordBuffer::kBufferRecords
		|| buffer->BufferRecordCount(1U) != 3U)
	{
		return false;
	}

	buffer->CommitWrite();
	if (buffer->HasPendingWrite()
		|| buffer->BufferRecordCount(0U) != 0U
		|| buffer->CurrentRecordCount() != 3U
		|| buffer->RecordsAppended() != 8003U)
	{
		return false;
	}

	experimentlogger::LoggerRecordBuffer::WriteBatch secondBatch = {};
	if (!buffer->BeginWrite(secondBatch) || secondBatch.bufferIndex != 1U || secondBatch.recordCount != 3U)
	{
		return false;
	}
	if (!buffer->RollbackWrite()
		|| buffer->HasPendingWrite()
		|| buffer->CurrentBufferIndex() != 1U
		|| buffer->CurrentRecordCount() != 3U)
	{
		return false;
	}

	if (!buffer->BeginWrite(secondBatch))
	{
		return false;
	}
	buffer->CommitWrite();
	return !buffer->HasBufferedRecords()
		&& !buffer->HasPendingWrite()
		&& buffer->RecordsAppended() == 8003U
		&& buffer->NextSequence() == 8003U;
}

bool VerifyClearAndResetSemantics()
{
	auto buffer = std::make_unique<experimentlogger::LoggerRecordBuffer>();
	if (!buffer->Append(MakeSample(1.0), 10U))
	{
		return false;
	}
	buffer->ClearBufferedRecords();
	if (buffer->HasBufferedRecords()
		|| buffer->HasPendingWrite()
		|| buffer->RecordsAppended() != 1U
		|| buffer->NextSequence() != 1U)
	{
		return false;
	}

	buffer->Reset();
	return !buffer->HasBufferedRecords()
		&& !buffer->HasPendingWrite()
		&& buffer->CurrentBufferIndex() == 0U
		&& buffer->RecordsAppended() == 0U
		&& buffer->NextSequence() == 0U;
}
} // namespace

int main()
{
	if (!VerifyRecordFields()
		|| !VerifySerializedOffsets()
		|| !VerifyPingPongBufferLifecycle()
		|| !VerifyClearAndResetSemantics())
	{
		return 1;
	}

	std::cout << "LoggerRecord tests passed\n";
	return 0;
}
