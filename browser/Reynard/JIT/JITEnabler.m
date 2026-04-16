//
//  JITEnabler.m
//  Reynard
//
//  Created by Minh Ton on 11/3/26.
//

#import "JITEnabler.h"
#import "JITSupport.h"
#import "JITUtils.h"
#import "TSRoot.h"
#import "TSUtils.h"

@interface JITEnabler ()

@property(nonatomic, assign) DeviceProvider *sharedProvider;
@property(nonatomic, strong) dispatch_queue_t providerQueue;
@property(nonatomic, assign) BOOL didEnsureDDIMounted;

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
        _didEnsureDDIMounted = NO;
    }
    return self;
}

- (BOOL)enableJITForPID:(int32_t)pid hasTXM26:(BOOL)hasTXM26 error:(NSError **)error {
    // TrollStore or jailbroken devices
    if (getEntitlementValue(@"com.apple.private.security.no-sandbox")) {
        NSString *helperPath = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"ptrace_jit"];
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:helperPath]) {
            if (error) *error = MakeError(TSPtraceHelperMissing);
            return NO;
        }
        
        int result = spawnRoot(helperPath, @[[NSString stringWithFormat:@"%d", pid]]);
        if (result >= 128) {
            if (error) *error = MakeError(TSPtraceHelperTerminated);
            return NO;
        }
        
        if (result != 0) {
            if (error) *error = MakeError(TSPtraceHelperAttachFailed);
            return NO;
        }
        
        return YES;
    }
    
    if (@available(iOS 17.4, *)) {
        // For iOS 17.4 and later
        // Thanks StikDebug!
        // https://github.com/StephenDev0/StikDebug
        
        DeviceProvider *provider = [self getProvider:error];
        if (!provider) return NO;
        
        DebugSession session = {0};
        IdeviceFfiError *ffiError = NULL;
        
        if (!connectDebugSession(provider, &session, @"10.7.0.1", error)) return NO;
        
        ProcessControlHandle *processControl = NULL;
        ffiError = process_control_new(session.remoteServer, &processControl);
        if (ffiError) {
            if (error) *error = MakeError(ProcessControlCreateFailed);
            idevice_error_free(ffiError);
            freeDebugSession(&session);
            return NO;
        }
        
        ffiError = process_control_disable_memory_limit(processControl, (uint64_t)pid);
        process_control_free(processControl);
        if (ffiError) {
            logger([NSString stringWithFormat:@"disable_memory_limit failed for pid %d: %s", pid, ffiError->message ?: "unknown error"]);
            idevice_error_free(ffiError);
        }
        
        NSError *commandError = nil;
        NSString *noAckResponse = nil;
        if (!configureNoAckMode(session.debugProxy, &noAckResponse, &commandError)) {
            if (error) *error = commandError ?: MakeError(NoAckConfigureFailed);
            freeDebugSession(&session);
            return NO;
        }
        
        logger([NSString stringWithFormat:@"QStartNoAckMode result for pid %d: %@", pid, noAckResponse ?: @"<no response>"]);
        
        NSString *attachCommand = [NSString stringWithFormat:@"vAttach;%X", pid];
        NSString *attachResponse = nil;
        if (!sendDebugCommand(session.debugProxy, attachCommand, &attachResponse, &commandError)) {
            if (error) *error = commandError ?: MakeError(AttachDebugProxyFailed);
            freeDebugSession(&session);
            return NO;
        }
        
        logger([NSString stringWithFormat:@"Attach response for pid %d: %@", pid, attachResponse.length > 0 ? @"<stop packet>" : @"<no response>"]);
        
        if (hasTXM26) {
            registerJITEndpointForPID(pid, @"10.7.0.1", 49152);
            
            DebugSession *persistentSession = malloc(sizeof(*persistentSession));
            if (!persistentSession) {
                freeDebugSession(&session);
                if (error) *error = MakeError(SessionAllocationFailed);
                return NO;
            }
            
            *persistentSession = session;
            session.adapter = NULL;
            session.handshake = NULL;
            session.remoteServer = NULL;
            session.debugProxy = NULL;
            
            // TXM iOS 26+ workaround
            dispatch_async(debugServiceQueue(), ^{
                runDebugService(pid, persistentSession);
            });
            
            logger([NSString stringWithFormat:@"Debug session started for pid %d", pid]);
        } else {
            // detach immediately
            detachDebuggerSession(session.debugProxy, pid);
            freeDebugSession(&session);
        }
        
        return YES;
    } else {
        DeviceProvider *provider = [self getProvider:error];
        if (!provider) return NO;
        
        uint16_t debugPort = 0;
        if (!startLegacyDebugService(provider, &debugPort, error)) return NO;
        
        LegacyDebugConnection connection = {
            .socketFD = -1,
            .sslContext = NULL,
        };
        
        if (!connectLegacyDebugSocket(@"10.7.0.1", debugPort, &connection, error)) {
            return NO;
        }
        
        NSString *attachResponse = nil;
        NSString *attachCommand = [NSString stringWithFormat:@"vAttach;%08X", (uint32_t)pid];
        if (!sendLegacyDebugCommand(&connection, attachCommand, &attachResponse, error)) {
            closeLegacyDebugConnection(&connection);
            return NO;
        }
        
        logger([NSString stringWithFormat:@"Legacy attach response for pid %d: %@", pid, attachResponse.length > 0 ? attachResponse : @"<no response>"]);
        
        // detach immediately
        if (!detachLegacyDebuggerSession(&connection, pid)) {
            closeLegacyDebugConnection(&connection);
        }
        return YES;
    }
    
    return NO;
}

- (void)detachAllJITSessions {
    resetJITEndpointMonitor();
    dispatch_sync(debugSessionStateQueue(), ^{
        NSMutableSet<NSNumber *> *active = activeDebugSessionPIDs();
        NSMutableSet<NSNumber *> *detachRequested = detachRequestedDebugSessionPIDs();
        [detachRequested unionSet:active];
    });
}

- (DeviceProvider *)getProvider:(NSError **)error {
    __block DeviceProvider *provider = NULL;
    __block NSError *providerError = nil;
    
    dispatch_sync(self.providerQueue, ^{
        if (!self.sharedProvider) {
            self.sharedProvider = createDeviceProvider(pairingFilePath(), @"10.7.0.1", &providerError);
            self.didEnsureDDIMounted = NO;
        }
        
        if (self.sharedProvider && !self.didEnsureDDIMounted) {
            if (!ensureDDIMounted(self.sharedProvider, &providerError)) {
                provider = NULL;
                return;
            }
            self.didEnsureDDIMounted = YES;
        }
        
        provider = self.sharedProvider;
    });
    
    if (!provider && error) *error = providerError;
    return provider;
}

- (void)dealloc {
    resetJITEndpointMonitor();
    if (_sharedProvider) {
        freeDeviceProvider(_sharedProvider);
        _sharedProvider = NULL;
    }
}

@end
