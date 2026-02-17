///////////////////////////////////////////////////////////////////////////////
// VirtualMotorCoreDriver.cpp
#include "TcPch.h"
#pragma hdrstop

#include "VirtualMotorCoreDriver.h"
#include "VirtualMotorCoreClassFactory.h"

DECLARE_GENERIC_DEVICE(VIRTUALMOTORCOREDRV)

IOSTATUS CVirtualMotorCoreDriver::OnLoad( )
{
	TRACE(_T("CObjClassFactory::OnLoad()\n") );
	m_pObjClassFactory = new CVirtualMotorCoreClassFactory();

	return IOSTATUS_SUCCESS;
}

VOID CVirtualMotorCoreDriver::OnUnLoad( )
{
	delete m_pObjClassFactory;
}

unsigned long _cdecl CVirtualMotorCoreDriver::VIRTUALMOTORCOREDRV_GetVersion( )
{
	return( (VIRTUALMOTORCOREDRV_Major << 8) | VIRTUALMOTORCOREDRV_Minor );
}

