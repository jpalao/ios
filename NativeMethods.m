//
//  NativeMethods.m
//  ios
//
//  Copyright (c) 2021 Jose Palao. All rights reserved.
//

#import "CBPerl.h"
#import "NativeMethods.h"

// The BYTEORDER macro is also #defined by perl, and Perl's use
// of it should be fully expanded by now.
#undef BYTEORDER

static dispatch_once_t onceToken = 0;
static dispatch_queue_t stdioQueue = nil;

void init_dispatch_queue()
{
   dispatch_once(&onceToken, ^{
       stdioQueue = dispatch_queue_create("ios.stdio", DISPATCH_QUEUE_SERIAL);
   });
}

NSString * unquoteString(NSString *prog) {
    if ([prog hasPrefix: @"\""] && [prog hasSuffix: @"\""])
    {
        prog = [prog substringWithRange:NSMakeRange(1, [prog length]-2)];
    }
    return prog;
}

NSMutableDictionary * parseRunPerl (char * json)
{
    NSMutableDictionary * result = [[NSMutableDictionary alloc] initWithCapacity:256];

    int retval = 0;

    NSData * data = nil;
    NSDictionary *jsonResponse = nil;
    NSString * absPwd = nil;
    NSArray * args = nil;
    NSArray * switches = nil;
    NSString * filePath = nil;
    NSError *error = nil;
    NSString * prog  = nil;
    NSArray * progs = nil;
    NSNumber * stderrBool = nil;
    NSNumber * nolibBool = nil;

    if (!json) {
        return nil;
    }

    @try
    {
        data = [[NSString stringWithCString: json encoding:NSUTF8StringEncoding] dataUsingEncoding:NSUTF8StringEncoding];
    }
    @catch (NSException * e)
    {
        retval = 1;
    }
    if (!retval && data != nil)
    {
        jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
        if (error || !jsonResponse) {
            retval = 2;
        }
    }
    if (!retval)
    {
        @try
        {
            switches = [jsonResponse valueForKey:@"switches"];
        } @finally {
            if (switches == nil || [switches isEqual:[NSNull null]])
            {
                switches = @[];
            }
            else
            {
                NSMutableArray * mutableSwitches = [[NSMutableArray alloc] initWithCapacity: switches.count];
                for (NSString * s in switches) {
                    NSString * unquoted = unquoteString(s);
                    [mutableSwitches addObject:unquoted];
                }
                [mutableSwitches removeObject:@""];
                switches = [mutableSwitches copy];
            }
            [result setObject:[switches copy] forKey:@"switches"];
        }

        @try
        {
            nolibBool = [jsonResponse valueForKey:@"nolib"];
        } @finally {
            if (!(nolibBool != nil && ![nolibBool isEqual:[NSNull null]] && [nolibBool isEqualToNumber: [NSNumber numberWithUnsignedInt:1]]))
            {
                NSMutableArray * mutable = [[result objectForKey:@"switches"] mutableCopy];
                [mutable addObject:@"-I../lib"];
                switches = [mutable copy];
                [result setObject:switches forKey:@"switches"];
            }
        }

        @try
        {
            filePath = [jsonResponse valueForKey:@"progfile"];
        }
        @finally {
            if (filePath == nil || [filePath isEqual:[NSNull null]]) {
                @try
                {
                    prog = [jsonResponse valueForKey:@"prog"];
                }
                @finally
                {
                    if (prog == nil || [prog isEqual:[NSNull null]])
                    {
                        @try {
                            progs = [jsonResponse valueForKey:@"progs"];
                        } @finally {
                            if (progs != nil && ![progs isEqual:[NSNull null]])
                            {
                                NSMutableArray * mutable = [[result objectForKey:@"switches"] mutableCopy];
                                for (NSString* prog in progs) {
                                    [mutable addObject:@"-e"];
                                    NSString * unquoted = unquoteString(prog);
                                    [mutable addObject:unquoted];
                                }
                                switches = [mutable copy];
                                [result setObject:switches forKey:@"switches"];
                            }
                        }
                    }
                    else
                    {
                        if ([prog isKindOfClass: [NSNumber class]]) {
                            prog = [(NSNumber *)prog stringValue];
                        }
                        NSMutableArray * mutable = [[result objectForKey:@"switches"] mutableCopy];
                        [mutable addObject:@"-e"];
                        NSString * unquoted = unquoteString(prog);
                        [mutable addObject:unquoted];
                        switches = [mutable copy];
                        [result setObject:switches forKey:@"switches"];
                    }
                }
            }
            else {
                [result setObject:filePath forKey:@"filePath"];
            }
        }

        @try
        {
            absPwd = [jsonResponse valueForKey:@"pwd"];
        } @finally {
            if (absPwd == nil || [absPwd isEqual:[NSNull null]]) absPwd = @".";
            [result setObject:absPwd forKey:@"absPwd"];
        }

        @try
        {
            stderrBool = [jsonResponse valueForKey:@"stderr"];
        } @finally {
            if (stderrBool == nil || [stderrBool isEqual:[NSNull null]]) stderrBool = [NSNumber numberWithUnsignedInt:0];
            [result setObject:stderrBool forKey:@"stderr"];
        }

        @try {
            args = [jsonResponse valueForKey:@"args"];
        } @finally {
            if (args == nil || [args isEqual:[NSNull null]]) args = @[];
            [result setObject:args forKey:@"args"];
        }
    }
    return result;
}

void * CBYield(double ti)
{
    [NSThread sleepForTimeInterval:ti];
    SV *ret = newSV(0);
    return (void *)ret;
}

void* CBRunPerl (char * json)
{
@autoreleasepool {
    // Define a Perl context
    PERL_SET_CONTEXT([CBPerl getPerlInterpreter]);
    dTHX;

    NSMutableDictionary * cbRunPerlDict = parseRunPerl(json);

    __block int retval = 0;
    __block BOOL  wait_for_perl = TRUE;

    SV *ret = newSV(retval);

    if (cbRunPerlDict == nil)
    {
        retval = 1;
        @synchronized (stdioQueue) {
            wait_for_perl = NO;
        }
    }
    else
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, (unsigned long)NULL), ^(void) {
            @autoreleasepool {
                NSString * filePath = [cbRunPerlDict objectForKey:@"filePath"];
                NSString * absPwd = [cbRunPerlDict objectForKey:@"absPwd"];
                BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:filePath];

                if (!fileExists && ![filePath isAbsolutePath] && absPwd != nil)
                {
                    NSString * pathWithCwd = [NSString stringWithFormat:@"%@/%@", absPwd, filePath];
                    fileExists =  [[NSFileManager defaultManager] fileExistsAtPath:pathWithCwd];
                    if (fileExists)
                    {
                        filePath = [NSString stringWithString: pathWithCwd];
                    }
                }

                if (retval == 0)
                {
                    @try
                    {
                        NSError *perlError = nil;
                        [
                            [CBPerl alloc]
                            initWithFileName:filePath
                            withAbsolutePwd:absPwd
                            withDebugger:FALSE
                            withOptions:[cbRunPerlDict objectForKey:@"switches"]
                            withArguments:[cbRunPerlDict objectForKey:@"args"]
                            error:&perlError
                            completion: (PerlCompletionBlock) ^ (int perlResult) {
                                fflush(stdout);
                                fflush(stderr);
                                [NSThread sleepForTimeInterval: 0.05];
                            }
                        ];
                        if (perlError) {
                            retval = perlError.code;
                        }
                    }
                    @catch (NSException *)
                    {
                        retval = 5;
                    }
                }
                @synchronized (stdioQueue) {
                    wait_for_perl = FALSE;
                }
            }
        });
    }

    while (1) {
        @synchronized (stdioQueue) {
            if (!wait_for_perl) {
                break;
            }
        }
        [NSThread sleepForTimeInterval: 0.1];
    }

    sv_setiv(ret, (int)((retval & 0xff) << 8));
    return (void *)ret;
} // autoreleasepool
}

static void handleStdioException(NSException *exception, NSMutableData *string) {
    @synchronized (stdioQueue) {
        [string appendData:[[exception description] dataUsingEncoding:NSUTF8StringEncoding]];
    }
}

void*
CBRunPerlCaptureStdout (char * json) {
@autoreleasepool {

    // Define a Perl context
    PERL_SET_CONTEXT([CBPerl getPerlInterpreter]);
    dTHX;

    AV * results = newAV();
    SV * stdout_result = nil;
    SV * exit_code = nil;

    if (stdioQueue == nil) {
        init_dispatch_queue();
    }

    BOOL redirectStderr = NO;

    NSPipe * stdoutPipe = [NSPipe pipe];
    NSPipe * stderrPipe = [NSPipe pipe];
    __block BOOL  ended = FALSE;
    __block id notificationObserver, notificationObserver2;
    NSMutableData * stdoutOutput = [NSMutableData dataWithCapacity:100000000];
    NSFileHandle * stdoutPipeOut = [stdoutPipe fileHandleForReading];
    NSFileHandle * stderrPipeOut = [stderrPipe fileHandleForReading];

    NSFileHandle * stdoutPipeIn = [stdoutPipe fileHandleForWriting];
    NSFileHandle * stderrPipeIn = [stderrPipe fileHandleForWriting];

    int stderr_fd = STDERR_FILENO;
    int stdout_fd = STDOUT_FILENO;

    int saved_stdout = dup(stdout_fd);
    int saved_stderr = dup(stderr_fd);

    int close_r = -1;

    if (redirectStderr)
    {
        dup2([stdoutPipeIn fileDescriptor], stderr_fd);
    }
    else
    {
        dup2([stderrPipeIn fileDescriptor], stderr_fd);
    }

    dup2([stdoutPipeIn fileDescriptor], stdout_fd);

    [stdoutPipeIn initWithFileDescriptor:[stdoutPipeIn fileDescriptor]];
    [stderrPipeIn initWithFileDescriptor:[stderrPipeIn fileDescriptor]];

    dispatch_sync(dispatch_get_main_queue(), ^{
        notificationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSFileHandleDataAvailableNotification object:stdoutPipeOut queue:[NSOperationQueue mainQueue] usingBlock: (void (^)(NSNotification *)) ^{
            if (!ended) {
                @try {
                    @synchronized (stdioQueue) {
                         [stdoutOutput appendData:[stdoutPipeOut availableData]];
                    }
                    if (!ended) {
                        [stdoutPipeOut waitForDataInBackgroundAndNotify];
                    }
                }
                @catch (NSException * exception) {
                    if (!ended) {
                        handleStdioException(exception, stdoutOutput);
                    }
                }
            }
        }];
        [stdoutPipeOut waitForDataInBackgroundAndNotify];
        if (!redirectStderr)
        {
            notificationObserver2 = [[NSNotificationCenter defaultCenter] addObserverForName:NSFileHandleDataAvailableNotification object:stderrPipeOut queue:[NSOperationQueue mainQueue] usingBlock: (void (^)(NSNotification *)) ^{
                if (!ended) {
                    @try {
                        @synchronized (stdioQueue) {
                            [stdoutOutput appendData:[stderrPipeOut availableData]];
                        }
                        if (!ended) {
                            [stderrPipeOut waitForDataInBackgroundAndNotify];
                        }
                    }
                    @catch (NSException * exception) {
                        if (!ended) {
                            handleStdioException(exception, stdoutOutput);
                        }
                    }
                }
            }];
            [stderrPipeOut waitForDataInBackgroundAndNotify];
        }
    });

    exit_code = CBRunPerl(json);
    @synchronized (stdioQueue) {
        ended = TRUE;
    }

    [[NSNotificationCenter defaultCenter] removeObserver:notificationObserver name:NSFileHandleDataAvailableNotification object:stdoutPipeOut];
    [[NSNotificationCenter defaultCenter] removeObserver:notificationObserver2 name:NSFileHandleDataAvailableNotification object:stderrPipeOut];

    [stdoutPipeOut closeFile];
    [stdoutPipeIn closeFile];
    [stderrPipeOut closeFile];
    [stderrPipeIn closeFile];

    int new_fd = dup2(saved_stdout, STDOUT_FILENO);
        new_fd = dup2(saved_stderr, STDERR_FILENO);

    close_r = close(saved_stdout);
    close_r = close(saved_stderr);

    stdout_result = newSVpvn_flags([stdoutOutput bytes], [stdoutOutput length], SVf_UTF8);

    av_push(results, exit_code);
    av_push(results, stdout_result);

    return (void *) results;
}
}
