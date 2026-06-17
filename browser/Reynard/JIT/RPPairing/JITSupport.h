//
//  JITSupport.h
//  Reynard
//
//  Created by Minh Ton on 11/3/2026.
//

@import Foundation;
#import <Security/Security.h>

#import "IdeviceFFI.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct DeviceProvider DeviceProvider;

typedef struct {
  int socketFD;
  SSLContextRef sslContext;
} LegacyDebugConnection;

typedef struct {
  AdapterHandle *adapter;
  RsdHandshakeHandle *handshake;
  RemoteServerHandle *remoteServer;
  DebugProxyHandle *debugProxy;
} DebugSession;

dispatch_queue_t debugServiceQueue(void);
dispatch_queue_t debugSessionStateQueue(void);
NSMutableSet<NSNumber *> *activeDebugSessionPIDs(void);
NSMutableSet<NSNumber *> *detachRequestedDebugSessionPIDs(void);

DeviceProvider *_Nullable createDeviceProvider(
    NSString *pairingFilePath, NSString *targetAddress,
    NSError *_Nullable *_Nullable error);
BOOL ensureDDIMounted(DeviceProvider *provider,
                      NSError *_Nullable *_Nullable error);

BOOL sendDebugCommand(DebugProxyHandle *debugProxy, NSString *commandString,
                      NSString *_Nullable *_Nullable responseOut,
                      NSError *_Nullable *_Nullable error);
BOOL configureNoAckMode(DebugProxyHandle *debugProxy,
                        NSString *_Nullable *_Nullable responseOut,
                        NSError *_Nullable *_Nullable error);
BOOL connectDebugSession(DeviceProvider *provider, DebugSession *session,
                         NSString *targetAddress,
                         NSError *_Nullable *_Nullable error);
BOOL connectLegacyDebugSocket(NSString *targetAddress, uint16_t port,
                              LegacyDebugConnection *connectionOut,
                              NSError *_Nullable *_Nullable error);
BOOL startLegacyDebugService(DeviceProvider *provider,
                             uint16_t *_Nullable portOut,
                             NSError *_Nullable *_Nullable error);
BOOL sendLegacyDebugCommand(LegacyDebugConnection *connection,
                            NSString *command,
                            NSString *_Nullable *_Nullable responseOut,
                            NSError *_Nullable *_Nullable error);
BOOL detachDebuggerSession(DebugProxyHandle *debugProxy, int32_t pid);
BOOL detachLegacyDebuggerSession(LegacyDebugConnection *connection,
                                 int32_t pid);
void closeLegacyDebugConnection(LegacyDebugConnection *connection);

void runDebugService(int32_t pid, DebugSession *session);

void registerJITEndpointForPID(int32_t pid, NSString *targetAddress,
                               uint16_t port);
void unregisterJITEndpointForPID(int32_t pid);
void resetJITEndpointMonitor(void);

void freeDebugSession(DebugSession *session);
void freeDeviceProvider(DeviceProvider *_Nullable provider);

NS_ASSUME_NONNULL_END
