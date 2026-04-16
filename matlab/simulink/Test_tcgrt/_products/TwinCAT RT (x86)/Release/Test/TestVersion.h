////////////////////////////////////////////////////////////////////////////
// TestVersion.h

#ifndef TestVersion_H_INCLUDED
#define TestVersion_H_INCLUDED

#define Test_Version   0
#define Test_Revision  0
#define Test_Build     10

#define Test_FileVersionMajor    0
#define Test_FileVersionMinor    0
#define Test_FileVersionBuild    0
#define Test_FileVersionRevision 10
#define Test_FileVersionStr      "0.0.0.10"
#define Test_FileVersionRcStr    "0,0,0,10"

#define Test_ProductMajor        0
#define Test_ProductMinor        0
#define Test_ProductBuild        0
#define Test_ProductRevision     10
#define Test_ProductVersionStr   "0.0.0.10"
#define Test_ProductVersionRcStr "0,0,0,10"

#define Test_CompanyNameStr      "TE140x Module Vendor"
#define Test_InternalNameStr     "Test"
#define Test_LibraryIdNameStr    "TE140x Module Vendor|Test|0.0.0.10"

#ifndef RC_INVOKED
static const GUID VID_Test      = { 0xd152a0e9, 0x1ee6, 0x60bc, { 0x61, 0x56, 0x6d, 0x75, 0xca, 0xc0, 0x50, 0x7c } };
#endif

#endif // include guard
