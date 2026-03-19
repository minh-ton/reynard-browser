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
typedef void (^DeviceLogHandler)(NSString *message);

typedef struct {
  int socketFD;
  SSLContextRef sslContext;
  BOOL usesSSL;
} LegacyDebugConnection;

typedef struct LegacyDebugSession {
  LegacyDebugConnection connection;
  uint16_t debugPort;
  BOOL usesSSL;
  const char *serviceName;
} LegacyDebugSession;

typedef struct {
  AdapterHandle *adapter;
  RsdHandshakeHandle *handshake;
  RemoteServerHandle *remoteServer;
  DebugProxyHandle *debugProxy;
} DebugSession;

dispatch_queue_t debugServiceQueue(void);

DeviceProvider *_Nullable createDeviceProvider(
    NSString *pairingFilePath, NSString *targetAddress,
    NSError *_Nullable *_Nullable error);

BOOL sendDebugCommand(DebugProxyHandle *debugProxy, NSString *commandString,
                      NSString *_Nullable *_Nullable responseOut,
                      NSError *_Nullable *_Nullable error);
BOOL configureNoAckMode(DebugProxyHandle *debugProxy,
                        NSString *_Nullable *_Nullable responseOut,
                        NSError *_Nullable *_Nullable error);
BOOL connectDebugSession(DeviceProvider *provider, DebugSession *session,
                         NSError *_Nullable *_Nullable error);
BOOL startLegacyDebugService(DeviceProvider *provider,
                             uint16_t *_Nullable portOut,
                             BOOL *_Nullable sslOut,
                             const char *_Nullable *_Nullable serviceNameOut,
                             NSError *_Nullable *_Nullable error);
BOOL connectLegacyDebugSocket(NSString *targetAddress, uint16_t port,
                              BOOL useSSL, LegacyDebugConnection *connectionOut,
                              NSError *_Nullable *_Nullable error);
BOOL sendLegacyDebugCommand(LegacyDebugConnection *connection,
                            NSString *command,
                            NSString *_Nullable *_Nullable responseOut,
                            NSError *_Nullable *_Nullable error);
void closeLegacyDebugConnection(LegacyDebugConnection *connection);

void runDebugService(int32_t pid, DebugSession *session,
                     DeviceLogHandler _Nullable logHandler);
void runLegacyDebugService(int32_t pid, LegacyDebugSession *session,
                           DeviceLogHandler _Nullable logHandler);

void freeDebugSession(DebugSession *session);
void freeDeviceProvider(DeviceProvider *_Nullable provider);

NS_ASSUME_NONNULL_END
