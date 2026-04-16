/*
 * Test.cpp
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

#include "Test.h"
#include "Test_private.h"
#include <cstring>

/* Block signals (default storage) */
B_Test_T Test_B;

/* Block states (default storage) */
DW_Test_T Test_DW;

/* Real-time model */
RT_MODEL_Test_T Test_M_{ };

RT_MODEL_Test_T *const Test_M{ &Test_M_ };

/* Model step function */
void Test_step(void)
{
  /* S-Function (TcModuleInOut): '<S1>/ControlInput' */
  if (Test_DW.ControlInput_PWORK != NULL) {
    Test_B.ControlInput = *((real_T*)Test_DW.ControlInput_PWORK);
  }

  /* S-Function (TcModuleInOut): '<S2>/LoadActualPosition1' */
  if (Test_DW.LoadActualPosition1_PWORK != NULL) {
    Test_B.LoadActualPosition1 = *((real_T*)Test_DW.LoadActualPosition1_PWORK);
  }

  /* S-Function (TcModuleInOut): '<S2>/MotorActualPosition' */
  if (Test_DW.MotorActualPosition_PWORK != NULL) {
    Test_B.MotorActualPosition = *((real_T*)Test_DW.MotorActualPosition_PWORK);
  }

  /* Switch: '<Root>/Switch' incorporates:
   *  Constant: '<Root>/SwitchFB'
   */
  if (Test_P.SwitchFB_Value) {
    /* Gain: '<Root>/FB_flag' */
    Test_B.FB_flag = Test_B.LoadActualPosition1;
  } else {
    /* Gain: '<Root>/FB_flag' */
    Test_B.FB_flag = Test_B.MotorActualPosition;
  }

  /* End of Switch: '<Root>/Switch' */

  /* Gain: '<Root>/FB_flag' */
  Test_B.FB_flag *= Test_P.FB_flag_Gain;

  /* S-Function (TcModuleInOut): '<S3>/FeedForward' */
  if (Test_DW.FeedForward_PWORK != NULL) {
    Test_B.FeedForward = *((real_T*)Test_DW.FeedForward_PWORK);
  }

  /* S-Function (TcModuleInOut): '<S3>/Reference' */
  if (Test_DW.Reference_PWORK != NULL) {
    Test_B.Reference = *((real_T*)Test_DW.Reference_PWORK);
  }

  /* Sum: '<Root>/Sum' */
  Test_B.Sum = Test_B.Reference - Test_B.FB_flag;

  /* Sum: '<Root>/Sum1' */
  Test_B.Sum1 = Test_B.FeedForward + Test_B.ControlInput;

  /* SignalConversion generated from: '<Root>/TwinCAT File Writer' */
  Test_B.TmpSignalConversionAtTwinCATFil[0] = Test_B.MotorActualPosition;
  Test_B.TmpSignalConversionAtTwinCATFil[1] = Test_B.LoadActualPosition1;
  Test_B.TmpSignalConversionAtTwinCATFil[2] = Test_B.Reference;
  Test_B.TmpSignalConversionAtTwinCATFil[3] = Test_B.FeedForward;
  Test_B.TmpSignalConversionAtTwinCATFil[4] = Test_B.Sum1;
  Test_B.TmpSignalConversionAtTwinCATFil[5] = Test_B.Sum;

  /* Update for S-Function (TcFileWriter): '<Root>/TwinCAT File Writer' incorporates:
   *  Constant: '<Root>/exp'
   */
  Test_DW.TwinCATFileWriter_DWORK1 = Test_M->Timing.taskTime0;
  if (Test_DW.TwinCATFileWriter_PWORK) {
    if (Test_P.exp_Value)
      tc_matfilestream_disable(Test_DW.TwinCATFileWriter_PWORK);
    else
      tc_matfilestream_write(Test_DW.TwinCATFileWriter_PWORK,
        &Test_B.TmpSignalConversionAtTwinCATFil[0], 6*sizeof(real_T) + 8,
        Test_P.TwinCATFileWriter_MaxFileByteSi,
        Test_P.TwinCATFileWriter_MaxFileCount);
  }

  /* Update for S-Function (TcModuleInOut): '<S1>/Error' */
  if (Test_DW.Error_PWORK != NULL) {
    *((real_T*)Test_DW.Error_PWORK) = Test_B.Sum;
  }

  /* Update for S-Function (TcModuleInOut): '<S2>/TargetTorque' */
  if (Test_DW.TargetTorque_PWORK != NULL) {
    *((real_T*)Test_DW.TargetTorque_PWORK) = Test_B.Sum1;
  }

  /* Matfile logging */
  rt_UpdateTXYLogVars(Test_M->rtwLogInfo, (&Test_M->Timing.taskTime0));

  /* signal main to stop simulation */
  {                                    /* Sample time: [0.001s, 0.0s] */
    if ((rtmGetTFinal(Test_M)!=-1) &&
        !((rtmGetTFinal(Test_M)-Test_M->Timing.taskTime0) >
          Test_M->Timing.taskTime0 * (DBL_EPSILON))) {
      rtmSetErrorStatus(Test_M, "Simulation finished");
    }
  }

  /* Update absolute time for base rate */
  /* The "clockTick0" counts the number of times the code of this task has
   * been executed. The absolute time is the multiplication of "clockTick0"
   * and "Timing.stepSize0". Size of "clockTick0" ensures timer will not
   * overflow during the application lifespan selected.
   * Timer of this task consists of two 32 bit unsigned integers.
   * The two integers represent the low bits Timing.clockTick0 and the high bits
   * Timing.clockTickH0. When the low bit overflows to 0, the high bits increment.
   */
  if (!(++Test_M->Timing.clockTick0)) {
    ++Test_M->Timing.clockTickH0;
  }

  Test_M->Timing.taskTime0 = Test_M->Timing.clockTick0 *
    Test_M->Timing.stepSize0 + Test_M->Timing.clockTickH0 *
    Test_M->Timing.stepSize0 * 4294967296.0;
}

/* Model initialize function */
void Test_initialize(void)
{
  /* Registration code */
  rtmSetTFinal(Test_M, -1);
  Test_M->Timing.stepSize0 = 0.001;

  /* Setup for data logging */
  {
    static RTWLogInfo rt_DataLoggingInfo;
    rt_DataLoggingInfo.loggingInterval = (nullptr);
    Test_M->rtwLogInfo = &rt_DataLoggingInfo;
  }

  /* Setup for data logging */
  {
    rtliSetLogXSignalInfo(Test_M->rtwLogInfo, (nullptr));
    rtliSetLogXSignalPtrs(Test_M->rtwLogInfo, (nullptr));
    rtliSetLogT(Test_M->rtwLogInfo, "tout");
    rtliSetLogX(Test_M->rtwLogInfo, "");
    rtliSetLogXFinal(Test_M->rtwLogInfo, "");
    rtliSetLogVarNameModifier(Test_M->rtwLogInfo, "rt_");
    rtliSetLogFormat(Test_M->rtwLogInfo, 4);
    rtliSetLogMaxRows(Test_M->rtwLogInfo, 0);
    rtliSetLogDecimation(Test_M->rtwLogInfo, 1);
    rtliSetLogY(Test_M->rtwLogInfo, "");
    rtliSetLogYSignalInfo(Test_M->rtwLogInfo, (nullptr));
    rtliSetLogYSignalPtrs(Test_M->rtwLogInfo, (nullptr));
  }

  /* block I/O */
  (void) std::memset((static_cast<void *>(&Test_B)), 0,
                     sizeof(B_Test_T));

  /* states (dwork) */
  (void) std::memset(static_cast<void *>(&Test_DW), 0,
                     sizeof(DW_Test_T));

  /* Matfile logging */
  rt_StartDataLoggingWithStartTime(Test_M->rtwLogInfo, 0.0, rtmGetTFinal(Test_M),
    Test_M->Timing.stepSize0, (&rtmGetErrorStatus(Test_M)));

  /* Start for S-Function (TcFileWriter): '<Root>/TwinCAT File Writer' incorporates:
   *  Constant: '<Root>/exp'
   */
  {
    Test_DW.TwinCATFileWriter_PWORK = tc_matfilestream_create(
      "C:\\experiment.mat");
    LONG dims[] = { 1, 1 };

    void* h = tc_matfilestream_configure_struct(Test_DW.TwinCATFileWriter_PWORK,
      "tc_yout", 2, dims, sizeof(real_T) + 8);

    // add timestamp member
    LONG timeDims[] = { 1, 1 };

    tc_matfilestream_add_matrix(Test_DW.TwinCATFileWriter_PWORK, h, "time", 2,
      timeDims, 8, 0, 0, false, &Test_DW.TwinCATFileWriter_DWORK1);

    // add data member
    LONG dataDims[] = { 6, 1 };

    tc_matfilestream_add_matrix(Test_DW.TwinCATFileWriter_PWORK, h, "data", 2,
      dataDims, sizeof(real_T), 0, 0, 0, 0);
  }
}

/* Model terminate function */
void Test_terminate(void)
{
  /* Terminate for S-Function (TcFileWriter): '<Root>/TwinCAT File Writer' incorporates:
   *  Constant: '<Root>/exp'
   */
  tc_matfilestream_close(Test_DW.TwinCATFileWriter_PWORK);
}
