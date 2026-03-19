//
//  JITEnabler.m
//  Reynard
//
//  Created by Minh Ton on 11/3/26.
//

#import "JITEnabler.h"
#import "JITSupport.h"
#import "JITUtils.h"

static NSString *const enablerErrorDomain = @"JITEnabler";

@interface JITEnabler ()

@property(nonatomic, assign) DeviceProvider *sharedProvider;
@property(nonatomic, strong) dispatch_queue_t providerQueue;

- (DeviceProvider *)getProvider:(NSError **)error;

@end

@implementation JITEnabler

+ (JITEnabler *)shared {
    static JITEnabler *sharedEnabler = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedEnabler = [[self alloc] init];
    });
    return sharedEnabler;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sharedProvider = NULL;
        _providerQueue = dispatch_queue_create("me.minh-ton.jit.enabler.provider", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)enableJITForPID:(int32_t)pid logHandler:(LogHandler)logHandler error:(NSError **)error {
    if (@available(iOS 17, *)) {
        // For iOS 17 and later
        // Thanks StikDebug!
        // https://github.com/StephenDev0/StikDebug
        
        DeviceProvider *provider = [self getProvider:error];
        if (!provider) return NO;
        
        DebugSession session = {0};
        IdeviceFfiError *ffiError = NULL;
        
        if (!connectDebugSession(provider, &session, error)) return NO;
        
        ProcessControlHandle *processControl = NULL;
        ffiError = process_control_new(session.remoteServer, &processControl);
        if (ffiError) {
            if (error) {
                NSString *description = [NSString stringWithUTF8String: ffiError->message ?: "Failed to create process control client."];
                *error = errorWithCode(ffiError->code, description);
            }
            idevice_error_free(ffiError);
            freeDebugSession(&session);
            return NO;
        }
        
        ffiError = process_control_disable_memory_limit(processControl, (uint64_t)pid);
        process_control_free(processControl);
        if (ffiError) {
            logger([NSString stringWithFormat:@"disable_memory_limit failed for pid %d: %s", pid, ffiError->message ?: "unknown error"], logHandler);
            idevice_error_free(ffiError);
        }
        
        NSError *commandError = nil;
        NSString *noAckResponse = nil;
        if (!configureNoAckMode(session.debugProxy, &noAckResponse, &commandError)) {
            if (error) *error = commandError ?: errorWithCode(-9, @"Failed to configure no-ack debug mode.");
            freeDebugSession(&session);
            return NO;
        }
        
        logger([NSString stringWithFormat:@"QStartNoAckMode result for pid %d: %@", pid, noAckResponse ?: @"<no response>"], logHandler);
        
        NSString *attachCommand = [NSString stringWithFormat:@"vAttach;%X", pid];
        NSString *attachResponse = nil;
        if (!sendDebugCommand(session.debugProxy, attachCommand, &attachResponse, &commandError)) {
            if (error) *error = commandError ?: errorWithCode(-6, @"Failed to attach debug proxy.");
            freeDebugSession(&session);
            return NO;
        }
        
        logger([NSString stringWithFormat:@"Attach response for pid %d: %@", pid, attachResponse.length > 0 ? @"<stop packet>" : @"<no response>"], logHandler);
        
        DebugSession *persistentSession = malloc(sizeof(*persistentSession));
        if (!persistentSession) {
            freeDebugSession(&session);
            if (error) *error = errorWithCode(-8, @"Failed to allocate persistent debug session.");
            return NO;
        }
        
        *persistentSession = session;
        session.adapter = NULL;
        session.handshake = NULL;
        session.remoteServer = NULL;
        session.debugProxy = NULL;
        
        DeviceLogHandler copiedHandler = [logHandler copy];
        dispatch_async(debugServiceQueue(), ^{
            runDebugService(pid, persistentSession, copiedHandler);
        });
        
        logger([NSString stringWithFormat:@"Debug session started for pid %d", pid], logHandler);
        
        return YES;
    } else {
        DeviceProvider *provider = [self getProvider:error];
        if (!provider) return NO;
        
        uint16_t debugPort = 0;
        BOOL usesSSL = NO;
        const char *serviceName = "<unknown>";
        if (!startLegacyDebugService(provider, &debugPort, &usesSSL, &serviceName, error)) return NO;
        
        LegacyDebugSession *legacySession = calloc(1, sizeof(*legacySession));
        if (!legacySession) {
            if (error) *error = errorWithCode(-8, @"Failed to allocate legacy debug session.");
            return NO;
        }
        
        legacySession->connection.socketFD = -1;
        legacySession->connection.sslContext = NULL;
        legacySession->connection.usesSSL = usesSSL;
        legacySession->debugPort = debugPort;
        legacySession->usesSSL = usesSSL;
        legacySession->serviceName = serviceName;
        
        if (!connectLegacyDebugSocket(@"10.7.0.1", debugPort, usesSSL, &legacySession->connection, error)) {
            if (error && *error && usesSSL) {
                NSString *description = [NSString stringWithFormat:@"%@ lockdownd requested SSL for service %s on port %u.", (*error).localizedDescription ?: @"Legacy debug connect failed.", serviceName, debugPort];
                *error = errorWithCode((*error).code, description);
            }
            free(legacySession);
            return NO;
        }
        
        NSString *attachResponse = nil;
        NSString *attachCommand = [NSString stringWithFormat:@"vAttach;%08X", (uint32_t)pid];
        if (!sendLegacyDebugCommand(&legacySession->connection, attachCommand, &attachResponse, error)) {
            if (error && *error) {
                NSString *description = [NSString stringWithFormat:@"%@ (service=%s, port=%u, ssl=%@)", (*error).localizedDescription ?: @"Legacy attach command failed.", serviceName, debugPort, usesSSL ? @"true" : @"false"];
                *error = errorWithCode((*error).code, description);
            }
            
            closeLegacyDebugConnection(&legacySession->connection);
            free(legacySession);
            return NO;
        }
        
        logger([NSString stringWithFormat:@"Legacy attach response for pid %d: %@", pid, attachResponse.length > 0 ? attachResponse : @"<no response>"], logHandler);
        
        DeviceLogHandler copiedHandler = [logHandler copy];
        dispatch_async(debugServiceQueue(), ^{
            runLegacyDebugService(pid, legacySession, copiedHandler);
        });
        
        logger([NSString stringWithFormat:@"Legacy debug session started for pid %d", pid], logHandler);
        
        return YES;
    }
    
    return NO;
}

- (DeviceProvider *)getProvider:(NSError **)error {
    __block DeviceProvider *provider = NULL;
    __block NSError *providerError = nil;
    dispatch_sync(self.providerQueue, ^{
        if (!self.sharedProvider) self.sharedProvider = createDeviceProvider([self pairingFilePath], @"10.7.0.1", &providerError);
        provider = self.sharedProvider;
    });
    
    if (!provider && error) *error = providerError;
    return provider;
}

- (void)dealloc {
    if (_sharedProvider) {
        freeDeviceProvider(_sharedProvider);
        _sharedProvider = NULL;
    }
}

- (NSString *)pairingFilePath {
    NSURL *documentsDirectory = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    return [[documentsDirectory URLByAppendingPathComponent:@"pairingFile.plist"] path];
}

@end
