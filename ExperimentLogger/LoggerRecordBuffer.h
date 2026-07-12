///////////////////////////////////////////////////////////////////////////////
// LoggerRecordBuffer.h

#pragma once

#include "LoggerRecord.h"

#include <cstdint>

namespace experimentlogger
{
class LoggerRecordBuffer final
{
public:
	static constexpr std::uint32_t kBufferCount = 2U;
	static constexpr std::uint32_t kBufferRecords = 8000U;

	struct WriteBatch
	{
		const LogRecord* records;
		std::uint32_t recordCount;
		std::uint32_t bufferIndex;
	};

	LoggerRecordBuffer() noexcept;
	LoggerRecordBuffer(const LoggerRecordBuffer&) = delete;
	LoggerRecordBuffer& operator=(const LoggerRecordBuffer&) = delete;

	void Reset() noexcept;
	void ClearBufferedRecords() noexcept;
	bool Append(const LogSample& sample, std::uint64_t timestampStepNs) noexcept;

	bool HasPendingWrite() const noexcept;
	bool HasBufferedRecords() const noexcept;
	bool CurrentBufferFull() const noexcept;
	std::uint32_t CurrentBufferIndex() const noexcept;
	std::uint32_t InactiveBufferIndex() const noexcept;
	std::uint32_t CurrentRecordCount() const noexcept;
	std::uint32_t BufferRecordCount(std::uint32_t bufferIndex) const noexcept;
	std::uint32_t PendingRecordCount() const noexcept;
	std::uint32_t NextSequence() const noexcept;
	std::uint32_t RecordsAppended() const noexcept;
	const LogRecord& RecordAt(std::uint32_t bufferIndex, std::uint32_t recordIndex) const noexcept;

	bool BeginWrite(WriteBatch& batch) noexcept;
	void CommitWrite() noexcept;
	bool RollbackWrite() noexcept;

private:
	void ClearPendingWrite() noexcept;

	LogRecord m_buffers[kBufferCount][kBufferRecords];
	std::uint32_t m_bufferCounts[kBufferCount];
	std::uint32_t m_activeBufferIndex;
	std::uint32_t m_pendingWriteBufferIndex;
	std::uint32_t m_pendingWriteRecords;
	std::uint32_t m_nextSequence;
	std::uint32_t m_recordsAppended;
};
} // namespace experimentlogger
