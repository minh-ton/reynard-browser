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
#include <netinet/tcp.h>
#include <sys/select.h>
#include <unistd.h>

static const char *providerLabel = "Reynard";
static const uint16_t lockdownPort = 62078;
static const NSTimeInterval debugPacketTimeoutSeconds = 2.0;

static const char *const legacyDebugServiceIdentifiers[] = {
    "com.apple.debugserver",
    "com.apple.debugserver.DVTSecureSocketProxy",
};

static const size_t legacyDebugServiceIdentifierCount = sizeof(legacyDebugServiceIdentifiers) / sizeof(legacyDebugServiceIdentifiers[0]);

struct DeviceProvider {
    IdeviceProviderHandle *handle;
    HeartbeatClientHandle *heartbeatClient;
    BOOL heartbeatRunning;
};

dispatch_queue_t debugServiceQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{
        queue = dispatch_queue_create("me.minh-ton.jit.debug-service", DISPATCH_QUEUE_CONCURRENT);
    });
    return queue;
}

// MARK: JIT on iOS 17+

static void startHeartbeat(DeviceProvider *provider) {
    dispatch_queue_t heartbeatQueue = dispatch_queue_create("me.minh-ton.jit.provider-heartbeat",DISPATCH_QUEUE_SERIAL);
    provider->heartbeatRunning = YES;
    
    dispatch_async(heartbeatQueue, ^{
        uint64_t currentInterval = 15;
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
            
            currentInterval = (newInterval > 0) ? (newInterval + 5) : 15;
        }
    });
}

BOOL sendDebugCommand(DebugProxyHandle *debugProxy, NSString *commandString, NSString **responseOut, NSError **error) {
    DebugserverCommandHandle *command = debugserver_command_new(commandString.UTF8String, NULL, 0);
    if (!command) {
        if (error) *error = errorWithCode(-6, [NSString stringWithFormat:@"Failed to create debugserver command %@", commandString]);
        return NO;
    }
    
    char *response = NULL;
    IdeviceFfiError *ffiError = debug_proxy_send_command(debugProxy, command, &response);
    debugserver_command_free(command);
    
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithFormat:@"Debug command %@ failed: %@", commandString, [NSString stringWithUTF8String:ffiError->message ?: "unknown error"]];
            *error = errorWithCode(ffiError->code, description);
        }
        
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
        if (error) *error = errorWithCode(-7, [NSString stringWithFormat:@"Unexpected register write response %@", response]);
        return NO;
    }
    
    return YES;
}

BOOL configureNoAckMode(DebugProxyHandle *debugProxy, NSString **responseOut, NSError **error) {
    for (NSUInteger ackCount = 0; ackCount < 2; ackCount++) {
        IdeviceFfiError *ffiError = debug_proxy_send_ack(debugProxy);
        if (!ffiError) continue;
        
        if (error) {
            NSString *description = [NSString stringWithFormat:@"Failed to send debug ACK: %@", [NSString stringWithUTF8String:ffiError->message ?: "unknown error"]];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        return NO;
    }
    
    NSString *response = nil;
    if (!sendDebugCommand(debugProxy, @"QStartNoAckMode", &response, error)) return NO;
    if (response.length > 0 && ![response isEqualToString:@"OK"]) {
        if (error) *error = errorWithCode(-9, [NSString stringWithFormat:@"Unexpected no-ack response %@", response]);
        return NO;
    }
    
    debug_proxy_set_ack_mode(debugProxy, 0);
    if (responseOut) {
        *responseOut = response;
    }
    return YES;
}

BOOL connectDebugSession(DeviceProvider *provider, DebugSession *session, NSError **error) {
    IdeviceFfiError *ffiError = NULL;
    CoreDeviceProxyHandle *coreDevice = NULL;
    ReadWriteOpaque *stream = NULL;
    
    ffiError = core_device_proxy_connect(provider->handle, &coreDevice);
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Failed to connect CoreDeviceProxy."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        return NO;
    }
    
    uint16_t rsdPort = 0;
    ffiError = core_device_proxy_get_server_rsd_port(coreDevice, &rsdPort);
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Failed to resolve RSD port."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        core_device_proxy_free(coreDevice);
        return NO;
    }
    
    ffiError = core_device_proxy_create_tcp_adapter(coreDevice, &session->adapter);
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Failed to create CoreDevice adapter."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        core_device_proxy_free(coreDevice);
        return NO;
    }
    coreDevice = NULL;
    
    ffiError = adapter_connect(session->adapter, rsdPort, &stream);
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Failed to connect adapter stream."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        freeDebugSession(session);
        return NO;
    }
    
    ffiError = rsd_handshake_new(stream, &session->handshake);
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Failed to complete RSD handshake."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        freeDebugSession(session);
        return NO;
    }
    stream = NULL;
    
    ffiError = remote_server_connect_rsd(session->adapter, session->handshake, &session->remoteServer);
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Failed to connect remote server."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        freeDebugSession(session);
        return NO;
    }
    
    ffiError = debug_proxy_connect_rsd(session->adapter, session->handshake, &session->debugProxy);
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Failed to connect debug proxy."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        freeDebugSession(session);
        return NO;
    }
    
    return YES;
}

static BOOL prepareMemoryRegion(DebugProxyHandle *debugProxy, uint64_t startAddress, uint64_t regionSize, uint64_t writableSourceAddress, NSError **error) {
    uint64_t size = regionSize == 0 ? 0x4000 : regionSize;
    
    for (uint64_t currentAddress = startAddress; currentAddress < startAddress + size; currentAddress += 0x4000) {
        uint64_t sourceAddress = currentAddress;
        if (writableSourceAddress != 0) sourceAddress = writableSourceAddress + (currentAddress - startAddress);
        
        NSString *existingByte = nil;
        NSString *readCommand = [NSString stringWithFormat:@"m%llx,1", sourceAddress];
        if (!sendDebugCommand(debugProxy, readCommand, &existingByte, error)) return NO;
        
        if (!existingByte || existingByte.length < 2) {
            if (error && !*error)
                *error = errorWithCode(-12, [NSString stringWithFormat:@"Failed to read prepare-region byte at 0x%llx (source 0x%llx)", currentAddress, sourceAddress]);
            return NO;
        }
        
        NSString *command = [NSString stringWithFormat:@"M%llx,1:%@", currentAddress, [existingByte substringToIndex:2]];
        NSString *response = nil;
        
        if (!sendDebugCommand(debugProxy, command, &response, error)) return NO;
        if (response.length > 0 && ![response isEqualToString:@"OK"]) {
            if (error) *error = errorWithCode(-7, [NSString stringWithFormat:@"Unexpected prepare-region response %@", response]);
            return NO;
        }
    }
    
    return YES;
}

static BOOL allocateRXRegion(DebugProxyHandle *debugProxy, uint64_t regionSize, uint64_t *addressOut, NSError **error) {
    NSString *response = nil;
    NSString *command = [NSString stringWithFormat:@"_M%llx,rx", regionSize];
    
    if (!sendDebugCommand(debugProxy, command, &response, error)) return NO;
    
    if (response.length == 0) {
        if (error) *error = errorWithCode(-10, @"RX allocation returned an empty response.");
        return NO;
    }
    
    uint64_t address = 0;
    NSScanner *scanner = [NSScanner scannerWithString:response];
    if (![scanner scanHexLongLong:&address]) {
        if (error) *error = errorWithCode(-11, [NSString stringWithFormat:@"RX allocation returned invalid address %@", response]);
        return NO;
    }
    
    if (addressOut) *addressOut = address;
    return YES;
}

void runDebugService(int32_t pid, DebugSession *session, DeviceLogHandler logHandler) {
    NSError *commandError = nil;
    BOOL exitPacketPresent = NO;
    BOOL detachedByCommand = NO;
    
    while (YES) {
        NSString *stopResponse = nil;
        commandError = nil;
        
        if (!sendDebugCommand(session->debugProxy, @"c", &stopResponse, &commandError)) {
            if (!isNotConnectedError(commandError)) logger([NSString stringWithFormat:@"Debug loop ended for pid %d: %@", pid, commandError.localizedDescription ?: @"continue failed"], logHandler);
            break;
        }
        
        if ([stopResponse hasPrefix:@"W"] || [stopResponse hasPrefix:@"X"]) {
            exitPacketPresent = YES;
            logger([NSString stringWithFormat:@"Target exited for pid %d with packet %@", pid, stopResponse], logHandler);
            break;
        }
        
        NSString *threadID = packetField(stopResponse, @"thread");
        NSString *pcField = packetField(stopResponse, @"20");
        NSString *x0Field = packetField(stopResponse, @"00");
        NSString *x1Field = packetField(stopResponse, @"01");
        NSString *x2Field = packetField(stopResponse, @"02");
        NSString *x16Field = packetField(stopResponse, @"10");
        
        uint64_t pc = parseLittleEndianHex64(pcField);
        uint64_t x0 = x0Field ? parseLittleEndianHex64(x0Field) : 0;
        uint64_t x1 = x1Field ? parseLittleEndianHex64(x1Field) : 0;
        uint64_t x2 = x2Field ? parseLittleEndianHex64(x2Field) : 0;
        uint64_t x16 = x16Field ? parseLittleEndianHex64(x16Field) : 0;
        
        NSString *instructionResponse = nil;
        NSString *readInstruction = [NSString stringWithFormat:@"m%llx,4", pc];
        if (!sendDebugCommand(session->debugProxy, readInstruction, &instructionResponse, &commandError)) instructionResponse = nil;
        
        uint32_t instruction = (uint32_t)parseLittleEndianHex64(instructionResponse ?: @"");
        if (instructionResponse.length == 0 || !instructionIsBreakpoint(instruction)) {
            NSString *signal = packetSignal(stopResponse);
            if (signal && !forwardSignalStop(session->debugProxy, signal, threadID, &commandError)) break;
            continue;
        }
        
        uint16_t breakpointImmediate = (instruction >> 5) & 0xffff;
        uint64_t executableAddress = x0;
        
        if (breakpointImmediate == 0xf00d) {
            if (!threadID || !x16Field) break;
            if (!writeRegisterValue(session->debugProxy, @"20", pc + 4, threadID, &commandError)) break;
            
            if (x16 == 0) {
                detachedByCommand = YES;
                
                NSString *detachResponse = nil;
                NSError *detachError = nil;
                if (sendDebugCommand(session->debugProxy, @"D", &detachResponse, &detachError)) {
                    logger([NSString stringWithFormat:@"Detach response for pid %d: %@", pid, detachResponse ?: @"<no response>"], logHandler);
                } else if (!isNotConnectedError(detachError)) {
                    logger([NSString stringWithFormat:@"Detach failed for pid %d: %@", pid, detachError.localizedDescription ?: @"detach failed"], logHandler);
                }
                break;
            }
            
            if (x16 == 1) {
                if (!x1Field) break;
                
                if (executableAddress == 0) {
                    if (!allocateRXRegion(session->debugProxy, x1, &executableAddress, &commandError)) break;
                    logger([NSString stringWithFormat:@"Allocated RX region for pid %d at 0x%llx size=0x%llx", pid, executableAddress, x1], logHandler);
                }
                
                if (!prepareMemoryRegion(session->debugProxy, executableAddress, x1, 0, &commandError)) break;
                if (!writeRegisterValue(session->debugProxy, @"0", executableAddress, threadID, &commandError)) break;
                continue;
            }
            
            if (x16 == 2) {
                logger([NSString stringWithFormat:@"Received unsupported 0xf00d x16 command 0x%llx for pid %d", x16, pid], logHandler);
                if (!writeRegisterValue(session->debugProxy, @"0", 0xE0000002ull, threadID, &commandError)) break;
                continue;
            }
            
            logger([NSString stringWithFormat:@"Received unknown 0xf00d x16 command 0x%llx for pid %d", x16, pid], logHandler);
            if (!writeRegisterValue(session->debugProxy, @"0", (0xE0000000ull | (x16 & 0xffffull)), threadID, &commandError)) break;
            continue;
        } else if (breakpointImmediate == 0x69) {
            if (!x0Field || !x1Field) break;
            
            uint64_t regionSize = x2 != 0 ? x2 : x1;
            uint64_t writableSourceAddress = x2 != 0 ? x1 : 0;
            
            if (!prepareMemoryRegion(session->debugProxy, x0, regionSize, writableSourceAddress, &commandError)) break;
            if (!writeRegisterValue(session->debugProxy, @"20", pc + 4, threadID, &commandError)) break;
        } else {
            continue;
        }
    }
    
    if (!exitPacketPresent && !detachedByCommand) {
        NSString *detachResponse = nil;
        NSError *detachError = nil;
        if (sendDebugCommand(session->debugProxy, @"D", &detachResponse, &detachError)) {
            logger([NSString stringWithFormat:@"Detach response for pid %d: %@", pid, detachResponse ?: @"<no response>"], logHandler);
        } else if (!isNotConnectedError(detachError)) {
            logger([NSString stringWithFormat:@"Detach failed for pid %d: %@", pid, detachError.localizedDescription ?: @"detach failed"], logHandler);
        }
    }
    
    freeDebugSession(session);
    free(session);
}

DeviceProvider *createDeviceProvider(NSString *pairingFilePath, NSString *targetAddress, NSError **error) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:pairingFilePath]) {
        if (error) *error = errorWithCode(-2, @"Pairing file not found in Documents.");
        return NULL;
    }
    
    IdevicePairingFile *pairingFile = NULL;
    IdeviceFfiError *ffiError = idevice_pairing_file_read(pairingFilePath.fileSystemRepresentation, &pairingFile);
    
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Failed to read pairing file."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        return NULL;
    }
    
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(lockdownPort);
    
    if (inet_pton(AF_INET, targetAddress.UTF8String, &address.sin_addr) != 1) {
        idevice_pairing_file_free(pairingFile);
        if (error) *error = errorWithCode(-3, @"Invalid target IP address.");
        return NULL;
    }
    
    IdeviceProviderHandle *providerHandle = NULL;
    ffiError = idevice_tcp_provider_new((const struct sockaddr *)&address, pairingFile, providerLabel, &providerHandle);
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Failed to create idevice provider."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        return NULL;
    }
    
    HeartbeatClientHandle *heartbeatClient = NULL;
    ffiError = heartbeat_connect(providerHandle, &heartbeatClient);
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Failed to connect heartbeat service."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        idevice_provider_free(providerHandle);
        return NULL;
    }
    
    uint64_t nextInterval = 0;
    ffiError = heartbeat_get_marco(heartbeatClient, 15, &nextInterval);
    if (!ffiError) ffiError = heartbeat_send_polo(heartbeatClient);
    
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Heartbeat failed."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        heartbeat_client_free(heartbeatClient);
        idevice_provider_free(providerHandle);
        return NULL;
    }
    
    DeviceProvider *provider = malloc(sizeof(*provider));
    if (!provider) {
        idevice_provider_free(providerHandle);
        if (error) *error = errorWithCode(-5, @"Failed to allocate device provider.");
        return NULL;
    }
    
    provider->handle = providerHandle;
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
        if (error) *error = errorWithCode(-24, @"Missing socket for TLS debugserver session.");
        return NO;
    }
    
    SSLContextRef sslContext = SSLCreateContext(kCFAllocatorDefault, kSSLClientSide, kSSLStreamType);
    if (!sslContext) {
        if (error) *error = errorWithCode(-24, @"Failed to create SSL context for debugserver session.");
        return NO;
    }
    
    OSStatus status = SSLSetIOFuncs(sslContext, legacySSLRead, legacySSLWrite);
    if (status != noErr) {
        if (error) *error = errorWithCode(-24, [NSString stringWithFormat:@"Failed configuring SSL I/O: %@", secureTransportStatusDescription(status)]);
        CFRelease(sslContext);
        return NO;
    }
    
    int *connectionSocket = &connection->socketFD;
    status = SSLSetConnection(sslContext, connectionSocket);
    if (status != noErr) {
        if (error) *error = errorWithCode(-24, [NSString stringWithFormat:@"Failed binding SSL socket: %@", secureTransportStatusDescription(status)]);
        CFRelease(sslContext);
        return NO;
    }
    
    SSLSetProtocolVersionMin(sslContext, kTLSProtocol1);
    SSLSetProtocolVersionMax(sslContext, kTLSProtocol12);
    SSLSetSessionOption(sslContext, kSSLSessionOptionBreakOnServerAuth, true);
    
    NSError *identityError = nil;
    SecIdentityRef identity = copyLegacyPairingIdentity(&identityError);
    if (!identity) {
        if (error) *error = identityError ?: errorWithCode(-24, @"Failed loading pairing identity for TLS debugserver session.");
        CFRelease(sslContext);
        return NO;
    }
    
    const void *identityValues[] = { identity };
    CFArrayRef certificateChain = CFArrayCreate(NULL, identityValues, 1, &kCFTypeArrayCallBacks);
    OSStatus statusSetCert = SSLSetCertificate(sslContext, certificateChain);
    CFRelease(certificateChain);
    CFRelease(identity);
    if (statusSetCert != noErr) {
        if (error) *error = errorWithCode(-24, [NSString stringWithFormat:@"Failed applying pairing identity to TLS session: %@", secureTransportStatusDescription(statusSetCert)]);
        CFRelease(sslContext);
        return NO;
    }
    
    while (YES) {
        status = SSLHandshake(sslContext);
        if (status == noErr) break;
        if (status == errSSLWouldBlock) continue;
        if (status == errSSLServerAuthCompleted) continue;
        
        if (error) *error = errorWithCode(-24, [NSString stringWithFormat:@"Failed TLS handshake with debugserver: %@", secureTransportStatusDescription(status)]);
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
    connection->usesSSL = NO;
}

static BOOL sendAllBytes(LegacyDebugConnection *connection, const uint8_t *bytes, size_t length, NSError **error) {
    if (!connection || connection->socketFD < 0) {
        if (error) *error = errorWithCode(-24, @"Missing debugserver socket.");
        return NO;
    }
    
    size_t bytesWritten = 0;
    while (bytesWritten < length) {
        if (connection->usesSSL) {
            size_t processedLength = length - bytesWritten;
            OSStatus status = SSLWrite(connection->sslContext, bytes + bytesWritten, processedLength, &processedLength);
            
            if (status == noErr) {
                bytesWritten += processedLength;
                continue;
            }
            
            if (status == errSSLWouldBlock) continue;
            
            if (error) {
                NSString *description = [NSString stringWithFormat:@"Failed to send TLS debugserver packet: %@",
                                         secureTransportStatusDescription(status)];
                *error = errorWithCode(-24, description);
            }
            
            return NO;
        }
        
        ssize_t result = send(connection->socketFD, bytes + bytesWritten, length - bytesWritten, 0);
        if (result > 0) {
            bytesWritten += (size_t)result;
            continue;
        }
        
        if (result < 0 && errno == EINTR) continue;
        
        if (error) {
            NSString *description = [NSString stringWithFormat:@"Failed to send debugserver packet: %s", strerror(errno)];
            *error = errorWithCode(-24, description);
        }
        
        return NO;
    }
    
    return YES;
}

static BOOL readByteWithTimeout(LegacyDebugConnection *connection, NSTimeInterval timeout, char *byteOut, BOOL *timedOut, NSError **error) {
    if (timedOut) *timedOut = NO;
    
    if (!connection || connection->socketFD < 0) {
        if (error) *error = errorWithCode(-25, @"Missing debugserver socket.");
        return NO;
    }
    
    if (connection->usesSSL) {
        size_t processedLength = 1;
        OSStatus status = SSLRead(connection->sslContext, byteOut, 1, &processedLength);
        if (status == noErr && processedLength == 1) return YES;
        
        if (status == errSSLWouldBlock) {
            if (timedOut) *timedOut = YES;
            return YES;
        }
        
        if (status == errSSLClosedGraceful || status == errSSLClosedAbort) {
            if (error) *error = errorWithCode(-26, @"Debugserver closed the TLS socket.");
            return NO;
        }
        
        if (error) {
            NSString *description = [NSString stringWithFormat:@"Failed reading TLS debugserver data: %@", secureTransportStatusDescription(status)];
            *error = errorWithCode(-27, description);
        }
        
        return NO;
    }
    
    fd_set readSet;
    FD_ZERO(&readSet);
    FD_SET(connection->socketFD, &readSet);
    
    struct timeval timeoutValue;
    timeoutValue.tv_sec = (time_t)timeout;
    timeoutValue.tv_usec = (suseconds_t)((timeout - timeoutValue.tv_sec) * 1000000.0);
    
    int ready = select(connection->socketFD + 1, &readSet, NULL, NULL, &timeoutValue);
    if (ready == 0) {
        if (timedOut) *timedOut = YES;
        return YES;
    }
    
    if (ready < 0) {
        if (errno == EINTR) return readByteWithTimeout(connection, timeout, byteOut, timedOut, error);
        if (error) {
            NSString *description = [NSString stringWithFormat:@"Failed waiting for debugserver data: %s", strerror(errno)];
            *error = errorWithCode(-25, description);
        }
        return NO;
    }
    
    ssize_t readResult = recv(connection->socketFD, byteOut, 1, 0);
    if (readResult == 1) return YES;
    
    if (readResult == 0) {
        if (error) *error = errorWithCode(-26, @"Debugserver closed the socket.");
        return NO;
    }
    
    if (errno == EINTR) return readByteWithTimeout(connection, timeout, byteOut, timedOut, error);
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
        if (timedOut) *timedOut = YES;
        return YES;
    }
    
    if (error) {
        NSString *description = [NSString stringWithFormat:@"Failed reading debugserver data: %s", strerror(errno)];
        *error = errorWithCode(-27, description);
    }
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
            if (error) *error = errorWithCode(-28, @"Received NACK from debugserver.");
            return NO;
        }
        if (marker != '$') continue;
        
        NSMutableData *payloadData = [NSMutableData data];
        while (YES) {
            char payloadByte = 0;
            timedOut = NO;
            if (!readByteWithTimeout(connection, debugPacketTimeoutSeconds, &payloadByte, &timedOut, error)) return NO;
            if (timedOut) {
                if (error) *error = errorWithCode(-29, @"Timed out while reading debugserver payload.");
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
                if (error) *error = errorWithCode(-30, @"Timed out while reading debugserver checksum.");
                return NO;
            }
        }
        
        unsigned int providedChecksum = 0;
        if (sscanf(checksumChars, "%2x", &providedChecksum) != 1 ||
            (uint8_t)providedChecksum != packetChecksum(payloadData.bytes, payloadData.length)) {
            if (error) *error = errorWithCode(-31, @"Debugserver packet checksum mismatch.");
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
        if (error) *error = errorWithCode(-32, @"Failed to encode legacy debug command.");
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
    if (!sendLegacyDebugPacket(connection, command, error)) return NO;
    return readLegacyDebugResponse(connection, responseOut, error);
}

static BOOL sendLegacyContinueCommand(LegacyDebugConnection *connection, NSString **responseOut, NSError **error) {
    if (!sendLegacyDebugPacket(connection, @"c", error)) return NO;
    
    while (YES) {
        NSString *response = nil;
        if (!readLegacyDebugResponse(connection, &response, error)) return NO;
        if (response.length == 0) continue;
        if (responseOut) *responseOut = response;
        return YES;
    }
}

BOOL connectLegacyDebugSocket(NSString *targetAddress, uint16_t port, BOOL useSSL, LegacyDebugConnection *connectionOut, NSError **error) {
    if (!connectionOut) {
        if (error) *error = errorWithCode(-33, @"Missing output debugserver connection.");
        return NO;
    }
    
    connectionOut->socketFD = -1;
    connectionOut->sslContext = NULL;
    connectionOut->usesSSL = useSSL;
    
    int socketFD = socket(AF_INET, SOCK_STREAM, 0);
    if (socketFD < 0) {
        if (error) {
            NSString *description = [NSString stringWithFormat:@"Failed creating debugserver socket: %s", strerror(errno)];
            *error = errorWithCode(-33, description);
        }
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
        if (error) *error = errorWithCode(-34, @"Invalid legacy debugserver target address.");
        return NO;
    }
    
    if (connect(socketFD, (const struct sockaddr *)&address, sizeof(address)) != 0) {
        NSString *description = [NSString stringWithFormat:@"Failed connecting to legacy debugserver at %@:%u: %s", targetAddress, port, strerror(errno)];
        close(socketFD);
        if (error) *error = errorWithCode(-35, description);
        return NO;
    }
    
    connectionOut->socketFD = socketFD;
    connectionOut->usesSSL = useSSL;
    
    if (useSSL && !configureLegacyDebugTLS(connectionOut, error)) {
        closeLegacyDebugConnection(connectionOut);
        return NO;
    }
    
    return YES;
}

BOOL startLegacyDebugService(DeviceProvider *provider, uint16_t *portOut, BOOL *sslOut, const char **serviceNameOut, NSError **error) {
    LockdowndClientHandle *lockdownClient = NULL;
    IdevicePairingFile *pairingFile = NULL;
    IdeviceFfiError *ffiError = NULL;
    BOOL success = NO;
    
    ffiError = lockdownd_connect(provider->handle, &lockdownClient);
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Failed to connect lockdownd."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        return NO;
    }
    
    ffiError = idevice_provider_get_pairing_file(provider->handle, &pairingFile);
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Failed to get provider pairing file."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        goto cleanup;
    }
    
    ffiError = lockdownd_start_session(lockdownClient, pairingFile);
    if (ffiError) {
        if (error) {
            NSString *description = [NSString stringWithUTF8String:ffiError->message ?: "Failed to start lockdownd session."];
            *error = errorWithCode(ffiError->code, description);
        }
        idevice_error_free(ffiError);
        goto cleanup;
    }
    
    uint16_t sslFallbackPort = 0;
    BOOL sslFallbackValue = NO;
    const char *sslFallbackServiceName = NULL;
    BOOL hasSSLFallback = NO;
    
    for (size_t serviceIndex = 0; serviceIndex < legacyDebugServiceIdentifierCount; serviceIndex++) {
        uint16_t debugPort = 0;
        bool enableSSL = false;
        
        ffiError = lockdownd_start_service(lockdownClient, legacyDebugServiceIdentifiers[serviceIndex], &debugPort, &enableSSL);
        if (ffiError) {
            idevice_error_free(ffiError);
            continue;
        }
        
        if (enableSSL) {
            if (!hasSSLFallback) {
                sslFallbackPort = debugPort;
                sslFallbackValue = YES;
                sslFallbackServiceName = legacyDebugServiceIdentifiers[serviceIndex];
                hasSSLFallback = YES;
            }
            continue;
        }
        
        if (portOut) *portOut = debugPort;
        if (sslOut) *sslOut = enableSSL;
        if (serviceNameOut) *serviceNameOut = legacyDebugServiceIdentifiers[serviceIndex];
        success = YES;
        break;
    }
    
    if (!success && hasSSLFallback) {
        if (portOut) *portOut = sslFallbackPort;
        if (sslOut) *sslOut = sslFallbackValue;
        if (serviceNameOut) *serviceNameOut = sslFallbackServiceName;
        success = YES;
    }
    
    if (!success && error) *error = errorWithCode(-36, @"Unable to start legacy debugserver service via lockdownd.");
    
cleanup:
    if (pairingFile) idevice_pairing_file_free(pairingFile);
    if (lockdownClient) lockdownd_client_free(lockdownClient);
    return success;
}

static BOOL forwardLegacySignalStop(LegacyDebugConnection *connection, NSString *signal, NSString *threadID, NSError **error) {
    NSString *continueCommand = [NSString stringWithFormat:@"vCont;S%@:%@", signal, threadID];
    NSString *stopResponse = nil;
    return sendLegacyDebugCommand(connection, continueCommand, &stopResponse, error);
}

static BOOL writeLegacyRegisterValue(LegacyDebugConnection *connection, NSString *registerName, uint64_t value, NSString *threadID, NSError **error) {
    NSString *response = nil;
    NSString *command = [NSString stringWithFormat:@"P%@=%@;thread:%@;", registerName, encodeLittleEndianHex64(value), threadID];
    
    if (!sendLegacyDebugCommand(connection, command, &response, error)) return NO;
    if (response.length > 0 && ![response isEqualToString:@"OK"]) {
        if (error) *error = errorWithCode(-7, [NSString stringWithFormat:@"Unexpected register write response %@", response]);
        return NO;
    }
    
    return YES;
}

static BOOL prepareLegacyMemoryRegion(LegacyDebugConnection *connection, uint64_t startAddress, uint64_t regionSize, uint64_t writableSourceAddress, NSError **error) {
    uint64_t size = regionSize == 0 ? 0x4000 : regionSize;
    
    for (uint64_t currentAddress = startAddress; currentAddress < startAddress + size; currentAddress += 0x4000) {
        uint64_t sourceAddress = currentAddress;
        if (writableSourceAddress != 0) sourceAddress = writableSourceAddress + (currentAddress - startAddress);
        
        NSString *existingByte = nil;
        NSString *readCommand = [NSString stringWithFormat:@"m%llx,1", sourceAddress];
        if (!sendLegacyDebugCommand(connection, readCommand, &existingByte, error)) return NO;
        
        if (!existingByte || existingByte.length < 2) {
            if (error && !*error) {
                *error = errorWithCode(-12, [NSString stringWithFormat:@"Failed to read prepare-region byte at 0x%llx (source 0x%llx)", currentAddress, sourceAddress]);
            }
            return NO;
        }
        
        NSString *command = [NSString stringWithFormat:@"M%llx,1:%@", currentAddress, [existingByte substringToIndex:2]];
        NSString *response = nil;
        
        if (!sendLegacyDebugCommand(connection, command, &response, error)) return NO;
        if (response.length > 0 && ![response isEqualToString:@"OK"]) {
            if (error) *error = errorWithCode(-7, [NSString stringWithFormat:@"Unexpected prepare-region response %@", response]);
            return NO;
        }
    }
    
    return YES;
}

static BOOL allocateLegacyRXRegion(LegacyDebugConnection *connection, uint64_t regionSize, uint64_t *addressOut, NSError **error) {
    NSString *response = nil;
    NSString *command = [NSString stringWithFormat:@"_M%llx,rx", regionSize];
    
    if (!sendLegacyDebugCommand(connection, command, &response, error)) return NO;
    
    if (response.length == 0) {
        if (error) *error = errorWithCode(-10, @"RX allocation returned an empty response.");
        return NO;
    }
    
    uint64_t address = 0;
    NSScanner *scanner = [NSScanner scannerWithString:response];
    if (![scanner scanHexLongLong:&address]) {
        if (error) *error = errorWithCode(-11, [NSString stringWithFormat:@"RX allocation returned invalid address %@", response]);
        return NO;
    }
    
    if (addressOut) *addressOut = address;
    return YES;
}

void runLegacyDebugService(int32_t pid, LegacyDebugSession *session, DeviceLogHandler logHandler) {
    if (!session) return;
    
    NSError *commandError = nil;
    BOOL exitPacketPresent = NO;
    BOOL detachedByCommand = NO;
    
    while (YES) {
        NSString *stopResponse = nil;
        commandError = nil;
        
        if (!sendLegacyContinueCommand(&session->connection, &stopResponse, &commandError)) {
            if (!isNotConnectedError(commandError)) {
                logger([NSString stringWithFormat:@"Legacy debug loop ended for pid %d: %@", pid, commandError.localizedDescription ?: @"continue failed"], logHandler);
            }
            break;
        }
        
        if ([stopResponse hasPrefix:@"W"] || [stopResponse hasPrefix:@"X"]) {
            exitPacketPresent = YES;
            logger([NSString stringWithFormat:@"Legacy target exited for pid %d with packet %@", pid, stopResponse], logHandler);
            break;
        }
        
        NSString *threadID = packetField(stopResponse, @"thread");
        NSString *pcField = packetField(stopResponse, @"20");
        NSString *x0Field = packetField(stopResponse, @"00");
        NSString *x1Field = packetField(stopResponse, @"01");
        NSString *x2Field = packetField(stopResponse, @"02");
        NSString *x16Field = packetField(stopResponse, @"10");
        
        uint64_t pc = parseLittleEndianHex64(pcField);
        uint64_t x0 = x0Field ? parseLittleEndianHex64(x0Field) : 0;
        uint64_t x1 = x1Field ? parseLittleEndianHex64(x1Field) : 0;
        uint64_t x2 = x2Field ? parseLittleEndianHex64(x2Field) : 0;
        uint64_t x16 = x16Field ? parseLittleEndianHex64(x16Field) : 0;
        
        NSString *instructionResponse = nil;
        NSString *readInstruction = [NSString stringWithFormat:@"m%llx,4", pc];
        if (!sendLegacyDebugCommand(&session->connection, readInstruction, &instructionResponse, &commandError)) instructionResponse = nil;
        
        uint32_t instruction = (uint32_t)parseLittleEndianHex64(instructionResponse ?: @"");
        if (instructionResponse.length == 0 || !instructionIsBreakpoint(instruction)) {
            NSString *signal = packetSignal(stopResponse);
            if (signal && !forwardLegacySignalStop(&session->connection, signal, threadID, &commandError)) break;
            continue;
        }
        
        uint16_t breakpointImmediate = (instruction >> 5) & 0xffff;
        uint64_t executableAddress = x0;
        
        if (breakpointImmediate == 0xf00d) {
            if (!threadID || !x16Field) break;
            if (!writeLegacyRegisterValue(&session->connection, @"20", pc + 4, threadID, &commandError)) break;
            
            if (x16 == 0) {
                detachedByCommand = YES;
                
                NSString *detachResponse = nil;
                NSError *detachError = nil;
                if (sendLegacyDebugCommand(&session->connection, @"D", &detachResponse, &detachError)) {
                    logger([NSString stringWithFormat:@"Legacy detach response for pid %d: %@", pid, detachResponse ?: @"<no response>"], logHandler);
                } else if (!isNotConnectedError(detachError)) {
                    logger([NSString stringWithFormat:@"Legacy detach failed for pid %d: %@", pid, detachError.localizedDescription ?: @"detach failed"], logHandler);
                }
                break;
            }
            
            if (x16 == 1) {
                if (!x1Field) break;
                
                if (executableAddress == 0) {
                    if (!allocateLegacyRXRegion(&session->connection, x1, &executableAddress, &commandError)) break;
                    logger([NSString stringWithFormat:@"Legacy allocated RX region for pid %d at 0x%llx size=0x%llx", pid, executableAddress, x1], logHandler);
                }
                
                if (!prepareLegacyMemoryRegion(&session->connection, executableAddress, x1, 0, &commandError)) break;
                if (!writeLegacyRegisterValue(&session->connection, @"0", executableAddress, threadID, &commandError)) break;
                continue;
            }
            
            if (x16 == 2) {
                logger([NSString stringWithFormat:@"Legacy received unsupported 0xf00d x16 command 0x%llx for pid %d", x16, pid], logHandler);
                if (!writeLegacyRegisterValue(&session->connection, @"0", 0xE0000002ull, threadID, &commandError)) break;
                continue;
            }
            
            logger([NSString stringWithFormat:@"Legacy received unknown 0xf00d x16 command 0x%llx for pid %d", x16, pid], logHandler);
            if (!writeLegacyRegisterValue(&session->connection, @"0", (0xE0000000ull | (x16 & 0xffffull)), threadID, &commandError)) break;
            continue;
        } else if (breakpointImmediate == 0x69) {
            if (!x0Field || !x1Field) break;
            
            uint64_t regionSize = x2 != 0 ? x2 : x1;
            uint64_t writableSourceAddress = x2 != 0 ? x1 : 0;
            
            if (!prepareLegacyMemoryRegion(&session->connection, x0, regionSize, writableSourceAddress, &commandError)) break;
            if (!writeLegacyRegisterValue(&session->connection, @"20", pc + 4, threadID, &commandError)) break;
        } else {
            continue;
        }
    }
    
    if (!exitPacketPresent && !detachedByCommand) {
        NSString *detachResponse = nil;
        NSError *detachError = nil;
        if (sendLegacyDebugCommand(&session->connection, @"D", &detachResponse, &detachError)) {
            logger([NSString stringWithFormat:@"Legacy detach response for pid %d: %@", pid, detachResponse ?: @"<no response>"], logHandler);
        } else if (!isNotConnectedError(detachError)) {
            logger([NSString stringWithFormat:@"Legacy detach failed for pid %d: %@", pid, detachError.localizedDescription ?: @"detach failed"], logHandler);
        }
    }
    
    closeLegacyDebugConnection(&session->connection);
    free(session);
}

