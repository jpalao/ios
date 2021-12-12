//
//  CBPerl.m
//  Camel Bones - a bare-bones Perl bridge for Objective-C
//  Originally written for ShuX
//
//  Copyright (c) 2002 Sherm Pendley. All rights reserved.
//

#import "AppMain.h"

#import "CBPerl.h"

@interface CBPerl (DummyThread)
- (void) dummyThread: (id)dummy;
@end

@implementation CBPerl

@synthesize CBPerlInterpreter = _CBPerlInterpreter;

static NSMutableDictionary * perlInstanceDict = nil;
static Boolean perlInitialized = false;

+ (void) initPerlInstanceDictionary: (NSMutableDictionary *) dictionary {
    @synchronized(self) {
        // prevent xs call to overwrite the perl instance dict when running from app
        if (!perlInstanceDict) {
            perlInstanceDict = dictionary;
        }
    }
}

+ (void) clearPerlInstanceDictionary: (NSMutableDictionary *) dictionary {
    @synchronized(self) {
        if (dictionary == perlInstanceDict)
            perlInstanceDict = nil;
    }
}

+ (NSMutableDictionary *) getPerlInstanceDictionary {
    @synchronized(self) {
        return perlInstanceDict;
    }
}

+ (void) initializePerl {
    @synchronized(self) {
        char *dummy_perl_env[1] = { NULL };
        int nargs = 0;
        char *emb[] = {};

#if defined(PERL_SYS_INIT3) && !defined(MYMALLOC)
        /* only call this the first time through, as per perlembed man page */
        PERL_SYS_INIT3(&nargs, (char ***) &emb, (char***)&dummy_perl_env);
#endif
        perlInitialized = 1;
    }
}

+ (void) destroyPerl {
    PERL_SYS_TERM();
    perlInitialized = 0;
}

+ (CBPerl *) getCBPerlFromPerlInterpreter: (PerlInterpreter *) perlInterpreter {
    @synchronized(perlInstanceDict) {
        CBPerl * result = [[CBPerl getPerlInstanceDictionary] valueForKey:[NSString stringWithFormat:@"%llx", (unsigned long long) perlInterpreter]];
        return result;
    }
}

+ (void) setCBPerl:(CBPerl *) cbperl forPerlInterpreter:(PerlInterpreter *) perlInterpreter {
    @synchronized(self) {
        NSAssert ([CBPerl getPerlInstanceDictionary] != NULL, @"perl2CBPerlDict is NULL");
        [[CBPerl getPerlInstanceDictionary] setObject:cbperl forKey:[NSString stringWithFormat:@"%llx", (unsigned long long) perlInterpreter]];
    }
}

+ (PerlInterpreter *) getPerlInterpreter {
    @synchronized(perlInstanceDict) {
#if DEBUG
        void * vp = PERL_GET_CONTEXT;
        NSAssert(vp != NULL, @"getPerlInterpreter returning null...");
        return vp;
#else
        return PERL_GET_CONTEXT;
#endif
    }
}

- (void) dealloc
{
    @synchronized(perlInstanceDict) {
        [super dealloc];
    };
}

- (NSArray *) getDirsInPerl5Dir {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString * bundlePath  = [[NSBundle mainBundle] resourcePath];
    NSURL *directoryURL = [NSURL URLWithString:bundlePath];
    NSURL *perl5URL = [directoryURL URLByAppendingPathComponent:@"perl5"];
    // TODO handle error
    return [fileManager contentsOfDirectoryAtPath:perl5URL.path error: nil];
}

- (NSArray *) getDefaultPerlIncludes {
    NSString * bundlePath                   = [[NSBundle mainBundle] resourcePath];
    NSArray * perl5Dirs = [self getDirsInPerl5Dir];

    if (!perl5Dirs.count) return [NSMutableArray arrayWithCapacity:0].mutableCopy;
    
    for (id input in perl5Dirs) {
        NSString * exp = @"^(5\\.\\d+\\.\\d+)$";
        NSError * error = nil;
         NSRegularExpression * regex = [NSRegularExpression regularExpressionWithPattern:exp options:0 error:&error];

         if (error) {
             // TODO
//             [self showDialog:@"Error" withMessage:[NSString stringWithFormat:@"Regex failed with input : %@", input]];
//             return @"";
         }

         NSUInteger numberOfMatches = [regex numberOfMatchesInString:input options:0 range:NSMakeRange(0, [input length])];
         if (!numberOfMatches) continue;
         self.perlVersionString = input;
    }

    NSAssert(self.perlVersionString != nil, @"perlVersionString is nil");
    NSString * incCaches = [NSString stringWithFormat:@"-I%@/Library/Caches", bundlePath];
    NSString * inc1 = [NSString stringWithFormat:@"-I%@/perl5/%@", bundlePath, self.perlVersionString];
    NSString * inc2 = [NSString stringWithFormat:@"-I%@/perl5/%@/darwin-thread-multi-2level", bundlePath, self.perlVersionString];
    NSString * inc3 = [NSString stringWithFormat:@"-I%@/perl5/site_perl/%@", bundlePath, self.perlVersionString];
    NSString * inc4 = [NSString stringWithFormat:@"-I%@/perl5/site_perl/%@/darwin-thread-multi-2level", bundlePath, self.perlVersionString];

    return [NSArray arrayWithObjects: incCaches, inc1, inc2, inc3, inc4,  nil];
}

- (void) initWithFileName:(NSString*)fileName withAbsolutePwd:(NSString*)pwd withDebugger:(Boolean)debuggerEnabled withOptions:(NSArray *) options withArguments:(NSArray *) arguments error:(NSError **)error completion:(PerlCompletionBlock)completion
{
@autoreleasepool
{
    int embSize = 0;
    int dirChanged = -1;
    char *emb[32];
    int result;

    @synchronized(perlInstanceDict)
    {
        if (fileName) {
            NSURL * filePathUrl = [NSURL URLWithString: fileName];
            NSURL * dirPath = [filePathUrl URLByDeletingLastPathComponent];
            NSString * dirToChange = nil;
            if (pwd && pwd.length > 0) {
                dirToChange = pwd;
            } else if (dirPath && ![fileName hasSuffix:@"debug_client.pl"]) {
                dirToChange = dirPath.absoluteString;
            }
            if (dirToChange) {
                dirChanged = chdir(dirToChange.UTF8String);
                if (dirChanged < 0) {
                    NSString * errm = [NSString stringWithFormat: @"Cannot chdir: %@", dirToChange];
                    * error = [[NSError alloc] initWithDomain:@"dev.perla.init" code:01 userInfo:@{@"reason": errm}];
                    return;
                }
            }

            if (dirPath) {
                NSString * pwdEnv = [NSString stringWithFormat:@"PWD=%@", dirPath.path];
                char * pwdEnvCstring = (char *)[pwdEnv UTF8String];
                putenv(pwdEnvCstring);
            }
        }
        NSArray * perlIncludes = [self getDefaultPerlIncludes];

        for (NSString * perlInclude in perlIncludes){
            if (perlInclude != nil)
                emb[embSize++] = (char *)[perlInclude UTF8String];
        }

        if (options != nil){
            for (NSString * option in options)
            {
                if (option != nil)
                {
                    if ([option isKindOfClass: [NSNumber class]])
                    {
                        option = [(NSNumber *)option stringValue];
                        emb[embSize++] = (char *)[option UTF8String];
                    }
                    else if ([option isKindOfClass: [NSString class]])
                    {
                        emb[embSize++] = (char *)[option UTF8String];
                    }
                    else if ([option isKindOfClass: [NSArray class]])
                    {
                        for (NSString * opt in option)
                        {
                            emb[embSize++] = (char *)[opt UTF8String];
                        }
                    }
                }
            }
        }

        if (fileName) {
            if ( debuggerEnabled ) {
                emb[embSize++] = "-d:ebug::Backend";
            }
            emb[embSize++] = (char *)[fileName UTF8String];
        }

        if (arguments != nil){
            for (NSString * argument in arguments) {
                if (argument != nil)
                    emb[embSize++] = (char *)[argument UTF8String];
            }
        }

        // No, create one and retain it

        if ((self = [super init]))
        {
            if (!perlInitialized)
            {
                [CBPerl initializePerl];
            }

            _CBPerlInterpreter = perl_alloc();

            if(_CBPerlInterpreter == NULL)
            {
                * error = [[NSError alloc] initWithDomain:@"dev.perla.init" code:01 userInfo:@{@"reason": @"Cannot initialize perl interpreter"}];
                [self cleanUp];
                return;
            }
            else
            {
                PERL_SET_CONTEXT(_CBPerlInterpreter);
            }

            [CBPerl setCBPerl:self forPerlInterpreter:_CBPerlInterpreter];

            PL_perl_destruct_level = 1;
            @try
            {
                perl_construct(_CBPerlInterpreter);
            }
            @catch (NSException * exception )
            {
                NSLog(@"perl_construct threw Exception %@", [exception description]);
                return;
            }
        } else {
            // Wonder what happened here?
            return;
        }
        @try {
            result = perl_parse(_CBPerlInterpreter, xs_init, embSize, emb, (char **)NULL);
        }
        @catch (NSException * exception ){
           NSLog(@"perl_parse threw Exception %@", [exception description]);
           * error = [[NSError alloc] initWithDomain:@"dev.perla.parse" code:03 userInfo:@{@"reason":[NSString stringWithFormat:@"%@", [exception description]]}];
           return;
        }
    }

    @try {
        int perl_run_result = perl_run(_CBPerlInterpreter);
        result = result ? result : perl_run_result;
    } @catch (NSException *exception) {
        * error = [[NSError alloc] initWithDomain:@"dev.perla.run" code:05 userInfo:@{@"reason":[NSString stringWithFormat:@"Unspecified error\n"]}];
    }

    if (result || *error != nil)
    {
        if ( SvTRUE(ERRSV ) )
        {
            char * perl_error = SvPVx_nolen(ERRSV);
            * error = [[NSError alloc] initWithDomain:@"dev.perla.run" code:result userInfo:@{@"reason":[NSString stringWithFormat:@"%s", perl_error]}];
        }
        else
        {
            * error = [[NSError alloc] initWithDomain:@"dev.perla.run" code:result userInfo:@{@"reason":[NSString stringWithFormat:@"Unspecified error\n"]}];
        }
    }

    [self cleanUp];
    if (completion) completion(result);
}
}

-(void) cleanUp {
    @synchronized(perlInstanceDict) {
        PERL_SET_CONTEXT([CBPerl getPerlInterpreter]);
        PL_perl_destruct_level = 1;
        [[CBPerl getPerlInstanceDictionary] removeObjectForKey:[NSString stringWithFormat:@"%llx", (unsigned long long) _CBPerlInterpreter]];
        perl_destruct(_CBPerlInterpreter);
        perl_free(_CBPerlInterpreter);
        // NSInteger rc = [self retainCount];
        NSArray *syms = [NSThread callStackSymbols];
        BOOL checkCBRunPerl = NO;
        for (NSString * sym in syms) {
             if ([sym rangeOfString:@"CBRunPerl"].location != NSNotFound) {
                 checkCBRunPerl = YES;
                 break;
             }
        }
        if (checkCBRunPerl) {
            [self dealloc];
        }
        //      TODO: PERL_SYS_TERM will kill the app, cannot be called at least on iOS
    }
}

- (id) initXS {

    [CBPerl initPerlInstanceDictionary: [NSMutableDictionary dictionaryWithCapacity:128]];

    if ((self = [super init])) {
        _CBPerlInterpreter = PERL_GET_CONTEXT;
        [CBPerl setCBPerl:self forPerlInterpreter:_CBPerlInterpreter];
        return [self retain];
    } else {
        // Wonder what happened here?
        return nil;
    }
}

@end
