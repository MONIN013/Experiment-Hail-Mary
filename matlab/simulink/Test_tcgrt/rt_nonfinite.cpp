/*
 * rt_nonfinite.cpp
 *
 * Academic License - for use in teaching, academic research, and meeting
 * course requirements at degree granting institutions only.  Not for
 * government, commercial, or other organizational use.
 *
 * Code generation for model "Test".
 *
 * Model version              : 1.11
 * Simulink Coder version : 25.1 (R2025a) 21-Nov-2024
 * C++ source code generated on : Tue Feb 24 13:04:49 2026
 *
 * Target selection: TwinCatGrt.tlc
 * Note: GRT includes extra infrastructure and instrumentation for prototyping
 * Embedded hardware selection: Intel->x86-64 (Windows64)
 * Code generation objectives: Unspecified
 * Validation result: Not run
 */

#include "rtwtypes.h"

extern "C"
{

#include "rt_nonfinite.h"

}

#include "limits"
#include "cmath"

extern "C"
{
  real_T rtNaN { -std::numeric_limits<real_T>::quiet_NaN() };

  real_T rtInf { std::numeric_limits<real_T>::infinity() };

  real_T rtMinusInf { -std::numeric_limits<real_T>::infinity() };

  real32_T rtNaNF { -std::numeric_limits<real32_T>::quiet_NaN() };

  real32_T rtInfF { std::numeric_limits<real32_T>::infinity() };

  real32_T rtMinusInfF { -std::numeric_limits<real32_T>::infinity() };
}

extern "C"
{
  /* Test if value is infinite */
  boolean_T rtIsInf(real_T value)
  {
    return std::isinf(value);
  }

  /* Test if single-precision value is infinite */
  boolean_T rtIsInfF(real32_T value)
  {
    return std::isinf(value);
  }

  /* Test if value is not a number */
  boolean_T rtIsNaN(real_T value)
  {
    return std::isnan(value);
  }

  /* Test if single-precision value is not a number */
  boolean_T rtIsNaNF(real32_T value)
  {
    return std::isnan(value);
  }
}
