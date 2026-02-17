///////////////////////////////////////////////////////////////////////////////
// VirtualMotorCoreDriver.h

#ifndef __VIRTUALMOTORCOREDRIVER_H__
#define __VIRTUALMOTORCOREDRIVER_H__

#if _MSC_VER > 1000
#pragma once
#endif // _MSC_VER > 1000

#include "TcBase.h"

#define VIRTUALMOTORCOREDRV_NAME        "VIRTUALMOTORCORE"
#define VIRTUALMOTORCOREDRV_Major       1
#define VIRTUALMOTORCOREDRV_Minor       0

#define DEVICE_CLASS CVirtualMotorCoreDriver

#include "ObjDriver.h"

class CVirtualMotorCoreDriver : public CObjDriver
{
public:
	virtual IOSTATUS	OnLoad();
	virtual VOID		OnUnLoad();

	//////////////////////////////////////////////////////
	// VxD-Services exported by this driver
	static unsigned long	_cdecl VIRTUALMOTORCOREDRV_GetVersion();
	//////////////////////////////////////////////////////
	
};

Begin_VxD_Service_Table(VIRTUALMOTORCOREDRV)
	VxD_Service( VIRTUALMOTORCOREDRV_GetVersion )
End_VxD_Service_Table


#endif // ifndef __VIRTUALMOTORCOREDRIVER_H__