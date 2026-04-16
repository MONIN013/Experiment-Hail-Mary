/*
 * Test.h
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

#ifndef Test_h_
#define Test_h_
#include <cmath>
#include "rtwtypes.h"
#include "rtw_continuous.h"
#include "rtw_solver.h"
#include "rt_logging.h"
#include "rt_nonfinite.h"
#include "TcMatFileStream.h"
#include "string.h"
#include "Test_types.h"
#include <cfloat>
#include <cstring>

/* Macros for accessing real-time model data structure */
#ifndef rtmGetFinalTime
#define rtmGetFinalTime(rtm)           ((rtm)->Timing.tFinal)
#endif

#ifndef rtmGetRTWLogInfo
#define rtmGetRTWLogInfo(rtm)          ((rtm)->rtwLogInfo)
#endif

#ifndef rtmGetErrorStatus
#define rtmGetErrorStatus(rtm)         ((rtm)->errorStatus)
#endif

#ifndef rtmSetErrorStatus
#define rtmSetErrorStatus(rtm, val)    ((rtm)->errorStatus = (val))
#endif

#ifndef rtmGetStopRequested
#define rtmGetStopRequested(rtm)       ((rtm)->Timing.stopRequestedFlag)
#endif

#ifndef rtmSetStopRequested
#define rtmSetStopRequested(rtm, val)  ((rtm)->Timing.stopRequestedFlag = (val))
#endif

#ifndef rtmGetStopRequestedPtr
#define rtmGetStopRequestedPtr(rtm)    (&((rtm)->Timing.stopRequestedFlag))
#endif

#ifndef rtmGetT
#define rtmGetT(rtm)                   ((rtm)->Timing.taskTime0)
#endif

#ifndef rtmGetTFinal
#define rtmGetTFinal(rtm)              ((rtm)->Timing.tFinal)
#endif

#ifndef rtmGetTPtr
#define rtmGetTPtr(rtm)                (&(rtm)->Timing.taskTime0)
#endif

/* Block signals (default storage) */
struct B_Test_T {
  real_T ControlInput;                 /* '<S1>/ControlInput' */
  real_T LoadActualPosition1;          /* '<S2>/LoadActualPosition1' */
  real_T MotorActualPosition;          /* '<S2>/MotorActualPosition' */
  real_T FeedForward;                  /* '<S3>/FeedForward' */
  real_T Reference;                    /* '<S3>/Reference' */
  real_T Sum;                          /* '<Root>/Sum' */
  real_T Sum1;                         /* '<Root>/Sum1' */
  real_T TmpSignalConversionAtTwinCATFil[6];
  real_T FB_flag;                      /* '<Root>/FB_flag' */
};

/* Block states (default storage) for system '<Root>' */
struct DW_Test_T {
  real_T TwinCATFileWriter_DWORK1;     /* '<Root>/TwinCAT File Writer' */
  void *TwinCATFileWriter_PWORK;       /* '<Root>/TwinCAT File Writer' */
  void *ControlInput_PWORK;            /* '<S1>/ControlInput' */
  void *Error_PWORK;                   /* '<S1>/Error' */
  void *LoadActualPosition1_PWORK;     /* '<S2>/LoadActualPosition1' */
  void *MotorActualPosition_PWORK;     /* '<S2>/MotorActualPosition' */
  void *TargetTorque_PWORK;            /* '<S2>/TargetTorque' */
  void *FeedForward_PWORK;             /* '<S3>/FeedForward' */
  void *Reference_PWORK;               /* '<S3>/Reference' */
};

/* Parameters (default storage) */
struct P_Test_T_ {
  int32_T TwinCATFileWriter_MaxFileCount;
                               /* Mask Parameter: TwinCATFileWriter_MaxFileCount
                                * Referenced by: '<Root>/TwinCAT File Writer'
                                */
  uint32_T TwinCATFileWriter_MaxFileByteSi;
                              /* Mask Parameter: TwinCATFileWriter_MaxFileByteSi
                               * Referenced by: '<Root>/TwinCAT File Writer'
                               */
  real_T FB_flag_Gain;                 /* Expression: 1
                                        * Referenced by: '<Root>/FB_flag'
                                        */
  boolean_T SwitchFB_Value;            /* Computed Parameter: SwitchFB_Value
                                        * Referenced by: '<Root>/SwitchFB'
                                        */
  boolean_T exp_Value;                 /* Computed Parameter: exp_Value
                                        * Referenced by: '<Root>/exp'
                                        */
};

/* Real-time Model Data Structure */
struct tag_RTM_Test_T {
  const char_T *errorStatus;
  RTWLogInfo *rtwLogInfo;

  /*
   * Timing:
   * The following substructure contains information regarding
   * the timing information for the model.
   */
  struct {
    time_T taskTime0;
    uint32_T clockTick0;
    uint32_T clockTickH0;
    time_T stepSize0;
    time_T tFinal;
    boolean_T stopRequestedFlag;
  } Timing;
};

/* Block parameters (default storage) */
#ifdef __cplusplus

extern "C"
{

#endif

  extern P_Test_T Test_P;

#ifdef __cplusplus

}

#endif

/* Block signals (default storage) */
#ifdef __cplusplus

extern "C"
{

#endif

  extern struct B_Test_T Test_B;

#ifdef __cplusplus

}

#endif

/* Block states (default storage) */
extern struct DW_Test_T Test_DW;

#ifdef __cplusplus

extern "C"
{

#endif

  /* Model entry point functions */
  extern void Test_initialize(void);
  extern void Test_step(void);
  extern void Test_terminate(void);

#ifdef __cplusplus

}

#endif

/* Real-time Model object */
#ifdef __cplusplus

extern "C"
{

#endif

  extern RT_MODEL_Test_T *const Test_M;

#ifdef __cplusplus

}

#endif

/*-
 * The generated code includes comments that allow you to trace directly
 * back to the appropriate location in the model.  The basic format
 * is <system>/block_name, where system is the system number (uniquely
 * assigned by Simulink) and block_name is the name of the block.
 *
 * Use the MATLAB hilite_system command to trace the generated code back
 * to the model.  For example,
 *
 * hilite_system('<S3>')    - opens system 3
 * hilite_system('<S3>/Kp') - opens and selects block Kp which resides in S3
 *
 * Here is the system hierarchy for this model
 *
 * '<Root>' : 'Test'
 * '<S1>'   : 'Test/Controller'
 * '<S2>'   : 'Test/Plant'
 * '<S3>'   : 'Test/Reference'
 */
#endif                                 /* Test_h_ */
