//
//  JITSupport.m
//  Reynard
//
//  Created by Minh Ton on 11/3/2026.
//

#import "JITSupport.h"
#import "JITErrors.h"
#import "JITUtils.h"
#import "IdeviceFFI.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <netinet/tcp.h>
#include <unistd.h>

static const uint16_t rppairingPort = 49152;

struct DeviceProvider {
    AdapterHandle *adapter;
    RsdHandshakeHandle *handshake;
    HeartbeatClientHandle *heartbeatClient;
    BOOL heartbeatRunning;
};

static dispatch_source_t endpointMonitorTimer = nil;
static NSUInteger endpointMonitorCursor = 0;
static BOOL endpointFailureLatched = NO;

dispatch_queue_t debugServiceQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{
        queue = dispatch_queue_create("com.minh-ton.Reynard.JITSupport.DebugServiceQueue", DISPATCH_QUEUE_CONCURRENT);
    });
    return queue;
}

dispatch_queue_t debugSessionStateQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.minh-ton.Reynard.JITSupport.DebugSessionStateQueue", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static dispatch_queue_t endpointMonitorQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.minh-ton.Reynard.JITSupport.EndpointMonitorQueue", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

NSMutableSet<NSNumber *> *activeDebugSessionPIDs(void) {
    static NSMutableSet<NSNumber *> *activePIDs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        activePIDs = [NSMutableSet set];
    });
    return activePIDs;
}

NSMutableSet<NSNumber *> *detachRequestedDebugSessionPIDs(void) {
    static NSMutableSet<NSNumber *> *requestedPIDs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        requestedPIDs = [NSMutableSet set];
    });
    return requestedPIDs;
}

static void registerDebugSessionPID(int32_t pid) {
    if (pid <= 0) return;
    
    dispatch_sync(debugSessionStateQueue(), ^{
        NSNumber *key = @(pid);
        [activeDebugSessionPIDs() addObject:key];
        [detachRequestedDebugSessionPIDs() removeObject:key];
    });
}

static void unregisterDebugSessionPID(int32_t pid) {
    if (pid <= 0) return;
    
    dispatch_sync(debugSessionStateQueue(), ^{
        NSNumber *key = @(pid);
        [activeDebugSessionPIDs() removeObject:key];
        [detachRequestedDebugSessionPIDs() removeObject:key];
    });
}

static BOOL shouldDetachDebugSessionPID(int32_t pid) {
    if (pid <= 0) return NO;
    
    __block BOOL shouldDetach = NO;
    dispatch_sync(debugSessionStateQueue(), ^{
        shouldDetach = [detachRequestedDebugSessionPIDs() containsObject:@(pid)];
    });
    return shouldDetach;
}

static void startHeartbeat(DeviceProvider *provider) {
    dispatch_queue_t heartbeatQueue = dispatch_queue_create("com.minh-ton.Reynard.JITSupport.ProviderHeartbeatQueue",DISPATCH_QUEUE_SERIAL);
    provider->heartbeatRunning = YES;
    
    dispatch_async(heartbeatQueue, ^{
        uint64_t currentInterval = 2;
        while (provider->heartbeatRunning) {
            uint64_t newInterval = 0;
            IdeviceFfiError *ffiError = heartbeat_get_marco(provider->heartbeatClient, currentInterval, &newInterval);
            
            if (!provider->heartbeatRunning) break;
            
            if (ffiError) {
                idevice_error_free(ffiError);
                break;
            }
            
            ffiError = heartbeat_send_polo(provider->heartbeatClient);
            if (ffiError) {
                idevice_error_free(ffiError);
                break;
            }
        }
    });
}

// MARK: RPPairing JIT enablement on 17.4+

BOOL sendDebugCommand(DebugProxyHandle *debugProxy, NSString *commandString, NSString **responseOut, NSError **error) {
    DebugserverCommandHandle *command = debugserver_command_new(commandString.UTF8String, NULL, 0);
    if (!command) {
        if (error) *error = MakeError(DebugCommandCreateFailed);
        return NO;
    }
    
    char *response = NULL;
    IdeviceFfiError *ffiError = debug_proxy_send_command(debugProxy, command, &response);
    debugserver_command_free(command);
    
    if (ffiError) {
        if (error) *error = MakeError(DebugCommandSendFailed);
        
        idevice_error_free(ffiError);
        if (response) idevice_string_free(response);
        return NO;
    }
    
    if (responseOut) *responseOut = response ? [NSString stringWithUTF8String:response] : nil;
    if (response) idevice_string_free(response);
    
    return YES;
}

static BOOL forwardSignalStop(DebugProxyHandle *debugProxy, NSString *signal, NSString *threadID, NSError **error) {
    NSString *continueCommand = [NSString stringWithFormat:@"vCont;S%@:%@", signal, threadID];
    NSString *stopResponse = nil;
    return sendDebugCommand(debugProxy, continueCommand, &stopResponse, error);
}

static BOOL writeRegisterValue(DebugProxyHandle *debugProxy, NSString *registerName, uint64_t value, NSString *threadID, NSError **error) {
    NSString *response = nil;
    NSString *command = [NSString stringWithFormat:@"P%@=%@;thread:%@;", registerName, encodeLittleEndianHex64(value), threadID];
    
    if (!sendDebugCommand(debugProxy, command, &response, error)) return NO;
    if (response.length > 0 && ![response isEqualToString:@"OK"]) {
        if (error) *error = MakeError(UnexpectedRegisterWriteResponse);
        return NO;
    }
    
    return YES;
}

BOOL configureNoAckMode(DebugProxyHandle *debugProxy, NSString **responseOut, NSError **error) {
    for (NSUInteger ackCount = 0; ackCount < 2; ackCount++) {
        IdeviceFfiError *ffiError = debug_proxy_send_ack(debugProxy);
        if (!ffiError) continue;
        
        if (error) *error = MakeError(NoAckConfigureFailed);
        idevice_error_free(ffiError);
        return NO;
    }
    
    NSString *response = nil;
    if (!sendDebugCommand(debugProxy, @"QStartNoAckMode", &response, error)) return NO;
    if (response.length > 0 && ![response isEqualToString:@"OK"]) {
        if (error) *error = MakeError(UnexpectedNoAckResponse);
        return NO;
    }
    
    debug_proxy_set_ack_mode(debugProxy, 0);
    if (responseOut) {
        *responseOut = response;
    }
    return YES;
}

BOOL connectDebugSession(DeviceProvider *provider, DebugSession *session, NSString *targetAddress, NSError **error) {
    IdeviceFfiError *ffiError = NULL;
    
    NSString *resolvedPairingFilePath = pairingFilePath();
    RpPairingFileHandle *rpPairingFile = NULL;
    ffiError = rp_pairing_file_read(resolvedPairingFilePath.fileSystemRepresentation, &rpPairingFile);
    if (ffiError) {
        if (error) *error = MakeError(PairingFileReadFailed);
        idevice_error_free(ffiError);
        return NO;
    }
    
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(rppairingPort);
    inet_pton(AF_INET, targetAddress.UTF8String, &address.sin_addr);
    
    ffiError = tunnel_create_rppairing(
                                       (const struct sockaddr *)&address,
                                       (socklen_t)sizeof(address),
                                       "ReynardDebug",
                                       rpPairingFile,
                                       NULL, NULL,
                                       &session->adapter, &session->handshake
                                       );
    rp_pairing_file_free(rpPairingFile);
    
    if (ffiError) {
        if (error) *error = MakeError(TunnelCreateFailed);
        idevice_error_free(ffiError);
        return NO;
    }
    
    ffiError = remote_server_connect_rsd(session->adapter, session->handshake, &session->remoteServer);
    if (ffiError) {
        if (error) *error = MakeError(RemoteServerConnectFailed);
        idevice_error_free(ffiError);
        freeDebugSession(session);
        return NO;
    }
    
    ffiError = debug_proxy_connect_rsd(session->adapter, session->handshake, &session->debugProxy);
    if (ffiError) {
        if (error) *error = MakeError(DebugProxyConnectFailed);
        idevice_error_free(ffiError);
        freeDebugSession(session);
        return NO;
    }
    
    return YES;
}

static BOOL prepareMemoryRegion(DebugProxyHandle *debugProxy, uint64_t startAddress, uint64_t regionSize, NSError **error) {
    uint64_t size = regionSize == 0 ? 0x4000 : regionSize;
    
    for (uint64_t currentAddress = startAddress; currentAddress < startAddress + size; currentAddress += 0x4000) {
        NSString *existingByte = nil;
        NSString *readCommand = [NSString stringWithFormat:@"m%llx,1", currentAddress];
        if (!sendDebugCommand(debugProxy, readCommand, &existingByte, error)) return NO;
        
        if (!existingByte || existingByte.length < 2) {
            if (error && !*error)
                *error = MakeError(MemoryPrepareReadFailed);
            return NO;
        }
        
        NSString *command = [NSString stringWithFormat:@"M%llx,1:%@", currentAddress, [existingByte substringToIndex:2]];
        NSString *response = nil;
        
        if (!sendDebugCommand(debugProxy, command, &response, error)) return NO;
        if (response.length > 0 && ![response isEqualToString:@"OK"]) {
            if (error) *error = MakeError(UnexpectedPrepareRegionResponse);
            return NO;
        }
    }
    
    return YES;
}

BOOL detachDebuggerSession(DebugProxyHandle *debugProxy, int32_t pid) {
    NSString *detachResponse = nil;
    NSError *detachError = nil;
    if (sendDebugCommand(debugProxy, @"D", &detachResponse, &detachError)) {
        logger([NSString stringWithFormat:@"Detach response for pid %d: %@", pid, detachResponse ?: @"<no response>"]);
        return YES;
    }
    
    if (!isNotConnectedError(detachError)) {
        logger([NSString stringWithFormat:@"Detach failed for pid %d: %@", pid, detachError.localizedDescription ?: @"detach failed"]);
    }
    return NO;
}

void runDebugService(int32_t pid, DebugSession *session) {
    if (!session) return;
    
    registerDebugSessionPID(pid);
    
    NSError *commandError = nil;
    BOOL exitPacketPresent = NO;
    BOOL detachedByCommand = NO;
    
    while (YES) {
        @autoreleasepool {
            NSString *stopResponse = nil;
            commandError = nil;
            
            if (shouldDetachDebugSessionPID(pid)) {
                detachedByCommand = detachDebuggerSession(session->debugProxy, pid);
                if (detachedByCommand) break;
            }
            
            if (!sendDebugCommand(session->debugProxy, @"c", &stopResponse, &commandError)) {
                if (!isNotConnectedError(commandError)) logger([NSString stringWithFormat:@"Debug loop ended for pid %d: %@", pid, commandError.localizedDescription ?: @"continue failed"]);
                break;
            }
            
            if ([stopResponse hasPrefix:@"W"] || [stopResponse hasPrefix:@"X"]) {
                exitPacketPresent = YES;
                logger([NSString stringWithFormat:@"Target exited for pid %d with packet %@", pid, stopResponse]);
                break;
            }
            
            NSString *threadID = packetField(stopResponse, @"thread");
            NSString *pcField = packetField(stopResponse, @"20");
            NSString *x0Field = packetField(stopResponse, @"00");
            NSString *x1Field = packetField(stopResponse, @"01");
            NSString *x16Field = packetField(stopResponse, @"10");
            
            uint64_t pc = parseLittleEndianHex64(pcField);
            uint64_t x0 = x0Field ? parseLittleEndianHex64(x0Field) : 0;
            uint64_t x1 = x1Field ? parseLittleEndianHex64(x1Field) : 0;
            uint64_t x16 = x16Field ? parseLittleEndianHex64(x16Field) : 0;
            
            NSString *instructionResponse = nil;
            NSString *readInstruction = [NSString stringWithFormat:@"m%llx,4", pc];
            if (!sendDebugCommand(session->debugProxy, readInstruction, &instructionResponse, &commandError)) instructionResponse = nil;
            
            uint32_t instruction = (uint32_t)parseLittleEndianHex64(instructionResponse ?: @"");
            if (instructionResponse.length == 0 || !instructionIsBreakpoint(instruction)) {
                NSString *signal = packetSignal(stopResponse);
                
                // continue with signal
                if (signal && !forwardSignalStop(session->debugProxy, signal, threadID, &commandError)) break;
                continue;
            }
            
            uint16_t breakpointImmediate = (instruction >> 5) & 0xffff;
            
            if (breakpointImmediate == 0xf00d) {
                if (!x0Field || !x1Field || !x16Field) break;
                if (x16 != 1) continue;
                
                if (x0 == 0 && x1 == 0) {
                    if (!writeRegisterValue(session->debugProxy, @"20", pc + 4, threadID, &commandError)) break;
                    continue;
                }
                
                if (x0 == 0) break;
                
                if (!prepareMemoryRegion(session->debugProxy, x0, x1, &commandError)) break;
                if (!writeRegisterValue(session->debugProxy, @"00", x0, threadID, &commandError)) break;
                
                // jump over breakpoint
                if (!writeRegisterValue(session->debugProxy, @"20", pc + 4, threadID, &commandError)) break;
            } else {
                continue;
            }
        }
    }
    
    if (!exitPacketPresent && !detachedByCommand) {
        detachedByCommand = detachDebuggerSession(session->debugProxy, pid);
    }
    
    unregisterDebugSessionPID(pid);
    unregisterJITEndpointForPID(pid);
    freeDebugSession(session);
    free(session);
}

DeviceProvider *createDeviceProvider(NSString *pairingFilePath, NSString *targetAddress, NSError **error) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:pairingFilePath]) {
        if (error) *error = MakeError(PairingFileMissing);
        return NULL;
    }
    
    RpPairingFileHandle *rpPairingFile = NULL;
    IdeviceFfiError *ffiError = rp_pairing_file_read(pairingFilePath.fileSystemRepresentation, &rpPairingFile);
    if (ffiError) {
        if (error) *error = MakeError(PairingFileReadFailed);
        idevice_error_free(ffiError);
        return NULL;
    }
    
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(rppairingPort);
    
    if (inet_pton(AF_INET, targetAddress.UTF8String, &address.sin_addr) != 1) {
        rp_pairing_file_free(rpPairingFile);
        if (error) *error = MakeError(InvalidTargetAddress);
        return NULL;
    }
    
    AdapterHandle *adapter = NULL;
    RsdHandshakeHandle *handshake = NULL;
    ffiError = tunnel_create_rppairing((const struct sockaddr *)&address, (socklen_t)sizeof(address), "Reynard", rpPairingFile, NULL, NULL, &adapter, &handshake);
    rp_pairing_file_free(rpPairingFile);
    
    if (ffiError) {
        if (error) *error = MakeError(TunnelCreateFailed);
        idevice_error_free(ffiError);
        return NULL;
    }
    
    HeartbeatClientHandle *heartbeatClient = NULL;
    ffiError = heartbeat_connect_rsd(adapter, handshake, &heartbeatClient);
    if (ffiError) {
        if (error) *error = MakeError(HeartbeatConnectFailed);
        idevice_error_free(ffiError);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        return NULL;
    }
    
    uint64_t nextInterval = 0;
    ffiError = heartbeat_get_marco(heartbeatClient, 2, &nextInterval);
    if (!ffiError) ffiError = heartbeat_send_polo(heartbeatClient);
    
    DeviceProvider *provider = calloc(1, sizeof(*provider));
    if (!provider) {
        heartbeat_client_free(heartbeatClient);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        if (error) *error = MakeError(DeviceProviderAllocationFailed);
        return NULL;
    }
    
    provider->adapter = adapter;
    provider->handshake = handshake;
    provider->heartbeatClient = heartbeatClient;
    provider->heartbeatRunning = NO;
    
    startHeartbeat(provider);
    
    return provider;
}

void freeDebugSession(DebugSession *session) {
    if (session->debugProxy) { debug_proxy_free(session->debugProxy); session->debugProxy = NULL; }
    if (session->remoteServer) { remote_server_free(session->remoteServer); session->remoteServer = NULL; }
    if (session->handshake) { rsd_handshake_free(session->handshake); session->handshake = NULL; }
    if (session->adapter) { adapter_free(session->adapter); session->adapter = NULL; }
}

void freeDeviceProvider(DeviceProvider *provider) {
    if (!provider) return;
    provider->heartbeatRunning = NO;
    if (provider->heartbeatClient) { heartbeat_client_free(provider->heartbeatClient); provider->heartbeatClient = NULL; }
    if (provider->handshake) { rsd_handshake_free(provider->handshake); provider->handshake = NULL; }
    if (provider->adapter) { adapter_free(provider->adapter); provider->adapter = NULL; }
    free(provider);
}

// MARK: Developer Disk Image Mounting

// There's actually a pretty helpful example from the 'idevice' submodule for this
// at ./support/idevice/cpp/examples/mounter.cpp, so I just ended up copying most
// of the logic from there with only a few modifications here.

static NSURL *ddiDirectoryURL(NSError **error) {
    NSURL *applicationSupportDirectory = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    if (!applicationSupportDirectory) {
        if (error) *error = MakeError(DDIMountPathResolveFailed);
        return nil;
    }
    
    return [applicationSupportDirectory URLByAppendingPathComponent:@"DDI" isDirectory:YES];
}

static NSData *ddiFileData(NSURL *ddiDirectory, NSString *fileName, NSError **error) {
    NSURL *fileURL = [ddiDirectory URLByAppendingPathComponent:fileName isDirectory:NO];
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:&readError];
    if (!data || data.length == 0) {
        if (error) *error = MakeError(DDIFileReadFailed);
        return nil;
    }
    return data;
}

static BOOL isDDIMounted(ImageMounterHandle *mounterClient, BOOL *mountedOut, NSError **error) {
    plist_t *devices = NULL;
    size_t deviceCount = 0;
    IdeviceFfiError *ffiError = image_mounter_copy_devices(mounterClient, &devices, &deviceCount);
    if (ffiError) {
        if (error) *error = MakeError(DDIMountStateQueryFailed);
        idevice_error_free(ffiError);
        return NO;
    }
    
    if (devices) {
        for (size_t index = 0; index < deviceCount; index++) {
            if (devices[index]) plist_free(devices[index]);
        }
        idevice_data_free((uint8_t *)devices, deviceCount * sizeof(plist_t));
    }
    
    if (mountedOut) *mountedOut = deviceCount > 0;
    return YES;
}

BOOL ensureDDIMounted(DeviceProvider *provider, NSError **error) {
    if (!provider || !provider->adapter || !provider->handshake) {
        if (error) *error = MakeError(DeviceProviderCreateFailed);
        return NO;
    }
    
    LockdowndClientHandle *lockdownClient = NULL;
    ImageMounterHandle *mounterClient = NULL;
    IdeviceFfiError *ffiError = NULL;
    plist_t chipIDNode = NULL;
    BOOL mounted = NO;
    NSURL *ddiDirectory = nil;
    NSData *imageData = nil;
    NSData *trustCacheData = nil;
    NSData *buildManifestData = nil;
    uint64_t uniqueChipID = 0;
    BOOL success = NO;
    
    ffiError = image_mounter_connect_rsd(provider->adapter, provider->handshake, &mounterClient);
    if (ffiError) {
        if (error) *error = MakeError(ImageMounterConnectFailed);
        idevice_error_free(ffiError);
        goto cleanup;
    }
    
    if (!isDDIMounted(mounterClient, &mounted, error)) {
        goto cleanup;
    }
    
    if (mounted) {
        success = YES;
        goto cleanup;
    }
    
    ddiDirectory = ddiDirectoryURL(error);
    if (!ddiDirectory) goto cleanup;
    
    imageData = ddiFileData(ddiDirectory, @"Image.dmg", error);
    if (!imageData) goto cleanup;
    
    trustCacheData = ddiFileData(ddiDirectory, @"Image.dmg.trustcache", error);
    if (!trustCacheData) goto cleanup;
    
    buildManifestData = ddiFileData(ddiDirectory, @"BuildManifest.plist", error);
    if (!buildManifestData) goto cleanup;
    
    ffiError = lockdownd_connect_rsd(provider->adapter, provider->handshake, &lockdownClient);
    if (ffiError) {
        if (error) *error = MakeError(LockdowndConnectFailed);
        idevice_error_free(ffiError);
        goto cleanup;
    }
    
    ffiError = lockdownd_get_value(lockdownClient, "UniqueChipID", NULL, &chipIDNode);
    if (ffiError) {
        if (error) *error = MakeError(UniqueChipIDReadFailed);
        idevice_error_free(ffiError);
        goto cleanup;
    }
    
    plist_get_uint_val(chipIDNode, &uniqueChipID);
    if (uniqueChipID == 0) {
        if (error) *error = MakeError(UniqueChipIDInvalid);
        goto cleanup;
    }
    
    ffiError = image_mounter_mount_personalized_rsd(mounterClient, provider->adapter, provider->handshake, imageData.bytes, imageData.length, trustCacheData.bytes, trustCacheData.length, buildManifestData.bytes, buildManifestData.length, NULL, uniqueChipID);
    if (ffiError) {
        if (error) *error = MakeError(ModernDDIMountFailed);
        idevice_error_free(ffiError);
        goto cleanup;
    }
    
    success = YES;
    
cleanup:
    if (chipIDNode) plist_free(chipIDNode);
    if (mounterClient) image_mounter_free(mounterClient);
    if (lockdownClient) lockdownd_client_free(lockdownClient);
    return success;
}

// MARK: Endpoint Connectivity Monitoring

static NSMutableDictionary<NSNumber *, NSDictionary<NSString *, id> *> *monitoredEndpointsByPID(void) {
    static NSMutableDictionary<NSNumber *, NSDictionary<NSString *, id> *> *endpoints;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        endpoints = [NSMutableDictionary dictionary];
    });
    return endpoints;
}

static NSMutableDictionary<NSString *, NSNumber *> *endpointFailureCounts(void) {
    static NSMutableDictionary<NSString *, NSNumber *> *failureCounts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        failureCounts = [NSMutableDictionary dictionary];
    });
    return failureCounts;
}

static void stopEndpointMonitorLocked(void) {
    if (!endpointMonitorTimer) return;
    dispatch_source_cancel(endpointMonitorTimer);
    endpointMonitorTimer = nil;
}

static BOOL probeTCPEndpoint(NSString *targetAddress, uint16_t port, NSTimeInterval timeoutSeconds, int *errorCodeOut) {
    if (errorCodeOut) *errorCodeOut = 0;
    
    int socketFD = socket(AF_INET, SOCK_STREAM, 0);
    if (socketFD < 0) {
        if (errorCodeOut) *errorCodeOut = errno;
        return NO;
    }
    
    int noSigPipe = 1;
    setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
    
    int noDelay = 1;
    setsockopt(socketFD, IPPROTO_TCP, TCP_NODELAY, &noDelay, sizeof(noDelay));
    
    int flags = fcntl(socketFD, F_GETFL, 0);
    if (flags < 0 || fcntl(socketFD, F_SETFL, flags | O_NONBLOCK) < 0) {
        close(socketFD);
        if (errorCodeOut) *errorCodeOut = errno;
        return NO;
    }
    
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    
    if (inet_pton(AF_INET, targetAddress.UTF8String, &address.sin_addr) != 1) {
        close(socketFD);
        if (errorCodeOut) *errorCodeOut = EINVAL;
        return NO;
    }
    
    int connectResult = connect(socketFD, (const struct sockaddr *)&address, sizeof(address));
    if (connectResult == 0) {
        close(socketFD);
        return YES;
    }
    
    if (errno != EINPROGRESS) {
        if (errorCodeOut) *errorCodeOut = errno;
        close(socketFD);
        return NO;
    }
    
    struct timeval timeoutValue;
    timeoutValue.tv_sec = (time_t)timeoutSeconds;
    timeoutValue.tv_usec = (suseconds_t)((timeoutSeconds - timeoutValue.tv_sec) * 1000000.0);
    
    fd_set writeSet;
    FD_ZERO(&writeSet);
    FD_SET(socketFD, &writeSet);
    
    int selectResult = select(socketFD + 1, NULL, &writeSet, NULL, &timeoutValue);
    if (selectResult <= 0) {
        if (errorCodeOut) *errorCodeOut = (selectResult == 0 ? ETIMEDOUT : errno);
        close(socketFD);
        return NO;
    }
    
    int socketError = 0;
    socklen_t socketErrorLength = sizeof(socketError);
    if (getsockopt(socketFD, SOL_SOCKET, SO_ERROR, &socketError, &socketErrorLength) != 0) {
        if (errorCodeOut) *errorCodeOut = errno;
        close(socketFD);
        return NO;
    }
    
    close(socketFD);
    
    if (socketError != 0 && errorCodeOut) *errorCodeOut = socketError;
    return socketError == 0;
}

static NSDictionary<NSString *, id> *endpointEntryForKey(NSString *endpointKey, NSNumber **pidOut) {
    __block NSDictionary<NSString *, id> *matchedEntry = nil;
    __block NSNumber *matchedPID = nil;
    
    [monitoredEndpointsByPID()
     enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull pid, NSDictionary<NSString *, id> * _Nonnull entry, BOOL * _Nonnull stop) {
        NSString *candidateKey = entry[@"key"];
        if (![candidateKey isEqualToString:endpointKey]) return;
        matchedEntry = entry;
        matchedPID = pid;
        *stop = YES;
    }];
    
    if (pidOut) *pidOut = matchedPID;
    return matchedEntry;
}

static void postEndpointConnectivityFailure(NSNumber *pid, NSString *targetAddress, NSNumber *portNumber, NSError *error) {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:4];
    if (pid) userInfo[@"pid"] = pid;
    if (targetAddress) userInfo[@"address"] = targetAddress;
    if (portNumber) userInfo[@"port"] = portNumber;
    if (error) userInfo[@"error"] = error;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"me-minh-ton.jit.endpoint-monitor-failed" object:nil userInfo:userInfo];
    });
}

static void performEndpointMonitorTick(void) {
    NSDictionary<NSNumber *, NSDictionary<NSString *, id> *> *entriesByPID = monitoredEndpointsByPID();
    if (entriesByPID.count == 0) {
        [endpointFailureCounts() removeAllObjects];
        endpointMonitorCursor = 0;
        stopEndpointMonitorLocked();
        return;
    }
    
    NSMutableOrderedSet<NSString *> *uniqueEndpointKeys = [NSMutableOrderedSet orderedSet];
    for (NSDictionary<NSString *, id> *entry in entriesByPID.allValues) {
        NSString *endpointKey = entry[@"key"];
        if (endpointKey.length > 0) [uniqueEndpointKeys addObject:endpointKey];
    }
    
    if (uniqueEndpointKeys.count == 0) return;
    if (endpointMonitorCursor >= uniqueEndpointKeys.count) endpointMonitorCursor = 0;
    
    NSString *endpointKey = uniqueEndpointKeys[endpointMonitorCursor];
    endpointMonitorCursor = (endpointMonitorCursor + 1) % uniqueEndpointKeys.count;
    
    NSNumber *samplePID = nil;
    NSDictionary<NSString *, id> *endpointEntry = endpointEntryForKey(endpointKey, &samplePID);
    NSString *targetAddress = endpointEntry[@"address"];
    NSNumber *portNumber = endpointEntry[@"port"];
    
    if (targetAddress.length == 0 || !portNumber) return;
    
    uint16_t port = (uint16_t)portNumber.unsignedShortValue;
    BOOL endpointHealthy = probeTCPEndpoint(targetAddress, port, 0.35, NULL);
    
    if (endpointHealthy) {
        [endpointFailureCounts() removeObjectForKey:endpointKey];
        return;
    }
    
    NSMutableDictionary<NSString *, NSNumber *> *failureCounts = endpointFailureCounts();
    NSUInteger failureCount = [failureCounts[endpointKey] unsignedIntegerValue] + 1;
    failureCounts[endpointKey] = @(failureCount);
    
    if (failureCount < 2) return;
    
    endpointFailureLatched = YES;
    stopEndpointMonitorLocked();
    
    NSError *connectivityError = MakeError(EndpointConnectivityLost);
    postEndpointConnectivityFailure(samplePID, targetAddress, portNumber, connectivityError);
}

static void startEndpointMonitorLocked(void) {
    if (endpointMonitorTimer || endpointFailureLatched) return;
    
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, endpointMonitorQueue());
    if (!timer) return;
    
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), (uint64_t)NSEC_PER_SEC, NSEC_PER_MSEC * 100);
    dispatch_source_set_event_handler(timer, ^{
        performEndpointMonitorTick();
    });
    
    endpointMonitorTimer = timer;
    dispatch_resume(timer);
}

void registerJITEndpointForPID(int32_t pid, NSString *targetAddress, uint16_t port) {
    if (pid <= 0 || targetAddress.length == 0 || port == 0) return;
    
    dispatch_async(endpointMonitorQueue(), ^{
        NSString *endpointKey = [NSString stringWithFormat:@"%@:%u", targetAddress, port];
        monitoredEndpointsByPID()[@(pid)] = @{
            @"key": endpointKey,
            @"address": [targetAddress copy],
            @"port": @(port),
        };
        
        [endpointFailureCounts() removeObjectForKey:endpointKey];
        startEndpointMonitorLocked();
    });
}

void unregisterJITEndpointForPID(int32_t pid) {
    if (pid <= 0) return;
    
    dispatch_async(endpointMonitorQueue(), ^{
        [monitoredEndpointsByPID() removeObjectForKey:@(pid)];
        
        if (monitoredEndpointsByPID().count == 0) {
            [endpointFailureCounts() removeAllObjects];
            endpointMonitorCursor = 0;
            stopEndpointMonitorLocked();
        }
    });
}

void resetJITEndpointMonitor(void) {
    dispatch_sync(endpointMonitorQueue(), ^{
        [monitoredEndpointsByPID() removeAllObjects];
        [endpointFailureCounts() removeAllObjects];
        endpointMonitorCursor = 0;
        endpointFailureLatched = NO;
        stopEndpointMonitorLocked();
    });
}
