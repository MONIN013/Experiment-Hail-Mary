///////////////////////////////////////////////////////////////////////////////
// ExperimentLoggerDriver.cpp
#include "TcPch.h"
#pragma hdrstop

#include "ExperimentLoggerDriver.h"
#include "ExperimentLoggerClassFactory.h"

DECLARE_GENERIC_DEVICE(EXPERIMENTLOGGERDRV)

IOSTATUS CExperimentLoggerDriver::OnLoad( )
{
	TRACE(_T("CObjClassFactory::OnLoad()\n") );
	m_pObjClassFactory = new CExperimentLoggerClassFactory();

	return IOSTATUS_SUCCESS;
}

VOID CExperimentLoggerDriver::OnUnLoad( )
{
	delete m_pObjClassFactory;
}

unsigned long _cdecl CExperimentLoggerDriver::EXPERIMENTLOGGERDRV_GetVersion( )
{
	return( (EXPERIMENTLOGGERDRV_Major << 8) | EXPERIMENTLOGGERDRV_Minor );
}

