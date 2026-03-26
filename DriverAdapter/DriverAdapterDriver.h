///////////////////////////////////////////////////////////////////////////////
// DriverAdapterDriver.h

#ifndef __DRIVERADAPTERDRIVER_H__
#define __DRIVERADAPTERDRIVER_H__

#if _MSC_VER > 1000
#pragma once
#endif // _MSC_VER > 1000

#include "TcBase.h"

#define DRIVERADAPTERDRV_NAME        "DRIVERADAPTER"
#define DRIVERADAPTERDRV_Major       1
#define DRIVERADAPTERDRV_Minor       0

#define DEVICE_CLASS CDriverAdapterDriver

#include "ObjDriver.h"

class CDriverAdapterDriver : public CObjDriver
{
public:
	virtual IOSTATUS	OnLoad();
	virtual VOID		OnUnLoad();

	//////////////////////////////////////////////////////
	// VxD-Services exported by this driver
	static unsigned long	_cdecl DRIVERADAPTERDRV_GetVersion();
	//////////////////////////////////////////////////////
	
};

Begin_VxD_Service_Table(DRIVERADAPTERDRV)
	VxD_Service( DRIVERADAPTERDRV_GetVersion )
End_VxD_Service_Table


#endif // ifndef __DRIVERADAPTERDRIVER_H__