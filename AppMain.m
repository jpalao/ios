//
//  AppMain.m
//
//  Copyright (c) 2004 Sherm Pendley. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AppMain.h"
#import "CBPerl.h"

int CBApplicationMain(int argc, const char *argv[]) {
    return CBApplicationMain2("main.pl", argc, argv);
}

int CBApplicationMain2(const char *scriptName, int argc, const char *argv[]) {

    NSAutoreleasePool *arPool = [[NSAutoreleasePool alloc] init];
    NSString *wrapperFolder = [[NSBundle mainBundle] resourcePath];
    NSString *mainPL = [NSString stringWithFormat: @"%@/%s", wrapperFolder, scriptName];
    NSError *error = nil;
    char cpwd[MAXPATHLEN];
    getcwd(cpwd, MAXPATHLEN -1);
    NSURL * pwd = [NSURL URLWithString: [NSString stringWithCString:cpwd encoding:NSUTF8StringEncoding]];
    // Run Perl code
    [[CBPerl alloc] initWithFileName:mainPL withAbsolutePwd: pwd.absoluteURL.path withDebugger:0 withOptions:nil withArguments:nil error:&error completion:nil];
    //TODO handle error

    [arPool release];
    return 0;
}

NSString * CBGetProcessorDescription(void) {
    char buf[100];
    size_t buflen = 100;
    sysctlbyname("machdep.cpu.brand_string", &buf, &buflen, NULL, 0);
    NSString *cpu = [NSString stringWithFormat:@"%s", buf];

    return [cpu autorelease];
}


NSString * CBGetArchitecture(void) {
    NSMutableString *cpu = [[NSMutableString alloc] init];
    size_t size;
    cpu_type_t type;
    cpu_subtype_t subtype;

    size = sizeof(type);
    sysctlbyname("hw.cputype", &type, &size, NULL, 0);

    size = sizeof(subtype);
    sysctlbyname("hw.cpusubtype", &subtype, &size, NULL, 0);

    if (type == CPU_TYPE_I386)
    {
        [cpu appendString:@"i386"];
    }
    else if (type == CPU_TYPE_X86_64)
    {
        [cpu appendString:@"x86_64"];
    }
    else if (type == CPU_TYPE_ARM)
    {
        [cpu appendString:@"arm"];
        switch(subtype)
        {
            case CPU_SUBTYPE_ARM_V7:
                [cpu appendString:@"v7"];
                break;
            case CPU_SUBTYPE_ARM_V7S:
                [cpu appendString:@"v7s"];
                break;
            case CPU_SUBTYPE_ARM64_ALL:
                [cpu appendString:@"64"];
        }
    }
    else
    {
        char str[256];
        sprintf(str, "(%d, %d) is not a supported architecture (type, subtype)", type, subtype);
        NSCAssert(FALSE, [NSString stringWithCString:str  encoding:NSUTF8StringEncoding]);
    }
    return [cpu autorelease];
}
