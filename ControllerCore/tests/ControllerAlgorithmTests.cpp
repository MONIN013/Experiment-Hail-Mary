#include "ControllerAlgorithm.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>

namespace
{
using Algorithm = controllercore::ControllerAlgorithm;
using Counts = Algorithm::SectionCounts;
using Higs = Algorithm::HigsParameters;
constexpr std::size_t kCapacity = Algorithm::kCoefficientCount;

void Set(double* c, std::size_t row, double b0, double b1, double b2, double a1, double a2)
{
	const std::size_t i = row * Algorithm::kCoefficientsPerSection;
	c[i] = b0; c[i + 1] = b1; c[i + 2] = b2; c[i + 3] = a1; c[i + 4] = a2;
}

void FillIdentity(double* c)
{
	for (std::size_t row = 0; row < Algorithm::kMaxSections; ++row)
		Set(c, row, 1, 0, 0, 0, 0);
}

bool Near(double a, double b, double tolerance = 1e-12)
{
	return std::abs(a - b) <= tolerance * (1.0 + std::abs(b));
}

class Biquad
{
public:
	Biquad() : b0(1), b1(0), b2(0), a1(0), a2(0), s1(0), s2(0) {}
	void SetCoefficients(const double* c, std::size_t row)
	{
		const std::size_t i = row * Algorithm::kCoefficientsPerSection;
		b0 = c[i]; b1 = c[i + 1]; b2 = c[i + 2]; a1 = c[i + 3]; a2 = c[i + 4];
		s1 = s2 = 0;
	}
	double Step(double x)
	{
		const double y = b0 * x + s1;
		const double next1 = b1 * x - a1 * y + s2;
		const double next2 = b2 * x - a2 * y;
		s1 = next1; s2 = next2;
		return y;
	}
private:
	double b0, b1, b2, a1, a2, s1, s2;
};

class LinearCascadeReference
{
public:
	explicit LinearCascadeReference(const double* c)
	{
		lpPre.SetCoefficients(c, 0);
		lpH.SetCoefficients(c, 1);
		lpPost.SetCoefficients(c, 2);
		p.SetCoefficients(c, 3);
		iPre.SetCoefficients(c, 4);
		iH.SetCoefficients(c, 5);
		iPost.SetCoefficients(c, 6);
		post.SetCoefficients(c, 7);
	}
	void Reset(const double* c)
	{
		*this = LinearCascadeReference(c);
	}
	double Step(double ref, double ff, double pos)
	{
		double x = lpPost.Step(lpH.Step(lpPre.Step(ref - pos)));
		const double pOut = p.Step(x);
		const double iOut = iPost.Step(iH.Step(iPre.Step(x)));
		return post.Step(pOut + iOut) + ff;
	}
private:
	Biquad lpPre, lpH, lpPost, p, iPre, iH, iPost, post;
};

bool VerifyLinearCascadeAgainstDirectReference()
{
	const Counts counts{ 1, 1, 1, 1, 1, 1 };
	double c[kCapacity];
	FillIdentity(c);
	// 2nd-order Butterworth low-pass, bilinear transformed at 100 Hz / 8 kHz.
	const double k = std::tan(3.14159265358979323846 * 100.0 / 8000.0);
	const double norm = 1.0 / (1.0 + std::sqrt(2.0) * k + k * k);
	Set(c, 0, 1.1, 0, 0, 0, 0); // lpPre
	Set(c, 1, k * k * norm, 2 * k * k * norm, k * k * norm,
		2 * (k * k - 1) * norm, (1 - std::sqrt(2.0) * k + k * k) * norm); // LP H
	Set(c, 2, 0.9, 0, 0, 0, 0); // lpPost
	// Lead zero at 200 Hz and pole at 1 kHz, bilinear transformed.
	const double kz = std::tan(3.14159265358979323846 * 200.0 / 8000.0);
	const double kp = std::tan(3.14159265358979323846 * 1000.0 / 8000.0);
	Set(c, 3, (1 + kz) / (1 + kp), (kz - 1) / (1 + kp), 0, (kp - 1) / (1 + kp), 0); // P lead
	Set(c, 4, 0.8, 0, 0, 0, 0); // iPre
	Set(c, 5, 0.5, 0.5, 0, -1, 0); // trapezoidal I
	Set(c, 6, 1.25, 0, 0, 0, 0); // iPost
	Set(c, 7, 0.75, 0, 0, 0, 0); // post

	const Higs disabled{ false, 1, 0 };
	Algorithm actual;
	if (!actual.ApplyParameters(c, 8, 1, counts, disabled, disabled)) return false;
	LinearCascadeReference reference(c);
	std::uint32_t random = 0x81234567u;
	for (unsigned n = 0; n < 12000; ++n)
	{
		random = random * 1664525u + 1013904223u;
		const double ref = (static_cast<double>(random >> 8) / 8388608.0) - 1.0;
		random = random * 1664525u + 1013904223u;
		const double ff = 0.1 * (static_cast<double>(random >> 8) / 8388608.0) - 0.05;
		random = random * 1664525u + 1013904223u;
		const double pos = 0.4 * (static_cast<double>(random >> 8) / 8388608.0) - 0.2;
		if (n == 6000)
		{
			actual.Reset();
			reference.Reset(c);
		}
		const double expected = reference.Step(ref, ff, pos);
		const double observed = actual.Step(ref, ff, pos);
		if (!Near(observed, expected, 2e-14)) return false;
	}
	return true;
}

struct HigsReference
{
	double gain;
	double omegaTs;
	double input = 0;
	double output = 0;
	std::uint32_t mode = 0;

	double Step(double x)
	{
		const double candidate = output + omegaTs * x;
		const double boundary = gain * x;
		const bool inside = x >= 0 ? candidate >= 0 && candidate <= boundary
			: candidate >= boundary && candidate <= 0;
		const bool same = (x >= 0 && input >= 0) || (x <= 0 && input <= 0);
		mode = inside ? 1u : (same ? 2u : 3u);
		output = inside ? candidate : (same ? boundary : 0.0);
		input = x;
		return output;
	}
};

bool VerifyTwoIndependentHigsAndDiagnostics()
{
	double c[kCapacity];
	FillIdentity(c);
	// H rows are at 0 and 1. Enabled HIGS skips both ordinary filters.
	Algorithm actual;
	const Counts counts{ 0, 0, 0, 0, 0, 0 };
	const Higs lp{ true, 2.0, 0.5 };
	const Higs i{ true, 1.0, 0.25 };
	if (!actual.ApplyParameters(c, 2, 1, counts, lp, i)) return false;
	HigsReference lpRef{ lp.gain, lp.omegaTs }, iRef{ i.gain, i.omegaTs };
	const double inputs[] = { 0.2963, 0.7126, -2.4259, 2.9048, -3.1113, 1.265,
		-2.0031, -0.8148, -0.8805, -0.2498, 1.0373, 0.0032, -1.9201,
		-1.6814, 1.8825, 1.7748, -0.3933, 0.759, -2.6419, 2.5544,
		-1.9321, -0.6086, -0.9647, 2.0348, 2.5771 };
	std::uint32_t lpModes = 0, iModes = 0;
	for (double x : inputs)
	{
		const double lpOut = lpRef.Step(x);
		const double iOut = iRef.Step(lpOut);
		const double expected = lpOut + iOut;
		lpModes |= 1u << lpRef.mode;
		iModes |= 1u << iRef.mode;
		if (!Near(actual.Step(x, 0, 0), expected)
			|| actual.HigsLpInput() != x || actual.HigsLpOutput() != lpOut
			|| actual.HigsLpMode() != lpRef.mode
			|| actual.HigsIInput() != lpOut || actual.HigsIOutput() != iOut
			|| actual.HigsIMode() != iRef.mode)
			return false;
	}
	if ((lpModes & 0x0eu) != 0x0eu || (iModes & 0x0eu) != 0x0eu) return false;
	// The same input drives separate controller instances without sharing state.
	Algorithm other;
	if (!other.ApplyParameters(c, 2, 1, counts, i, lp)) return false;
	const double lpBefore = actual.HigsLpOutput();
	const double iBefore = actual.HigsIOutput();
	return Near(other.Step(1, 0, 0), 0.375)
		&& Near(other.HigsLpOutput(), 0.25)
		&& Near(other.HigsIOutput(), 0.125)
		&& actual.HigsLpOutput() == lpBefore && actual.HigsIOutput() == iBefore;
}

bool VerifyLinearModeDiagnosticsAndReset()
{
	double c[kCapacity];
	FillIdentity(c);
	const Counts counts{ 0, 0, 0, 0, 0, 0 };
	Set(c, 0, 3, 0, 0, 0, 0);
	Set(c, 1, 2, 0, 0, 0, 0);
	const Higs linear{ false, 1, 0 };
	Algorithm actual;
	if (!actual.ApplyParameters(c, 2, 4, counts, linear, linear)
		|| actual.Step(1, 0, 0) != 9
		|| actual.HigsLpInput() != 1 || actual.HigsLpOutput() != 3 || actual.HigsLpMode() != 0
		|| actual.HigsIInput() != 3 || actual.HigsIOutput() != 6 || actual.HigsIMode() != 0)
		return false;
	actual.Reset();
	return actual.HigsLpInput() == 0 && actual.HigsLpOutput() == 0 && actual.HigsLpMode() == 0
		&& actual.HigsIInput() == 0 && actual.HigsIOutput() == 0 && actual.HigsIMode() == 0
		&& actual.Step(1, 0, 0) == 9;
}

bool VerifyRejectedParametersPreserveActiveState()
{
	double c[kCapacity];
	FillIdentity(c);
	Set(c, 3, 2, 0, 0, 0, 0);
	Set(c, 5, 0, 0, 0, 0, 0);
	const Counts counts{ 1, 1, 1, 1, 1, 1 };
	const Higs disabled{ false, 1, 0 };
	Algorithm actual;
	if (!actual.ApplyParameters(c, 8, 10, counts, disabled, disabled)) return false;
	const double nan = std::numeric_limits<double>::quiet_NaN();
	const Higs invalid[] = {
		{ false, 0, 0 }, { false, -1, 0 }, { false, nan, 0 }, { false, 1, nan },
		{ false, 1, -0.1 }, { true, 1, 0 }, { true, 1, 2 }, { true, nan, 0.1 }
	};
	for (std::uint32_t n = 0; n < sizeof(invalid) / sizeof(invalid[0]); ++n)
	{
		if (actual.ApplyParameters(c, 8, 11 + n, counts, invalid[n], disabled)
			|| actual.AppliedRevision() != 10 || actual.LastSeenRevision() != 11 + n
			|| actual.ParameterErrorCode() != Algorithm::ParameterErrorHigsParameters
			|| actual.Step(1, 0, 0) != 2)
			return false;
	}

	for (std::uint32_t n = 0; n < sizeof(invalid) / sizeof(invalid[0]); ++n)
	{
		if (actual.ApplyParameters(c, 8, 40 + n, counts, disabled, invalid[n])
			|| actual.AppliedRevision() != 10 || actual.LastSeenRevision() != 40 + n
			|| actual.ParameterErrorCode() != Algorithm::ParameterErrorHigsParameters
			|| actual.Step(1, 0, 0) != 2)
			return false;
	}

	const Counts tooMany{ UINT32_MAX, UINT32_MAX, UINT32_MAX, UINT32_MAX, UINT32_MAX, UINT32_MAX };
	if (actual.ApplyParameters(c, UINT32_MAX, 30, tooMany, disabled, disabled)
		|| actual.ParameterErrorCode() != Algorithm::ParameterErrorSectionCount) return false;
	if (actual.ApplyParameters(c, 7, 31, counts, disabled, disabled)
		|| actual.ParameterErrorCode() != Algorithm::ParameterErrorSectionCount) return false;
	c[0] = nan;
	return !actual.ApplyParameters(c, 8, 32, counts, disabled, disabled)
		&& actual.AppliedRevision() == 10
		&& actual.ParameterErrorCode() == Algorithm::ParameterErrorNonFiniteCoefficient
		&& actual.Step(1, 0, 0) == 2;
}

bool VerifyRevisionCommitResetsAllStageState()
{
	double c[kCapacity];
	FillIdentity(c);
	const Counts counts{ 1, 1, 1, 1, 1, 1 };
	Set(c, 3, 1, 0.5, 0, 0, 0);
	Set(c, 5, 0, 0, 0, 0, 0);
	const Higs disabled{ false, 1, 0 };
	Algorithm actual;
	if (!actual.ApplyParameters(c, 8, 7, counts, disabled, disabled)
		|| actual.Step(1, 0, 0) != 1 || actual.Step(0, 0, 0) != 0.5)
		return false;
	Set(c, 3, 2, 0, 0, 0, 0);
	return actual.ApplyParameters(c, 8, 8, counts, disabled, disabled)
		&& actual.AppliedRevision() == 8 && actual.ProcessedRevision() == 8
		&& actual.Step(0, 0, 0) == 0;
}

bool VerifyOverflowFaultRecovery()
{
	const double maximum = std::numeric_limits<double>::max();
	const Counts noSections{ 0, 0, 0, 0, 0, 0 };
	const Higs enabled{ true, 2, 0.5 };
	double c[kCapacity];
	FillIdentity(c);
	Algorithm higs;
	if (!higs.ApplyParameters(c, 2, 1, noSections, enabled, enabled)
		|| higs.Step(maximum, 0, 0) != 0
		|| higs.HigsLpInput() != 0 || higs.HigsLpOutput() != 0 || higs.HigsLpMode() != 0
		|| higs.Step(1, 0, 0) != 0.75)
		return false;

	const Counts lpOnly{ 0, 0, 0, 0, 0, 0 };
	const Higs disabled{ false, 1, 0 };
	Set(c, 0, 0, maximum, 0, -1, 0);
	Algorithm biquad;
	if (!biquad.ApplyParameters(c, 2, 1, lpOnly, disabled, disabled)
		|| biquad.Step(1, 0, 0) != 0
		|| biquad.Step(1, 0, 0) != 0
		|| biquad.Step(0, 0, 0) != 0)
		return false;

	const Counts pOnly{ 0, 0, 1, 0, 0, 0 };
	FillIdentity(c);
	Set(c, 1, maximum, 0.5, 0, 0, 0);
	Algorithm finalOverflow;
	return finalOverflow.ApplyParameters(c, 3, 1, pOnly, disabled, disabled)
		&& finalOverflow.Step(1, maximum, 0) == 0
		&& finalOverflow.Step(0, 0, 0) == 0.5;
}

bool VerifyNonfiniteInputDoesNotChangeHigsState()
{
	double c[kCapacity];
	FillIdentity(c);
	const Counts counts{ 0, 0, 0, 0, 0, 0 };
	const Higs enabled{ true, 1, 0.25 };
	Algorithm actual;
	if (!actual.ApplyParameters(c, 2, 1, counts, enabled, enabled)
		|| actual.Step(1, 0, 0) != 0.3125) return false;
	if (actual.Step(std::numeric_limits<double>::quiet_NaN(), 0, 0) != 0) return false;
	return actual.HigsLpInput() == 1 && actual.HigsLpOutput() == 0.25
		&& actual.HigsIInput() == 0.25 && actual.HigsIOutput() == 0.0625
		&& actual.Step(1, 0, 0) == 0.6875;
}

bool VerifyIdentityDefaultsAndErrors()
{
	Algorithm fresh;
	if (fresh.Step(2, 0.25, 0.5) != 1.75) return false;
	if (Algorithm::ComputeError(2, 0.5) != 1.5
		|| Algorithm::ComputeError(std::numeric_limits<double>::infinity(), 0) != 0)
		return false;
	const Counts counts{ 0, 0, 0, 0, 0, 0 };
	const Higs disabled{ false, 1, 0 };
	return !fresh.ApplyParameters(nullptr, 2, 1, counts, disabled, disabled)
		&& fresh.ParameterErrorCode() == Algorithm::ParameterErrorNonFiniteCoefficient;
}
bool Run(const char* name, bool (*test)())
{
	if (test()) return true;
	std::cerr << name << " failed\n";
	return false;
}
} // namespace

int main()
{
	if (!Run("LinearCascadeAgainstDirectReference", VerifyLinearCascadeAgainstDirectReference)
		|| !Run("TwoIndependentHigsAndDiagnostics", VerifyTwoIndependentHigsAndDiagnostics)
		|| !Run("LinearModeDiagnosticsAndReset", VerifyLinearModeDiagnosticsAndReset)
		|| !Run("RejectedParametersPreserveActiveState", VerifyRejectedParametersPreserveActiveState)
		|| !Run("RevisionCommitResetsAllStageState", VerifyRevisionCommitResetsAllStageState)
		|| !Run("OverflowFaultRecovery", VerifyOverflowFaultRecovery)
		|| !Run("NonfiniteInputDoesNotChangeHigsState", VerifyNonfiniteInputDoesNotChangeHigsState)
		|| !Run("IdentityDefaultsAndErrors", VerifyIdentityDefaultsAndErrors))
	{
		return 1;
	}

	std::cout << "ControllerAlgorithm two-HIGS cascade tests passed\n";
	return 0;
}