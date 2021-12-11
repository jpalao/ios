//
//  PerlImports.h
//  ios
//
//  Copyright (c) 2004 Sherm Pendley. All rights reserved.
//

#ifdef STRINGIFY
#undef STRINGIFY
#endif

#ifdef _
#undef _
#endif

#include "EXTERN.h"
#ifdef PERL_TIGER
#define HAS_BOOL
#endif
#include "perl.h"
#include "XSUB.h"
