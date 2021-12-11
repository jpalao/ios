//
//  NativeMethods.h
//  ios
//
//  Copyright (c) 2004 Sherm Pendley. All rights reserved.
//

#import <Foundation/Foundation.h>

// Call a native class or object method

extern void* CBCallNativeMethod(void* target, SEL sel, void*args, BOOL isSuper);
extern void* CBYield(double ti);
extern void* CBRunPerl(char * json);
extern void* CBRunPerlCaptureStdout (char * json);
extern id CBDerefSVtoID(void* sv);
