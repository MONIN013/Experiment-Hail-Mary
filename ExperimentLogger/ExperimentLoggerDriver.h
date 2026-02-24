///////////////////////////////////////////////////////////////////////////////
// ExperimentLoggerDriver.h

#ifndef __EXPERIMENTLOGGERDRIVER_H__
#define __EXPERIMENTLOGGERDRIVER_H__

#if _MSC_VER > 1000
#pragma once
#endif // _MSC_VER > 1000

#include "TcBase.h"

#define EXPERIMENTLOGGERDRV_NAME        "EXPERIMENTLOGGER"
#define EXPERIMENTLOGGERDRV_Major       1
#define EXPERIMENTLOGGERDRV_Minor       0

#define DEVICE_CLASS CExperimentLoggerDriver

#include "ObjDriver.h"

class CExperimentLoggerDriver : public CObjDriver
{
public:
	virtual IOSTATUS	OnLoad();
	virtual VOID		OnUnLoad();

	//////////////////////////////////////////////////////
	// VxD-Services exported by this driver
	static unsigned long	_cdecl EXPERIMENTLOGGERDRV_GetVersion();
	//////////////////////////////////////////////////////
	
};

Begin_VxD_Service_Table(EXPERIMENTLOGGERDRV)
	VxD_Service( EXPERIMENTLOGGERDRV_GetVersion )
End_VxD_Service_Table


#endif // ifndef __EXPERIMENTLOGGERDRIVER_H__