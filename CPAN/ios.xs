#import <ios/AppMain.h>
#import <ios/CBPerl.h>
#import <ios/NativeMethods.h>
#import <ios/PerlImports.h>

#ifdef GNUSTEP
#include <objc/objc.h>
#else
#if TARGET_OS_IPHONE
#import <objc/runtime.h>
#elif TARGET_OS_MAC
#import <objc/objc-runtime.h>
#endif
#endif

#import <XSUB.h>

MODULE = ios	PACKAGE = ios

PROTOTYPES: ENABLE

void
CBPoke(address, object, size=0)
	void *address;
	SV *object;
	unsigned size;

void
CBInit(importCocoa)
    BOOL importCocoa;
    CODE:
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
    [[CBPerl alloc] initXS: importCocoa];

AV*
CBRunPerlCaptureStdout(json)
    const char* json;

SV*
CBRunPerl(json)
    const char* json;

SV*
CBYield(ti)
    double ti;

