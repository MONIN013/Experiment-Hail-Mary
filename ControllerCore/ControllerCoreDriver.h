///////////////////////////////////////////////////////////////////////////////
// ControllerCoreDriver.h

#ifndef __CONTROLLERCOREDRIVER_H__
#define __CONTROLLERCOREDRIVER_H__

#if _MSC_VER > 1000
#pragma once
#endif // _MSC_VER > 1000

#include "TcBase.h"

#define CONTROLLERCOREDRV_NAME        "CONTROLLERCORE"
#define CONTROLLERCOREDRV_Major       1
#define CONTROLLERCOREDRV_Minor       0

#define DEVICE_CLASS CControllerCoreDriver

#include "ObjDriver.h"

class CControllerCoreDriver : public CObjDriver
{
public:
	virtual IOSTATUS	OnLoad();
	virtual VOID		OnUnLoad();

	//////////////////////////////////////////////////////
	// VxD-Services exported by this driver
	static unsigned long	_cdecl CONTROLLERCOREDRV_GetVersion();
	//////////////////////////////////////////////////////
	
};

Begin_VxD_Service_Table(CONTROLLERCOREDRV)
	VxD_Service( CONTROLLERCOREDRV_GetVersion )
End_VxD_Service_Table


#endif // ifndef __CONTROLLERCOREDRIVER_H__