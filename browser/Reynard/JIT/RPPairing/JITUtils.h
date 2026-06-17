//
//  JITUtils.h
//  Reynard
//
//  Created by Minh Ton on 18/3/2026.
//

@import Foundation;
#import <Security/Security.h>

#import "JITErrors.h"

NS_ASSUME_NONNULL_BEGIN

void logger(NSString *message);
NSString *pairingFilePath(void);

uint64_t parseLittleEndianHex64(NSString *hexString);
NSString *encodeLittleEndianHex64(uint64_t value);
NSString *_Nullable packetField(NSString *packet, NSString *fieldName);
NSString *_Nullable packetSignal(NSString *packet);
BOOL instructionIsBreakpoint(uint32_t instruction);
BOOL isNotConnectedError(NSError *error);

NSString *secureTransportStatusDescription(OSStatus status);
SecIdentityRef _Nullable copyLegacyPairingIdentity(
    NSError *_Nullable *_Nullable error);
OSStatus legacySSLRead(SSLConnectionRef connection, void *data,
                       size_t *dataLength);
OSStatus legacySSLWrite(SSLConnectionRef connection, const void *data,
                        size_t *dataLength);
uint8_t packetChecksum(const uint8_t *bytes, size_t length);
void applyLegacyDebugSocketTimeouts(int socketFD);

NS_ASSUME_NONNULL_END
