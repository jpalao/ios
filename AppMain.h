//
//  AppMain.h
//  ios
//
//  Copyright (c) 2004 Sherm Pendley. All rights reserved.
//

#include <sys/sysctl.h>
#import <Foundation/Foundation.h>

// Default entry point for applications, defaults to main.pl
extern int CBApplicationMain(int argc, const char *argv[]);

// Default entry point for applications, allowing specification of script name
extern int CBApplicationMain2(const char *scriptName, int argc, const char *argv[]);

// Examine the system to determine Perl arch/version to use
extern void CBSetPerlArchver(const char *archVer);
extern NSString * CBGetArchitecture(void);
extern NSString * CBGetProcessorDescription(void);
