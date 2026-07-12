///////////////////////////////////////////////////////////////////////////////
// LoggerRecordBuffer.cpp

#include "LoggerRecordBuffer.h"

namespace experimentlogger
{
LoggerRecordBuffer::LoggerRecordBuffer() noexcept
{
	Reset();
}

void LoggerRecordBuffer::Reset() noexcept
{
	m_activeBufferIndex = 0U;
	m_nextSequence = 0U;
	m_recordsAppended = 0U;
	ClearBufferedRecords();
}

void LoggerRecordBuffer::ClearBufferedRecords() noexcept
{
	for (std::uint32_t i = 0U; i < kBufferCount; ++i)
	{
		m_bufferCounts[i] = 0U;
	}
	ClearPendingWrite();
}

bool LoggerRecordBuffer::Append(const LogSample& sample, std::uint64_t timestampStepNs) noexcept
{
	const std::uint32_t bufferIndex = CurrentBufferIndex();
	const std::uint32_t recordIndex = m_bufferCounts[bufferIndex];
	if (recordIndex >= kBufferRecords)
	{
		return false;
	}

	m_buffers[bufferIndex][recordIndex] = BuildLogRecord(m_nextSequence, timestampStepNs, sample);
	m_bufferCounts[bufferIndex] = recordIndex + 1U;
	++m_nextSequence;
	++m_recordsAppended;
	return true;
}

bool LoggerRecordBuffer::HasPendingWrite() const noexcept
{
	return m_pendingWriteRecords > 0U;
}

bool LoggerRecordBuffer::HasBufferedRecords() const noexcept
{
	return (m_bufferCounts[0] > 0U) || (m_bufferCounts[1] > 0U);
}

bool LoggerRecordBuffer::CurrentBufferFull() const noexcept
{
	return CurrentRecordCount() >= kBufferRecords;
}

std::uint32_t LoggerRecordBuffer::CurrentBufferIndex() const noexcept
{
	return m_activeBufferIndex & 0x1U;
}

std::uint32_t LoggerRecordBuffer::InactiveBufferIndex() const noexcept
{
	return CurrentBufferIndex() ^ 0x1U;
}

std::uint32_t LoggerRecordBuffer::CurrentRecordCount() const noexcept
{
	return m_bufferCounts[CurrentBufferIndex()];
}

std::uint32_t LoggerRecordBuffer::BufferRecordCount(std::uint32_t bufferIndex) const noexcept
{
	return (bufferIndex < kBufferCount) ? m_bufferCounts[bufferIndex] : 0U;
}

std::uint32_t LoggerRecordBuffer::PendingRecordCount() const noexcept
{
	return m_pendingWriteRecords;
}

std::uint32_t LoggerRecordBuffer::NextSequence() const noexcept
{
	return m_nextSequence;
}

std::uint32_t LoggerRecordBuffer::RecordsAppended() const noexcept
{
	return m_recordsAppended;
}

const LogRecord& LoggerRecordBuffer::RecordAt(
	std::uint32_t bufferIndex,
	std::uint32_t recordIndex) const noexcept
{
	return m_buffers[bufferIndex][recordIndex];
}

bool LoggerRecordBuffer::BeginWrite(WriteBatch& batch) noexcept
{
	batch = {};
	if (HasPendingWrite())
	{
		return false;
	}

	const std::uint32_t writeIndex = CurrentBufferIndex();
	const std::uint32_t writeCount = m_bufferCounts[writeIndex];
	const std::uint32_t nextIndex = InactiveBufferIndex();
	if (writeCount == 0U || m_bufferCounts[nextIndex] != 0U)
	{
		return false;
	}

	m_pendingWriteBufferIndex = writeIndex;
	m_pendingWriteRecords = writeCount;
	m_activeBufferIndex = nextIndex;
	batch.records = &m_buffers[writeIndex][0];
	batch.recordCount = writeCount;
	batch.bufferIndex = writeIndex;
	return true;
}

void LoggerRecordBuffer::CommitWrite() noexcept
{
	if (!HasPendingWrite())
	{
		return;
	}

	m_bufferCounts[m_pendingWriteBufferIndex] = 0U;
	ClearPendingWrite();
}

bool LoggerRecordBuffer::RollbackWrite() noexcept
{
	if (!HasPendingWrite())
	{
		return false;
	}

	// The pending buffer cannot become active again after the other face has
	// accepted records. Keep the pending state intact so both faces remain drainable.
	if (m_bufferCounts[CurrentBufferIndex()] != 0U)
	{
		return false;
	}

	m_activeBufferIndex = m_pendingWriteBufferIndex;
	ClearPendingWrite();
	return true;
}

void LoggerRecordBuffer::ClearPendingWrite() noexcept
{
	m_pendingWriteBufferIndex = 0U;
	m_pendingWriteRecords = 0U;
}
} // namespace experimentlogger
