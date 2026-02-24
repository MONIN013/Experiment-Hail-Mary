///////////////////////////////////////////////////////////////////////////////
// ControllerCoreDriver.cpp
#include "TcPch.h"
#pragma hdrstop

#include "ControllerCoreDriver.h"
#include "ControllerCoreClassFactory.h"

DECLARE_GENERIC_DEVICE(CONTROLLERCOREDRV)

IOSTATUS CControllerCoreDriver::OnLoad( )
{
	TRACE(_T("CObjClassFactory::OnLoad()\n") );
	m_pObjClassFactory = new CControllerCoreClassFactory();

	return IOSTATUS_SUCCESS;
}

VOID CControllerCoreDriver::OnUnLoad( )
{
	delete m_pObjClassFactory;
}

unsigned long _cdecl CControllerCoreDriver::CONTROLLERCOREDRV_GetVersion( )
{
	return( (CONTROLLERCOREDRV_Major << 8) | CONTROLLERCOREDRV_Minor );
}

