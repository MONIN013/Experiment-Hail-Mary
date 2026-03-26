///////////////////////////////////////////////////////////////////////////////
// DriverAdapterDriver.cpp
#include "TcPch.h"
#pragma hdrstop

#include "DriverAdapterDriver.h"
#include "DriverAdapterClassFactory.h"

DECLARE_GENERIC_DEVICE(DRIVERADAPTERDRV)

IOSTATUS CDriverAdapterDriver::OnLoad( )
{
	TRACE(_T("CObjClassFactory::OnLoad()\n") );
	m_pObjClassFactory = new CDriverAdapterClassFactory();

	return IOSTATUS_SUCCESS;
}

VOID CDriverAdapterDriver::OnUnLoad( )
{
	delete m_pObjClassFactory;
}

unsigned long _cdecl CDriverAdapterDriver::DRIVERADAPTERDRV_GetVersion( )
{
	return( (DRIVERADAPTERDRV_Major << 8) | DRIVERADAPTERDRV_Minor );
}

