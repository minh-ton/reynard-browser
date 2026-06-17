//
//  JITSupport.m
//  Reynard
//
//  Created by Minh Ton on 11/3/2026.
//

#import "JITSupport.h"
#import "JITUtils.h"
#import "IdeviceFFI.h"
#import <Security/Security.h>

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <netinet/tcp.h>
#include <unistd.h>

static const char *providerLabel = "Reynard";
static const uint16_t lockdownPort = 62078;
static const uint16_t rppairingPort = 49152;
static const NSTimeInterval debugPacketTimeoutSeconds = 2.0;

static const char *const legacyDebugServiceIdentifier = "com.apple.debugserver.DVTSecureSocketProxy";

struct DeviceProvider {
    IdeviceProviderHandle *handle;
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
        queue = dispatch_queue_create("me.minh-ton.jit.debug-service", DISPATCH_QUEUE_CONCURRENT);
    });
    return queue;
}

dispatch_queue_t debugSessionStateQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("me.minh-ton.jit.debug-service-state", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static dispatch_queue_t endpointMonitorQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("me.minh-ton.jit.endpoint-monitor", DISPATCH_QUEUE_SERIAL);
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
    dispatch_queue_t heartbeatQueue = dispatch_queue_create("me.minh-ton.jit.provider-heartbeat",DISPATCH_QUEUE_SERIAL);
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

// MARK: JIT on iOS 17+

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
    
    if (__builtin_available(iOS 17.4, *)) {
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
        ffiError = tunnel_create_rppairing(
                                           (const struct sockaddr *)&address,
                                           (socklen_t)sizeof(address),
                                           "Reynard",
                                           rpPairingFile,
                                           NULL, NULL,
                                           &adapter, &handshake
                                           );
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
            if (heartbeatClient) heartbeat_client_free(heartbeatClient);
            rsd_handshake_free(handshake);
            adapter_free(adapter);
            if (error) *error = MakeError(DeviceProviderAllocationFailed);
            return NULL;
        }
        
        provider->handle = NULL;
        provider->adapter = adapter;
        provider->handshake = handshake;
        provider->heartbeatClient = heartbeatClient;
        provider->heartbeatRunning = NO;
        
        if (heartbeatClient) startHeartbeat(provider);
        
        return provider;
    }
    
    IdevicePairingFile *pairingFile = NULL;
    IdeviceFfiError *ffiError = idevice_pairing_file_read(pairingFilePath.fileSystemRepresentation, &pairingFile);
    
    if (ffiError) {
        if (error) *error = MakeError(PairingFileReadFailed);
        idevice_error_free(ffiError);
        return NULL;
    }
    
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(lockdownPort);
    
    if (inet_pton(AF_INET, targetAddress.UTF8String, &address.sin_addr) != 1) {
        idevice_pairing_file_free(pairingFile);
        if (error) *error = MakeError(InvalidTargetAddress);
        return NULL;
    }
    
    IdeviceProviderHandle *providerHandle = NULL;
    ffiError = idevice_tcp_provider_new((const struct sockaddr *)&address, pairingFile, providerLabel, &providerHandle);
    if (ffiError) {
        if (error) *error = MakeError(DeviceProviderCreateFailed);
        idevice_error_free(ffiError);
        return NULL;
    }
    
    DeviceProvider *provider = calloc(1, sizeof(*provider));
    if (!provider) {
        idevice_provider_free(providerHandle);
        if (error) *error = MakeError(DeviceProviderAllocationFailed);
        return NULL;
    }
    
    HeartbeatClientHandle *heartbeatClient = NULL;
    ffiError = heartbeat_connect(providerHandle, &heartbeatClient);
    if (ffiError) {
        if (error) *error = MakeError(HeartbeatConnectFailed);
        idevice_error_free(ffiError);
        idevice_provider_free(providerHandle);
        return NULL;
    }
    
    uint64_t nextInterval = 0;
    ffiError = heartbeat_get_marco(heartbeatClient, 15, &nextInterval);
    if (!ffiError) ffiError = heartbeat_send_polo(heartbeatClient);
    
    provider->handle = providerHandle;
    provider->adapter = NULL;
    provider->handshake = NULL;
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
    if (provider->handle) { idevice_provider_free(provider->handle); provider->handle = NULL; }
    free(provider);
}

// MARK: JIT on pre-iOS 17

// This JIT enablement method requires a lot of the TLS things to be
// re-implemented. So thanks LLM for helping me with this I guess?
// And I'm also going to add a TODO: Find a better way (or a library) for these TLS mess.

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static BOOL configureLegacyDebugTLS(LegacyDebugConnection *connection, NSError **error) {
    if (!connection || connection->socketFD < 0) {
        if (error) *error = MakeError(LegacyTLSConfigurationFailed);
        return NO;
    }
    
    SSLContextRef sslContext = SSLCreateContext(kCFAllocatorDefault, kSSLClientSide, kSSLStreamType);
    if (!sslContext) {
        if (error) *error = MakeError(LegacyTLSConfigurationFailed);
        return NO;
    }
    
    OSStatus status = SSLSetIOFuncs(sslContext, legacySSLRead, legacySSLWrite);
    if (status != noErr) {
        if (error) *error = MakeError(LegacyTLSConfigurationFailed);
        CFRelease(sslContext);
        return NO;
    }
    
    int *connectionSocket = &connection->socketFD;
    status = SSLSetConnection(sslContext, connectionSocket);
    if (status != noErr) {
        if (error) *error = MakeError(LegacyTLSConfigurationFailed);
        CFRelease(sslContext);
        return NO;
    }
    
    SSLSetProtocolVersionMin(sslContext, kTLSProtocol1);
    SSLSetProtocolVersionMax(sslContext, kTLSProtocol12);
    SSLSetSessionOption(sslContext, kSSLSessionOptionBreakOnServerAuth, true);
    
    NSError *identityError = nil;
    SecIdentityRef identity = copyLegacyPairingIdentity(&identityError);
    if (!identity) {
        if (error) *error = identityError ?: MakeError(TLSIdentityCreateFailed);
        CFRelease(sslContext);
        return NO;
    }
    
    const void *identityValues[] = { identity };
    CFArrayRef certificateChain = CFArrayCreate(NULL, identityValues, 1, &kCFTypeArrayCallBacks);
    OSStatus statusSetCert = SSLSetCertificate(sslContext, certificateChain);
    CFRelease(certificateChain);
    CFRelease(identity);
    if (statusSetCert != noErr) {
        if (error) *error = MakeError(LegacyTLSConfigurationFailed);
        CFRelease(sslContext);
        return NO;
    }
    
    while (YES) {
        status = SSLHandshake(sslContext);
        if (status == noErr) break;
        if (status == errSSLWouldBlock) continue;
        if (status == errSSLServerAuthCompleted) continue;
        
        if (error) *error = MakeError(LegacyTLSConfigurationFailed);
        CFRelease(sslContext);
        return NO;
    }
    
    connection->sslContext = sslContext;
    return YES;
}

void closeLegacyDebugConnection(LegacyDebugConnection *connection) {
    if (!connection) return;
    if (connection->sslContext) { SSLClose(connection->sslContext); CFRelease(connection->sslContext); connection->sslContext = NULL; }
    if (connection->socketFD >= 0) { close(connection->socketFD); connection->socketFD = -1; }
}

static BOOL sendAllBytes(LegacyDebugConnection *connection, const uint8_t *bytes, size_t length, NSError **error) {
    if (!connection || connection->socketFD < 0 || !connection->sslContext) {
        if (error) *error = MakeError(LegacyTLSConnectionMissing);
        return NO;
    }
    
    size_t bytesWritten = 0;
    while (bytesWritten < length) {
        size_t processedLength = length - bytesWritten;
        OSStatus status = SSLWrite(connection->sslContext, bytes + bytesWritten, processedLength, &processedLength);
        
        if (status == noErr) {
            bytesWritten += processedLength;
            continue;
        }
        
        if (status == errSSLWouldBlock) continue;
        
        if (error) *error = MakeError(LegacyTLSConfigurationFailed);
        
        return NO;
    }
    
    return YES;
}

static BOOL readByteWithTimeout(LegacyDebugConnection *connection, NSTimeInterval timeout, char *byteOut, BOOL *timedOut, NSError **error) {
    if (timedOut) *timedOut = NO;
    
    if (!connection || connection->socketFD < 0 || !connection->sslContext) {
        if (error) *error = MakeError(LegacyTLSConnectionMissing);
        return NO;
    }
    
    size_t processedLength = 1;
    OSStatus status = SSLRead(connection->sslContext, byteOut, 1, &processedLength);
    if (status == noErr && processedLength == 1) return YES;
    
    if (status == errSSLWouldBlock) {
        if (timedOut) *timedOut = YES;
        return YES;
    }
    
    if (status == errSSLClosedGraceful || status == errSSLClosedAbort) {
        if (error) *error = MakeError(LegacyTLSConnectionClosed);
        return NO;
    }
    
    if (error) *error = MakeError(LegacyTLSReadFailed);
    return NO;
}

#pragma clang diagnostic pop

static BOOL readLegacyDebugResponse(LegacyDebugConnection *connection, NSString **responseOut, NSError **error) {
    while (YES) {
        char marker = 0;
        BOOL timedOut = NO;
        if (!readByteWithTimeout(connection, debugPacketTimeoutSeconds, &marker, &timedOut, error)) return NO;
        if (timedOut) {
            if (responseOut) *responseOut = nil;
            return YES;
        }
        
        if (marker == '+') continue;
        if (marker == '-') {
            if (error) *error = MakeError(LegacyProtocolNackReceived);
            return NO;
        }
        if (marker != '$') continue;
        
        NSMutableData *payloadData = [NSMutableData data];
        while (YES) {
            char payloadByte = 0;
            timedOut = NO;
            if (!readByteWithTimeout(connection, debugPacketTimeoutSeconds, &payloadByte, &timedOut, error)) return NO;
            if (timedOut) {
                if (error) *error = MakeError(LegacyProtocolPayloadTimeout);
                return NO;
            }
            
            if (payloadByte == '#') break;
            [payloadData appendBytes:&payloadByte length:1];
        }
        
        char checksumChars[3] = {0};
        for (NSUInteger index = 0; index < 2; index++) {
            BOOL checksumTimedOut = NO;
            if (!readByteWithTimeout(connection, debugPacketTimeoutSeconds, &checksumChars[index], &checksumTimedOut, error)) return NO;
            
            if (checksumTimedOut) {
                if (error) *error = MakeError(LegacyProtocolChecksumTimeout);
                return NO;
            }
        }
        
        unsigned int providedChecksum = 0;
        if (sscanf(checksumChars, "%2x", &providedChecksum) != 1 ||
            (uint8_t)providedChecksum != packetChecksum(payloadData.bytes, payloadData.length)) {
            if (error) *error = MakeError(LegacyProtocolChecksumMismatch);
            return NO;
        }
        
        const uint8_t ack = '+';
        if (!sendAllBytes(connection, &ack, 1, error)) return NO;
        
        NSString *response = [[NSString alloc] initWithData:payloadData encoding:NSUTF8StringEncoding];
        if (!response) response = [[NSString alloc] initWithData:payloadData encoding:NSISOLatin1StringEncoding];
        if (!response) response = @"";
        
        if (responseOut) *responseOut = response;
        return YES;
    }
}

static BOOL sendLegacyDebugPacket(LegacyDebugConnection *connection, NSString *command, NSError **error) {
    NSData *payloadData = [command dataUsingEncoding:NSUTF8StringEncoding];
    if (!payloadData) {
        if (error) *error = MakeError(LegacyCommandEncodingFailed);
        return NO;
    }
    
    uint8_t checksum = packetChecksum(payloadData.bytes, payloadData.length);
    char checksumChars[3] = {0};
    snprintf(checksumChars, sizeof(checksumChars), "%02x", checksum);
    
    NSMutableData *packetData = [NSMutableData dataWithCapacity:payloadData.length + 4];
    const uint8_t packetStart = '$';
    const uint8_t packetEnd = '#';
    [packetData appendBytes:&packetStart length:1];
    [packetData appendData:payloadData];
    [packetData appendBytes:&packetEnd length:1];
    [packetData appendBytes:checksumChars length:2];
    
    return sendAllBytes(connection, packetData.bytes, packetData.length, error);
}

BOOL sendLegacyDebugCommand(LegacyDebugConnection *connection, NSString *command, NSString **responseOut, NSError **error) {
    if (!sendLegacyDebugPacket(connection, command, error)) {
        if (error && !*error) *error = MakeError(LegacyDebugCommandPacketFailed);
        return NO;
    }
    
    if (!readLegacyDebugResponse(connection, responseOut, error)) {
        if (error && !*error) *error = MakeError(LegacyDebugCommandResponseFailed);
        return NO;
    }
    
    return YES;
}

BOOL connectLegacyDebugSocket(NSString *targetAddress, uint16_t port, LegacyDebugConnection *connectionOut, NSError **error) {
    if (!connectionOut) {
        if (error) *error = MakeError(LegacyOutputConnectionMissing);
        return NO;
    }
    
    connectionOut->socketFD = -1;
    connectionOut->sslContext = NULL;
    
    int socketFD = socket(AF_INET, SOCK_STREAM, 0);
    if (socketFD < 0) {
        if (error) *error = MakeError(LegacySocketCreateFailed);
        return NO;
    }
    
    int noSigPipe = 1;
    setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
    int noDelay = 1;
    setsockopt(socketFD, IPPROTO_TCP, TCP_NODELAY, &noDelay, sizeof(noDelay));
    applyLegacyDebugSocketTimeouts(socketFD);
    
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    
    if (inet_pton(AF_INET, targetAddress.UTF8String, &address.sin_addr) != 1) {
        close(socketFD);
        if (error) *error = MakeError(LegacySocketInvalidAddress);
        return NO;
    }
    
    if (connect(socketFD, (const struct sockaddr *)&address, sizeof(address)) != 0) {
        close(socketFD);
        if (error) *error = MakeError(LegacySocketConnectFailed);
        return NO;
    }
    
    connectionOut->socketFD = socketFD;
    
    if (!configureLegacyDebugTLS(connectionOut, error)) {
        if (error && !*error) *error = MakeError(LegacySocketTLSSetupFailed);
        closeLegacyDebugConnection(connectionOut);
        return NO;
    }
    
    return YES;
}

BOOL startLegacyDebugService(DeviceProvider *provider, uint16_t *portOut, NSError **error) {
    LockdowndClientHandle *lockdownClient = NULL;
    IdevicePairingFile *pairingFile = NULL;
    IdeviceFfiError *ffiError = NULL;
    BOOL success = NO;
    
    ffiError = lockdownd_connect(provider->handle, &lockdownClient);
    if (ffiError) {
        if (error) *error = MakeError(LockdowndConnectFailed);
        idevice_error_free(ffiError);
        return NO;
    }
    
    ffiError = idevice_provider_get_pairing_file(provider->handle, &pairingFile);
    if (ffiError) {
        if (error) *error = MakeError(ProviderPairingFileFetchFailed);
        idevice_error_free(ffiError);
        goto cleanup;
    }
    
    ffiError = lockdownd_start_session(lockdownClient, pairingFile);
    if (ffiError) {
        if (error) *error = MakeError(LockdowndSessionStartFailed);
        idevice_error_free(ffiError);
        goto cleanup;
    }
    
    uint16_t debugPort = 0;
    bool enableSSL = false;
    ffiError = lockdownd_start_service(lockdownClient, legacyDebugServiceIdentifier, &debugPort, &enableSSL);
    if (ffiError) {
        if (error) *error = MakeError(LockdowndStartServiceFailed);
        idevice_error_free(ffiError);
        goto cleanup;
    }
    
    if (!enableSSL) {
        if (error) *error = MakeError(LegacyServiceTLSNotEnabled);
        goto cleanup;
    }
    
    if (portOut) *portOut = debugPort;
    success = YES;
    
cleanup:
    if (pairingFile) idevice_pairing_file_free(pairingFile);
    if (lockdownClient) lockdownd_client_free(lockdownClient);
    return success;
}

BOOL detachLegacyDebuggerSession(LegacyDebugConnection *connection, int32_t pid) {
    NSString *detachResponse = nil;
    NSError *detachError = nil;
    if (sendLegacyDebugCommand(connection, @"D", &detachResponse, &detachError)) {
        logger([NSString stringWithFormat:@"Legacy detach response for pid %d: %@", pid, detachResponse ?: @"<no response>"]);
        return YES;
    }
    
    if (!isNotConnectedError(detachError)) {
        logger([NSString stringWithFormat:@"Legacy detach failed for pid %d: %@", pid, detachError.localizedDescription ?: @"detach failed"]);
    }
    return NO;
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

static BOOL isImageMounted(ImageMounterHandle *mounterClient, const char *imageType, BOOL *mountedOut, NSError **error) {
    uint8_t *signature = NULL;
    size_t signatureLength = 0;
    
    IdeviceFfiError *ffiError = image_mounter_lookup_image(mounterClient, imageType, &signature, &signatureLength);
    if (!ffiError) {
        if (signature) idevice_data_free(signature, signatureLength);
        if (mountedOut) *mountedOut = YES;
        return YES;
    }
    
    BOOL notFound = ffiError->code == -14;
    idevice_error_free(ffiError);
    
    if (notFound) {
        if (mountedOut) *mountedOut = NO;
        return YES;
    }
    
    if (error) *error = MakeError(DDIMountStateQueryFailed);
    return NO;
}

BOOL ensureDDIMounted(DeviceProvider *provider, NSError **error) {
    if (!provider) {
        if (error) *error = MakeError(DeviceProviderCreateFailed);
        return NO;
    }
    
    NSURL *ddiDirectory = ddiDirectoryURL(error);
    if (!ddiDirectory) return NO;
    
    LockdowndClientHandle *lockdownClient = NULL;
    IdevicePairingFile *pairingFile = NULL;
    ImageMounterHandle *mounterClient = NULL;
    IdeviceFfiError *ffiError = NULL;
    plist_t versionNode = NULL;
    plist_t chipIDNode = NULL;
    char *versionCString = NULL;
    NSString *versionString = nil;
    NSInteger majorVersion = 0;
    const char *imageType = NULL;
    BOOL mounted = NO;
    NSData *legacyImageData = nil;
    NSData *legacySignatureData = nil;
    NSData *modernImageData = nil;
    NSData *modernTrustCacheData = nil;
    NSData *modernBuildManifestData = nil;
    uint64_t uniqueChipID = 0;
    BOOL success = NO;
    
    if (__builtin_available(iOS 17.4, *)) {
        if (!provider->adapter || !provider->handshake) {
            if (error) *error = MakeError(DeviceProviderCreateFailed);
            return NO;
        }
        
        ffiError = lockdownd_connect_rsd(provider->adapter, provider->handshake, &lockdownClient);
        if (ffiError) {
            if (error) *error = MakeError(LockdowndConnectFailed);
            idevice_error_free(ffiError);
            goto cleanup;
        }
    } else {
        if (!provider->handle) {
            if (error) *error = MakeError(DeviceProviderCreateFailed);
            return NO;
        }
        
        ffiError = lockdownd_connect(provider->handle, &lockdownClient);
        if (ffiError) {
            if (error) *error = MakeError(LockdowndConnectFailed);
            idevice_error_free(ffiError);
            goto cleanup;
        }
        
        ffiError = idevice_provider_get_pairing_file(provider->handle, &pairingFile);
        if (ffiError) {
            if (error) *error = MakeError(ProviderPairingFileFetchFailed);
            idevice_error_free(ffiError);
            goto cleanup;
        }
        
        ffiError = lockdownd_start_session(lockdownClient, pairingFile);
        if (ffiError) {
            if (error) *error = MakeError(LockdowndSessionStartFailed);
            idevice_error_free(ffiError);
            goto cleanup;
        }
    }
    
    ffiError = lockdownd_get_value(lockdownClient, "ProductVersion", NULL, &versionNode);
    if (ffiError) {
        if (error) *error = MakeError(DDIDeviceVersionReadFailed);
        idevice_error_free(ffiError);
        goto cleanup;
    }
    
    plist_get_string_val(versionNode, &versionCString);
    if (!versionCString) {
        if (error) *error = MakeError(DDIDeviceVersionInvalid);
        goto cleanup;
    }
    
    versionString = [NSString stringWithUTF8String:versionCString] ?: @"";
    majorVersion = versionString.integerValue;
    if (majorVersion <= 0) {
        if (error) *error = MakeError(DDIDeviceVersionInvalid);
        goto cleanup;
    }
    
    if (__builtin_available(iOS 17.4, *)) {
        ffiError = image_mounter_connect_rsd(provider->adapter, provider->handshake, &mounterClient);
    } else {
        ffiError = image_mounter_connect(provider->handle, &mounterClient);
    }
    if (ffiError) {
        if (error) *error = MakeError(ImageMounterConnectFailed);
        idevice_error_free(ffiError);
        goto cleanup;
    }
    
    imageType = majorVersion < 17 ? "Developer" : "Personalized";
    if (!isImageMounted(mounterClient, imageType, &mounted, error)) {
        goto cleanup;
    }
    
    if (mounted) {
        success = YES;
        goto cleanup;
    }
    
    if (majorVersion < 17) {
        legacyImageData = ddiFileData(ddiDirectory, @"DeveloperDiskImage.dmg", error);
        if (!legacyImageData) goto cleanup;
        
        legacySignatureData = ddiFileData(ddiDirectory, @"DeveloperDiskImage.dmg.signature", error);
        if (!legacySignatureData) goto cleanup;
        
        ffiError = image_mounter_mount_developer(mounterClient, legacyImageData.bytes, legacyImageData.length, legacySignatureData.bytes, legacySignatureData.length);
        if (ffiError) {
            if (error) *error = MakeError(LegacyDDIMountFailed);
            idevice_error_free(ffiError);
            goto cleanup;
        }
        
        success = YES;
        goto cleanup;
    }
    
    modernImageData = ddiFileData(ddiDirectory, @"Image.dmg", error);
    if (!modernImageData) goto cleanup;
    
    modernTrustCacheData = ddiFileData(ddiDirectory, @"Image.dmg.trustcache", error);
    if (!modernTrustCacheData) goto cleanup;
    
    modernBuildManifestData = ddiFileData(ddiDirectory, @"BuildManifest.plist", error);
    if (!modernBuildManifestData) goto cleanup;
    
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
    
    if (__builtin_available(iOS 17.4, *)) {
        ffiError = image_mounter_mount_personalized_rsd(mounterClient, provider->adapter, provider->handshake, modernImageData.bytes, modernImageData.length, modernTrustCacheData.bytes, modernTrustCacheData.length, modernBuildManifestData.bytes, modernBuildManifestData.length, NULL, uniqueChipID);
    } else {
        ffiError = image_mounter_mount_personalized(mounterClient, provider->handle, modernImageData.bytes, modernImageData.length, modernTrustCacheData.bytes, modernTrustCacheData.length, modernBuildManifestData.bytes, modernBuildManifestData.length, NULL, uniqueChipID);
    }
    
    if (ffiError) {
        if (error) *error = MakeError(ModernDDIMountFailed);
        idevice_error_free(ffiError);
        goto cleanup;
    }
    
    success = YES;
    
cleanup:
    if (versionCString) free(versionCString);
    if (chipIDNode) plist_free(chipIDNode);
    if (versionNode) plist_free(versionNode);
    if (mounterClient) image_mounter_free(mounterClient);
    if (pairingFile) idevice_pairing_file_free(pairingFile);
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
